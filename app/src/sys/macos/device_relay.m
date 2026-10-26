#import "device_relay.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/socket.h>
#include <unistd.h>

const NSTimeInterval SCDeviceRelayLifetime = 5 * 60;

NSArray<NSString *> *SCDeviceRelayAddresses(void) {
    struct ifaddrs *interfaces = NULL;
    NSMutableArray *addresses = [NSMutableArray array];
    if (getifaddrs(&interfaces)) { return addresses; }
    for (struct ifaddrs *entry = interfaces; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET
                || !(entry->ifa_flags & IFF_UP) || (entry->ifa_flags & IFF_LOOPBACK)
                || strncmp(entry->ifa_name, "en", 2)) { continue; }
        char address[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &((struct sockaddr_in *)entry->ifa_addr)->sin_addr,
                address, sizeof(address))) {
            NSString *host = @(address);
            if (![addresses containsObject:host]) { [addresses addObject:host]; }
        }
    }
    freeifaddrs(interfaces);
    return addresses;
}

@interface SCDeviceRelay ()
@property(nonatomic, strong) dispatch_source_t listener;
@property(nonatomic, copy, readwrite) NSString *serviceName;
@property(nonatomic, copy, readonly) NSString *path;
@property(nonatomic, readwrite) uint16_t port;
@property(nonatomic, strong) NSDate *expires;
@property(atomic, copy, readwrite) NSDictionary *registration;
@property(atomic, copy) NSString *bootstrapPeer;
@property(atomic, strong) NSDate *handoffExpires;
@property(atomic) BOOL stopped;
@end

static BOOL SCRelayPort(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()
        && [value doubleValue] == [value integerValue] && [value integerValue] > 0 && [value integerValue] <= 65535;
}

static NSArray<SCDeviceService *> *SCRelayServices(NSData *data, NSString *peer, NSString *name, BOOL reconnect) {
    id report = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![report isKindOfClass:NSDictionary.class]
            || (!reconnect && (![report[@"service"] isEqual:name] || !SCRelayPort(report[@"pairingPort"])))
            || ![report[@"connections"] isKindOfClass:NSArray.class]
            || [report[@"connections"] count] > 8) { return nil; }
    NSMutableArray *services = [NSMutableArray array];
    if (!reconnect) {
        SCDeviceService *pairing = [[SCDeviceService alloc] init];
        pairing.name = name;
        pairing.endpoint = SCDeviceEndpoint(peer, [report[@"pairingPort"] stringValue]);
        pairing.host = peer;
        pairing.pairing = YES;
        if (!pairing.endpoint) { return nil; }
        [services addObject:pairing];
    }
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"] invertedSet];
    for (id entry in report[@"connections"]) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"name"] isKindOfClass:NSString.class]
                || ![entry[@"name"] length] || [entry[@"name"] length] > 255
                || [entry[@"name"] rangeOfCharacterFromSet:invalid].location != NSNotFound
                || !SCRelayPort(entry[@"port"]) || (!reconnect && [entry[@"port"] isEqual:report[@"pairingPort"]])
                || (reconnect && ![entry[@"name"] isEqual:name])) { return nil; }
        SCDeviceService *connection = [[SCDeviceService alloc] init];
        connection.name = entry[@"name"];
        connection.endpoint = SCDeviceEndpoint(peer, [entry[@"port"] stringValue]);
        connection.host = peer;
        [services addObject:connection];
    }
    return services;
}

