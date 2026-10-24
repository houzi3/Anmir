#import <Foundation/Foundation.h>
#import "sys/macos/device_support.h"
#include <assert.h>
#include <unistd.h>

static void waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && end.timeIntervalSinceNow > 0) {
        @autoreleasepool {
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    assert(condition());
}

static void testParsing(void) {
    assert([SCDeviceEndpoint(@" 192.168.1.42 ", @"37123") isEqualToString:@"192.168.1.42:37123"]);
    assert([SCDeviceEndpoint(@"192.168.1.42:37123", nil) isEqualToString:@"192.168.1.42:37123"]);
    assert([SCDeviceEndpoint(@"::1", @"5555") isEqualToString:@"[::1]:5555"]);
    assert([SCDeviceHost(@"[fe80::1%en0]:12345") isEqualToString:@"fe80::1%en0"]);
    for (NSString *value in @[@"", @"host:12345", @"192.168.1.42", @"192.168.1.999:1", @"::1:5555", @"[::1]:0", @"[::1]:65536", @"1.2.3.4:1;echo", @"[fe80::1%]:1234"]) {
        assert(!SCDeviceEndpoint(value, nil));
    }
    assert(!SCDeviceEndpoint(@"", @"5555"));
    assert(SCDevicePairingCodeValid(@"012345"));
    for (NSString *code in @[@"12345", @"1234567", @"12345a", @"１２３４５６", @"123 45"]) {
        assert(!SCDevicePairingCodeValid(code));
    }
    assert(SCDevicePairSucceeded(@"Enter pairing code: Successfully paired to 192.168.1.42:42187 [guid=adb-device]", 0));
    assert(!SCDevicePairSucceeded(@"Successfully paired to device", 1));
    assert(SCDeviceConnectSucceeded(@"* daemon started successfully\nconnected to 192.168.1.42:37123\n", 0));
    assert(SCDeviceConnectSucceeded(@"already connected to 192.168.1.42:37123", 0));
    assert(!SCDeviceConnectSucceeded(@"failed to connect to 192.168.1.42:37123", 0));
    assert(!SCDeviceConnectSucceeded(@"connected to 192.168.1.42:37123", 1));
    NSDictionary *props = SCDeviceProperties(@"[ro.product.model]: [Pixel 7]\n[ro.build.version.sdk]: [36]\n[empty]: []\nbad\n");
    assert([props[@"ro.product.model"] isEqualToString:@"Pixel 7"]);
    assert([props[@"ro.build.version.sdk"] isEqualToString:@"36"]);
    assert([props[@"empty"] isEqualToString:@""]);
    NSArray<SCDeviceService *> *services = [SCDeviceService parse:@"List of discovered mdns services\nadb-test _adb-tls-pairing._tcp. 192.168.1.42:42187\nadb-test _adb-tls-connect._tcp. 192.168.1.42:37123\nadb-test _adb-tls-connect._tcp. 192.168.1.42:37123\nnoise _other._tcp 192.168.1.42:99\ninvalid _adb-tls-pairing._tcp. nope\nv6 _adb-tls-connect._tcp [::1]:5555\n"];
    assert(services.count == 3);
    assert(services[0].pairing && !services[1].pairing);
    assert([services[0].host isEqualToString:services[1].host]);
    assert(![services[0].endpoint isEqualToString:services[1].endpoint]);
    services = [SCDeviceService parse:@"adb-phone _adb-tls-pairing._tcp 192.168.1.42:42187\nstudio-code _adb-tls-pairing._tcp. 192.168.1.42:42187\nstudio-code _adb-tls-pairing._tcp 192.168.1.42:42187\n"];
    assert(services.count == 2);
    assert([services[1].name isEqualToString:@"studio-code"]);
}

static void testPhysicalDevices(void) {
    assert([SCDevicePhysicalIdentity(@{@"ro.serialno": @"527f6d76"}) isEqualToString:@"527f6d76"]);
    assert(([SCDevicePhysicalIdentity(@{@"ro.serialno": @"unknown", @"ro.boot.serialno": @"boot-serial"})
        isEqualToString:@"boot-serial"]));
    assert(!SCDevicePhysicalIdentity(@{}));
    assert((!SCDevicePhysicalIdentity(@{@"ro.serialno": @"  ", @"ro.boot.serialno": @"null"})));
    NSString *ip = @"192.168.31.249:33281";
    NSString *mdns = @"adb-527f6d76-FqVSxm._adb-tls-connect._tcp";
    NSString *usb = @"527f6d76";
    NSString *other = @"192.168.31.250:33281";
    NSArray *transports = @[ip, mdns, usb, other];
    NSDictionary *identities = @{ip: @"527f6d76", mdns: @"527f6d76", usb: @"527f6d76", other: @"different-phone"};
    NSArray<NSArray<NSString *> *> *groups = SCDeviceTransportGroups(transports, identities, [NSSet set]);
    assert(groups.count == 2 && groups[0].count == 3 && groups[1].count == 1);
    assert([groups[0].firstObject isEqualToString:ip]);
    // Missing properties must not merge unrelated/offline/unauthorized devices.
    groups = SCDeviceTransportGroups(transports, @{}, [NSSet set]);
    assert(groups.count == 4);
    groups = SCDeviceTransportGroups(@[other, mdns, ip], identities, [NSSet set]);
    assert(groups.count == 2 && [groups[0].firstObject isEqualToString:other]);
    assert(groups[1].count == 2);
    groups = SCDeviceTransportGroups(@[mdns, other], identities, [NSSet set]);
    assert(groups.count == 2); // Losing one transport does not lose the phone.
    assert(SCDeviceTransportGroups(@[], identities, [NSSet set]).count == 0);
    // A second transport can arrive while its asynchronous getprop is pending.
    // It must never flash as a second phone, including on initial discovery.
    groups = SCDeviceTransportGroups(@[mdns, ip], @{mdns: @"527f6d76"}, [NSSet setWithObject:ip]);
    assert(groups.count == 1 && groups[0].count == 1);
    groups = SCDeviceTransportGroups(@[mdns, ip], @{}, [NSSet setWithArray:@[mdns, ip]]);
    assert(groups.count == 0);
    groups = SCDeviceTransportGroups(@[mdns, ip], identities, [NSSet set]);
    assert(groups.count == 1 && groups[0].count == 2);
    // Independent phones still appear separately once identified; an unknown
    // phone also appears after its lookup fails rather than disappearing.
    groups = SCDeviceTransportGroups(@[mdns, other], @{mdns: @"527f6d76"}, [NSSet set]);
    assert(groups.count == 2);

}

static void testCommands(NSString *executable) {
    __block BOOL done = NO;
    [SCDeviceCommand run:executable arguments:@[@"--fixture", @"echo"] input:@"012345\n" timeout:2 completion:^(NSString *output, int status) {
        assert(NSThread.isMainThread);
        assert(!status && [output isEqualToString:@"012345\n"]);
        done = YES;
    }];
    waitFor(^BOOL { return done; }, 3);
    done = NO;
    [SCDeviceCommand run:executable arguments:@[@"--fixture", @"large"] input:nil timeout:2 completion:^(NSString *output, int status) {
        assert(!status && output.length == 131072); done = YES;
    }];
    waitFor(^BOOL { return done; }, 3);
    done = NO;
    [SCDeviceCommand run:executable arguments:@[@"--fixture", @"hang"] input:nil timeout:0.1 completion:^(NSString *output, int status) {
        (void)output; assert(status == -3); done = YES;
    }];
    waitFor(^BOOL { return done; }, 3);
    done = NO;
    SCDeviceCommand *command = [SCDeviceCommand run:executable arguments:@[@"--fixture", @"hang"] input:nil timeout:5 completion:^(NSString *output, int status) {
        (void)output; assert(status == -2); done = YES;
    }];
    [command cancel];
    waitFor(^BOOL { return done; }, 3);
    done = NO;
    [SCDeviceCommand run:@"/does/not/exist/adb" arguments:@[] input:nil timeout:1 completion:^(NSString *output, int status) {
        assert(status == -1 && output.length); done = YES;
    }];
    waitFor(^BOOL { return done; }, 2);
}

static void testWatcher(NSString *executable) {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *script = [directory stringByAppendingPathComponent:@"adb"];
    NSString *marker = [directory stringByAppendingPathComponent:@"started"];
    NSString *body = [NSString stringWithFormat:@"#!/bin/sh\nprintf 'device device\\n'\nif [ ! -f '%@' ]; then touch '%@'; /bin/sleep 0.1; exit 1; fi\nexec /bin/sleep 30\n", marker, marker];
    [body writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:script error:nil];
    SCDeviceWatcher *watcher = [[SCDeviceWatcher alloc] initWithExecutable:script];
    __block NSUInteger changes = 0;
    watcher.changed = ^{ ++changes; };
    [watcher start];
    waitFor(^BOOL { return changes >= 2 && watcher.connected; }, 5);
    [watcher stop];
    assert(!watcher.connected);
    NSUInteger stopped = changes;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
    assert(changes == stopped);
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    (void)executable;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc >= 3 && !strcmp(argv[1], "--fixture")) {
            if (!strcmp(argv[2], "echo")) { char line[64]; if (fgets(line, sizeof(line), stdin)) { fputs(line, stdout); } }
            else if (!strcmp(argv[2], "large")) { for (int i = 0; i < 131072; ++i) { putchar('x'); } }
            else if (!strcmp(argv[2], "hang")) { sleep(30); }
            return 0;
        }
        testParsing();
        testPhysicalDevices();
        NSString *executable = [NSString stringWithUTF8String:argv[0]].stringByStandardizingPath;
        testCommands(executable);
        testWatcher(executable);
        puts("Device support tests passed.");
    }
    return 0;
}
