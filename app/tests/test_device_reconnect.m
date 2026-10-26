#import <Foundation/Foundation.h>
#import "sys/macos/device_reconnect.h"
#import "sys/macos/device_connection.h"
#include <assert.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
@interface SCDeviceReconnect (TestTick)
- (void)tick;
@end

static NSString *statePath;
static void waitFor(BOOL (^condition)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && end.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
    assert(condition());
}
static void state(BOOL online, NSString *identity) {
    [@{@"online": @(online), @"identity": identity} writeToFile:statePath atomically:YES];
}
static int fixture(const char *argv[]) {
    NSDictionary *value = [NSDictionary dictionaryWithContentsOfFile:statePath];
    if (!strcmp(argv[1], "connect")) { puts([value[@"online"] boolValue] ? "connected to phone" : "failed to connect to phone"); }
    else if (!strcmp(argv[3], "get-state")) { puts([value[@"online"] boolValue] ? "device" : "offline"); }
    else { printf("[ro.serialno]: [%s]\n[ro.product.model]: [Test phone]\n", [value[@"identity"] UTF8String]); }
    return 0;
}
static NSString *report(SCDeviceRelay *relay, int port, BOOL retry) {
    NSArray *ports = port ? @[@{@"name": @"adb-phone", @"port": @(port)}] : @[];
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"connections":ports, @"retry":@(retry)} options:0 error:nil];
    int fd = socket(AF_INET, SOCK_STREAM, 0); assert(fd >= 0);
    struct sockaddr_in address = {.sin_len=sizeof(address), .sin_family=AF_INET,
        .sin_addr.s_addr=htonl(INADDR_LOOPBACK), .sin_port=htons(relay.port)};
    assert(!connect(fd, (struct sockaddr *)&address, sizeof(address)));
    NSString *header = [NSString stringWithFormat:@"POST /v1/reconnect/%@ HTTP/1.1\r\nContent-Length: %lu\r\n\r\n",
        relay.registration[@"token"], (unsigned long)body.length];
    NSData *prefix = [header dataUsingEncoding:NSUTF8StringEncoding];
    send(fd, prefix.bytes, prefix.length, 0); send(fd, body.bytes, body.length, 0);
    char bytes[512]; ssize_t count = recv(fd, bytes, sizeof(bytes), 0); close(fd); assert(count > 0);
    return [[NSString alloc] initWithBytes:bytes length:count encoding:NSUTF8StringEncoding];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *executable = [NSString stringWithUTF8String:argv[0]].stringByStandardizingPath;
        statePath = [executable stringByAppendingString:@".fixture.plist"];
        if (argc > 2) { return fixture(argv); }
        NSString *suite = [@"anmir-reconnect-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        state(YES, @"test-phone");
        SCDeviceReconnect *owner = [[SCDeviceReconnect alloc] initWithExecutable:executable defaults:defaults];
        SCDeviceRelay *relay = [SCDeviceRelay listenOnHost:@"192.0.2.10" error:nil];
        NSDictionary *properties = @{@"ro.serialno": @"test-phone"};
        assert([owner rememberRelay:relay guid:@"adb-phone" serial:@"127.0.0.1:37123" properties:properties]);
        assert(owner.active);
        __block NSUInteger restores = 0;
        owner.restoreMirror = ^BOOL(NSString *serial, NSDictionary *props) {
            assert([props[@"ro.serialno"] isEqualToString:@"test-phone"]);
            assert([serial hasPrefix:@"127.0.0.1:"]); ++restores; return YES;
        };
        id phone = [[owner valueForKey:@"phones"] firstObject];
        assert([report(relay, 37124, NO) containsString:@"202"]);
        waitFor(^BOOL { return restores == 1; }); // Changed IP/port restores an interrupted mirror.
        [owner mirrorEnded:@"127.0.0.1:37124" properties:properties unexpected:NO];
        assert([report(relay, 37125, NO) containsString:@"202"]);
        waitFor(^BOOL { return [[phone valueForKey:@"serial"] isEqualToString:@"127.0.0.1:37125"]; });
        assert(restores == 1); // Closing a mirror intentionally must suppress reopening.
        [owner mirroringSerial:@"127.0.0.1:37125" properties:properties];
        state(NO, @"test-phone");
        assert([report(relay, 37125, YES) containsString:@"202"]); // Manual retry bypasses the health deadline.
        waitFor(^BOOL { return [[phone valueForKey:@"failures"] integerValue] == 1; });
        assert(![[phone valueForKey:@"connected"] boolValue]);
        NSDate *due = [phone valueForKey:@"nextAttempt"];
        assert(due.timeIntervalSinceNow > 1 && due.timeIntervalSinceNow <= 2);
        [owner tick];
        assert([[phone valueForKey:@"failures"] integerValue] == 1); // Backoff is honored.
        state(YES, @"test-phone");
        assert([report(relay, 37126, NO) containsString:@"202"]);
        waitFor(^BOOL { return restores == 2; });
        state(YES, @"other-phone");
        assert([report(relay, 37127, NO) containsString:@"202"]);
        waitFor(^BOOL { return [[phone valueForKey:@"failures"] integerValue] == 1; });
        assert(restores == 2 && ![[phone valueForKey:@"connected"] boolValue]); // A valid token cannot substitute a different paired device.
        uint16_t savedPort = relay.port;
        [owner stop]; assert(!owner.active);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        state(YES, @"test-phone");
        owner = [[SCDeviceReconnect alloc] initWithExecutable:executable defaults:defaults];
        phone = [[owner valueForKey:@"phones"] firstObject];
        relay = [phone valueForKey:@"relay"];
        assert(relay.port == savedPort);
        assert([report(relay, 37128, NO) containsString:@"202"]);
        waitFor(^BOOL { return [[phone valueForKey:@"connected"] boolValue]; });
        assert(![[phone valueForKey:@"mirrorWanted"] boolValue]); // Restart remembers trust, not an old window-opening intent.
        [owner stop]; [defaults removePersistentDomainForName:suite];
        [NSFileManager.defaultManager removeItemAtPath:statePath error:nil];
        puts("Reconnect persistence, changed ports, identity verification, backoff, manual retry and intentional close passed.");
    }
    return 0;
}