@implementation SCDeviceRelay
+ (instancetype)listenOnHost:(NSString *)host error:(NSError **)error {
    return [self listenOnHost:host port:0 error:error];
}
+ (instancetype)resumeRegistration:(NSDictionary *)registration error:(NSError **)error {
    if (![registration isKindOfClass:NSDictionary.class] || !SCRelayPort(registration[@"port"])) { return nil; }
    for (NSString *key in @[@"host", @"token", @"guid", @"identity"]) {
        if (![registration[key] isKindOfClass:NSString.class] || ![registration[key] length]
                || [registration[key] length] > 255) { return nil; }
    }
    if ([registration[@"token"] length] != 32 || [registration[@"token"] rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) { return nil; }
    SCDeviceRelay *relay = [self listenOnHost:registration[@"host"] port:[registration[@"port"] intValue] error:error];
    relay.registration = registration;
    // A restored listener never accepts the generated bootstrap route.
    relay.expires = NSDate.distantPast;
    return relay;
}
+ (instancetype)listenOnHost:(NSString *)host port:(uint16_t)port error:(NSError **)error {
    struct in_addr address;
    if (!host.length || inet_pton(AF_INET, host.UTF8String, &address) != 1) { return nil; }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0) { fcntl(fd, F_SETFD, FD_CLOEXEC); }
    int reuse = 1;
    if (fd >= 0) { setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)); }
    struct sockaddr_in local = {.sin_len = sizeof(local), .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_ANY), .sin_port = htons(port)};
    if (fd < 0 || bind(fd, (struct sockaddr *)&local, sizeof(local)) || listen(fd, 8)) {
        int code = errno;
        if (fd >= 0) { close(fd); }
        if (error) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]; }
        return nil;
    }
    socklen_t length = sizeof(local);
    if (getsockname(fd, (struct sockaddr *)&local, &length) || fcntl(fd, F_SETFL, O_NONBLOCK) < 0) {
        int code = errno; close(fd);
        if (error) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]; }
        return nil;
    }
    SCDeviceRelay *relay = [[self alloc] init];
    relay.port = ntohs(local.sin_port);
    NSString *token = [NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    relay.serviceName = [NSString stringWithFormat:@"studio-anmir1-%08x-%04x-%@", ntohl(address.s_addr), relay.port, token];
    relay->_path = [@"/v1/relay/" stringByAppendingString:token];
    relay.expires = [NSDate dateWithTimeIntervalSinceNow:SCDeviceRelayLifetime];
    dispatch_queue_t queue = dispatch_queue_create("io.github.laobie.anmir.relay", DISPATCH_QUEUE_SERIAL);
    relay.listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    __weak SCDeviceRelay *weakRelay = relay;
    dispatch_source_set_event_handler(relay.listener, ^{
        struct sockaddr_in peer;
        socklen_t size = sizeof(peer);
        int client;
        while ((client = accept(fd, (struct sockaddr *)&peer, &size)) >= 0) {
            SCDeviceRelay *current = weakRelay;
            if (current && !current.stopped) { [current handle:client peer:peer]; }
            close(client);
            if (!current || current.stopped) { break; }
            size = sizeof(peer);
        }
    });
    dispatch_source_set_cancel_handler(relay.listener, ^{ close(fd); });
    dispatch_resume(relay.listener);
    return relay;
}

