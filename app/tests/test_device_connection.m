#import <Foundation/Foundation.h>
#import "sys/macos/device_connection.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void waitFor(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && end.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    assert(condition());
}

// The test executable is also a deterministic ADB fixture. No real devices,
// network addresses, desktop applications or system settings are touched.
static int fixture(int argc, const char *argv[]) {
    if (!strcmp(argv[1], "pair")) {
        if (strstr(argv[2], ":42190")) { sleep(30); return 1; }
        char secret[64];
        if (!fgets(secret, sizeof(secret), stdin) || strcmp(secret, "012345\n")) { return 1; }
        if (strstr(argv[2], ":42188")) { puts("pairing failed"); return 1; }
        printf("Successfully paired to %s%s\n", argv[2],
            strstr(argv[2], ":42189") ? "" : " [guid=adb-phone]");
    } else if (!strcmp(argv[1], "connect")) {
        printf("%s %s\n", strstr(argv[2], ":37124") ? "failed to connect to" : "connected to", argv[2]);
    } else if (argc >= 4 && !strcmp(argv[1], "-s")) {
        if (!strcmp(argv[3], "get-state")) {
            puts(strstr(argv[2], ":37125") ? "unauthorized" : "device");
        } else if (!strstr(argv[2], ":37126")) {
            puts("[ro.product.model]: [Test phone]\n[ro.serialno]: [test-phone]");
        }
    } else { return 1; }
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 2) { return fixture(argc, argv); }
        NSString *executable = [NSString stringWithUTF8String:argv[0]].stringByStandardizingPath;
        SCDeviceConnection *connection = [[SCDeviceConnection alloc] initWithExecutable:executable];
        NSMutableArray *phases = [NSMutableArray array];
        __weak SCDeviceConnection *weakConnection = connection;
        connection.changed = ^{
            assert(NSThread.isMainThread);
            [phases addObject:@(weakConnection.phase)];
        };
        [connection connectEndpoint:@"192.0.2.1:37123"];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionReady; }, 4);
        assert(!connection.busy && !connection.paired && !connection.error);
        assert([connection.properties[@"ro.serialno"] isEqualToString:@"test-phone"]);
        assert(([phases isEqualToArray:@[@(SCDeviceConnectionConnecting),
            @(SCDeviceConnectionVerifying), @(SCDeviceConnectionIdentifying), @(SCDeviceConnectionReady)]]));

        // A same-host advertisement with the wrong GUID must never be used.
        [connection updateServices:[SCDeviceService parse:
            @"adb-other _adb-tls-connect._tcp 192.0.2.1:37123"]];
        [connection pairEndpoint:@"192.0.2.1:42187" secret:@"012345"
            serviceName:nil requireGUID:YES];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionWaitingForService; }, 3);
        assert(connection.paired && connection.busy);
        [connection updateServices:[SCDeviceService parse:
            @"adb-phone _adb-tls-connect._tcp 192.0.2.2:37123"]];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionReady; }, 4);
        assert([connection.serial isEqualToString:@"192.0.2.2:37123"]);

        // QR pairing without a GUID falls back without pairing a second time.
        [connection pairEndpoint:@"192.0.2.1:42189" secret:@"012345"
            serviceName:nil requireGUID:YES];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionNeedsAddress; }, 3);
        assert(connection.paired && !connection.busy && !connection.error);
        [connection connectEndpoint:@"192.0.2.1:37123"];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionReady; }, 4);
        assert(connection.paired);

        [connection updateServices:[SCDeviceService parse:
            @"adb-phone _adb-tls-connect._tcp 192.0.2.1:37124"]];
        [connection pairEndpoint:@"192.0.2.1:42187" secret:@"012345"
            serviceName:nil requireGUID:YES];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionNeedsAddress; }, 4);
        assert(connection.paired && !connection.busy);

        for (NSString *endpoint in @[@"192.0.2.1:37124", @"192.0.2.1:37125", @"192.0.2.1:37126"]) {
            [connection connectEndpoint:endpoint];
            waitFor(^BOOL { return connection.phase == SCDeviceConnectionFailed; }, 4);
            assert(connection.error && !connection.busy && !connection.serial.length);
        }
        [connection pairEndpoint:@"192.0.2.1:42188" secret:@"012345"
            serviceName:nil requireGUID:NO];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionFailed; }, 3);
        assert(!connection.paired);

        [connection pairEndpoint:@"192.0.2.1:42190" secret:@"012345"
            serviceName:nil requireGUID:NO];
        [connection cancel];
        NSUInteger count = phases.count;
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        assert(connection.phase == SCDeviceConnectionIdle && !connection.busy);
        assert(phases.count == count); // Cancelled completion cannot change a new view.

        [connection updateServices:@[]];
        [connection pairEndpoint:@"192.0.2.1:42187" secret:@"012345"
            serviceName:nil requireGUID:YES];
        waitFor(^BOOL { return connection.phase == SCDeviceConnectionNeedsAddress; }, 15);
        assert(connection.paired && !connection.busy); // Real service deadline.
        [connection cancel];
        connection.changed = nil;
        puts("Wi-Fi connection stages, identity, fallback, errors, cancellation and deadline passed.");
    }
    return 0;
}
