#import <Foundation/Foundation.h>
#import "sys/macos/device_relay.h"
#import "sys/macos/device_pairing.h"
#include <assert.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

static void waitFor(BOOL (^condition)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && end.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
    assert(condition());
}

static NSString *sendReport(SCDeviceRelay *relay, NSString *path, id report, BOOL chunked) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    assert(fd >= 0);
    struct sockaddr_in address = {.sin_len = sizeof(address), .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK), .sin_port = htons(relay.port)};
    assert(!connect(fd, (struct sockaddr *)&address, sizeof(address)));
    NSString *header = [NSString stringWithFormat:@"POST %@ HTTP/1.1\r\nContent-Length: %lu\r\n%@\r\n",
        path, (unsigned long)body.length, chunked ? @"Transfer-Encoding: chunked\r\n" : @""];
    NSData *prefix = [header dataUsingEncoding:NSUTF8StringEncoding];
    assert(send(fd, prefix.bytes, prefix.length, 0) == (ssize_t)prefix.length);
    assert(send(fd, body.bytes, body.length, 0) == (ssize_t)body.length);
    NSMutableData *reply = [NSMutableData data];
    char buffer[512]; ssize_t length;
    while ((length = recv(fd, buffer, sizeof(buffer), 0)) > 0) { [reply appendBytes:buffer length:length]; }
    close(fd);
    assert(reply.length > 0);
    return [[NSString alloc] initWithData:reply encoding:NSUTF8StringEncoding];
}

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        SCDeviceRelay *relay = [SCDeviceRelay listenOnHost:@"192.0.2.10" error:&error];
        assert(relay && !error && relay.port);
        assert(relay.serviceName.length == 60);
        SCDeviceQRPairing *qr = [[SCDeviceQRPairing alloc] initWithServiceName:relay.serviceName];
        assert(qr.image && [qr.payload containsString:relay.serviceName]);
        NSString *path = [@"/v1/relay/" stringByAppendingString:[relay.serviceName componentsSeparatedByString:@"-"].lastObject];
        __block NSUInteger received = 0;
        relay.received = ^(NSArray<SCDeviceService *> *services) {
            assert(NSThread.isMainThread && services.count == 2);
            assert(services[0].pairing && !services[1].pairing);
            assert([services[0].endpoint isEqualToString:@"127.0.0.1:42187"]);
            assert([services[1].endpoint isEqualToString:@"127.0.0.1:37123"]);
            ++received;
        };
        NSDictionary *report = @{@"service": relay.serviceName, @"pairingPort": @42187,
            @"connections": @[@{@"name": @"adb-test", @"port": @37123}],
            @"host": @"192.0.2.99"}; // Never trust a supplied address over the TCP peer.
        assert([sendReport(relay, @"/wrong-session", report, NO) containsString:@"404"]);
        assert([sendReport(relay, path, report, YES) containsString:@"400"]);
        NSMutableDictionary *invalid = [report mutableCopy];
        invalid[@"pairingPort"] = @YES;
        assert([sendReport(relay, path, invalid, NO) containsString:@"400"]);
        invalid[@"pairingPort"] = @70000;
        assert([sendReport(relay, path, invalid, NO) containsString:@"400"]);
        invalid[@"pairingPort"] = @42187;
        invalid[@"service"] = @"studio-other";
        assert([sendReport(relay, path, invalid, NO) containsString:@"400"]);
        assert([sendReport(relay, path, report, NO) containsString:@"202"]);
        waitFor(^BOOL { return received == 1; });
        [relay setValue:NSDate.distantPast forKey:@"expires"];
        assert([sendReport(relay, path, report, NO) containsString:@"410"]);
        [relay setValue:[NSDate dateWithTimeIntervalSinceNow:10] forKey:@"expires"];
        assert([sendReport(relay, path, report, NO) containsString:@"202"]);
        [relay stop];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        assert(received == 1);
        relay = [SCDeviceRelay listenOnHost:@"192.0.2.10" error:&error];
        path = [@"/v1/relay/" stringByAppendingString:[relay.serviceName componentsSeparatedByString:@"-"].lastObject];
        report = @{@"service": relay.serviceName, @"pairingPort": @42187,
            @"connections": @[@{@"name": @"adb-test", @"port": @37123}]};
        [relay registerGUID:@"adb-test" identity:@"physical-phone" peer:@"127.0.0.1"];
        assert(![relay.registration[@"token"] isEqual:[relay.serviceName componentsSeparatedByString:@"-"].lastObject]);
        NSString *handoff = sendReport(relay, path, report, NO);
        assert([handoff containsString:@"201"] && [handoff containsString:relay.registration[@"token"]]);
        assert(![handoff containsString:@"physical-phone"]);
        NSString *reconnectPath = [@"/v1/reconnect/" stringByAppendingString:relay.registration[@"token"]];
        __block NSUInteger callbacks = 0;
        relay.reconnected = ^(NSArray *services, BOOL retry) {
            assert(!retry);
            assert(NSThread.isMainThread && services.count == 1);
            assert([[(SCDeviceService *)services[0] endpoint] isEqualToString:@"127.0.0.1:37124"]);
            ++callbacks;
        };
        NSDictionary *ports = @{@"connections": @[@{@"name": @"adb-test", @"port": @37124}], @"host": @"192.0.2.99"};
        assert([sendReport(relay, reconnectPath, ports, NO) containsString:@"202"]);
        waitFor(^BOOL { return callbacks == 1; });
        assert([sendReport(relay, reconnectPath, @{@"connections": @[@{@"name": @"adb-other", @"port": @37124}]}, NO) containsString:@"400"]);
        [relay setValue:NSDate.distantPast forKey:@"handoffExpires"];
        assert([sendReport(relay, path, report, NO) containsString:@"410"]);
        assert([sendReport(relay, reconnectPath, ports, NO) containsString:@"202"]);
        waitFor(^BOOL { return callbacks == 2; });
        NSDictionary *registration = relay.registration;
        uint16_t savedPort = relay.port;
        [relay stop];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        relay = [SCDeviceRelay resumeRegistration:registration error:&error];
        assert(relay.port == savedPort && [relay.registration isEqual:registration]);
        assert([sendReport(relay, reconnectPath, ports, NO) containsString:@"202"]);
        [relay stop];
        puts("Relay listener, session binding, peer address, validation, expiry and delivery passed.");
    }
    return 0;
}