- (void)registerGUID:(NSString *)guid identity:(NSString *)identity peer:(NSString *)peer {
    if (self.registration || !guid.length || !identity.length || !peer.length) { return; }
    NSString *token = [NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSArray *parts = [self.serviceName componentsSeparatedByString:@"-"];
    unsigned int ipv4 = 0;
    [[NSScanner scannerWithString:parts[2]] scanHexInt:&ipv4];
    struct in_addr address = {.s_addr = htonl(ipv4)};
    char host[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &address, host, sizeof(host));
    self.bootstrapPeer = peer;
    self.handoffExpires = [NSDate dateWithTimeIntervalSinceNow:30];
    self.registration = @{@"host": @(host), @"port": @(self.port), @"token": token,
        @"guid": guid, @"identity": identity};
    self.received = nil;
}

- (void)handle:(int)fd peer:(struct sockaddr_in)peer {
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
    struct timeval timeout = {.tv_sec = 3};
    int enabled = 1;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled));
    NSMutableData *request = [NSMutableData data];
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange end = NSMakeRange(NSNotFound, 0);
    NSUInteger bodyLength = 0;
    int status = 400;
    BOOL reconnect = NO;
    NSData *responseBody = [NSData data];
    NSDate *requestDeadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!self.stopped && requestDeadline.timeIntervalSinceNow > 0 && request.length <= 12288) {
        char buffer[2048];
        ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
        if (count <= 0) { break; }
        [request appendBytes:buffer length:count];
        if (end.location == NSNotFound) {
            end = [request rangeOfData:separator options:0 range:NSMakeRange(0, request.length)];
            if (end.location == NSNotFound) {
                if (request.length > 4096) { break; }
                continue;
            }
            if (end.location > 4096) { break; }
            NSString *header = [[NSString alloc] initWithData:[request subdataWithRange:NSMakeRange(0, end.location)]
                encoding:NSUTF8StringEncoding];
            NSArray *lines = [header componentsSeparatedByString:@"\r\n"];
            NSString *expected = [NSString stringWithFormat:@"POST %@ HTTP/1.1", self.path];
            NSDictionary *registration = self.registration;
            reconnect = registration && [lines.firstObject isEqualToString:
                [NSString stringWithFormat:@"POST /v1/reconnect/%@ HTTP/1.1", registration[@"token"]]];
            if (!reconnect && ![lines.firstObject isEqualToString:expected]) { status = 404; break; }
            BOOL valid = YES, foundLength = NO;
            for (NSString *line in [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)]) {
                NSString *lower = line.lowercaseString;
                if ([lower hasPrefix:@"transfer-encoding:"]) { valid = NO; break; }
                if ([lower hasPrefix:@"content-length:"]) {
                    NSString *value = [[line substringFromIndex:15] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                    if (foundLength || !value.length || [value rangeOfCharacterFromSet:
                            [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) {
                        valid = NO; break;
                    }
                    foundLength = YES;
                    bodyLength = value.integerValue;
                }
            }
            if (!valid || !foundLength || !bodyLength || bodyLength > 8192) { break; }
        }
        if (request.length < NSMaxRange(end) + bodyLength) { continue; }
        NSDictionary *registration = self.registration;
        if (!reconnect && (registration ? self.handoffExpires.timeIntervalSinceNow <= 0
                                        : self.expires.timeIntervalSinceNow <= 0)) { status = 410; break; }
        char host[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, &peer.sin_addr, host, sizeof(host))) { break; }
        if (!reconnect && registration && ![self.bootstrapPeer isEqualToString:@(host)]) { status = 404; break; }
        NSArray *services = SCRelayServices([request subdataWithRange:NSMakeRange(NSMaxRange(end), bodyLength)],
            @(host), reconnect ? registration[@"guid"] : self.serviceName, reconnect);
        if (!services) { break; }
        id retryValue = [[NSJSONSerialization JSONObjectWithData:
            [request subdataWithRange:NSMakeRange(NSMaxRange(end), bodyLength)] options:0 error:nil] objectForKey:@"retry"];
        if (retryValue && CFGetTypeID((__bridge CFTypeRef)retryValue) != CFBooleanGetTypeID()) { break; }
        BOOL retry = [retryValue boolValue];
        if (!reconnect && registration) {
            responseBody = [NSJSONSerialization dataWithJSONObject:@{@"reconnect": @{
                @"port": registration[@"port"], @"token": registration[@"token"], @"guid": registration[@"guid"]}}
                options:0 error:nil];
            status = 201;
            break;
        }
        __weak SCDeviceRelay *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            SCDeviceRelay *relay = weakSelf;
            if (relay.listener && !relay.stopped) {
                if (reconnect && relay.reconnected) { relay.reconnected(services, retry); }
                else if (!relay.registration && relay.expires.timeIntervalSinceNow > 0 && relay.received) { relay.received(services); }
            }
        });
        status = 202;
        break;
    }
    NSString *reply = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        status, status == 201 || status == 202 ? @"Accepted" : @"Rejected", (unsigned long)responseBody.length];
    NSMutableData *bytes = [[reply dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [bytes appendData:responseBody];
    NSUInteger sent = 0;
    while (sent < bytes.length) {
        ssize_t count = send(fd, (const char *)bytes.bytes + sent, bytes.length - sent, 0);
        if (count <= 0) { break; }
        sent += count;
    }
}

- (void)stop {
    self.stopped = YES;
    if (self.listener) { dispatch_source_cancel(self.listener); self.listener = nil; }
    self.received = nil;
    self.reconnected = nil;
}
- (void)dealloc { if (_listener) { dispatch_source_cancel(_listener); } }
@end
