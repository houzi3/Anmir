#import <Foundation/Foundation.h>
#import "sys/macos/mirror_session.h"
#include <assert.h>
#include <string.h>

static dispatch_semaphore_t preparedSignal;
static NSURL *cancelledRoot;
@interface SCCancelledMirrorLaunch : SCMirrorLaunch
@end
@implementation SCCancelledMirrorLaunch
+ (instancetype)prepareWithName:(NSString *)name serial:(NSString *)serial
    hostBundle:(NSBundle *)host error:(NSError **)error {
    assert(!NSThread.isMainThread);
    SCCancelledMirrorLaunch *launch = [super prepareWithName:name serial:serial hostBundle:host error:error];
    cancelledRoot = launch.bundleURL.URLByDeletingLastPathComponent;
    dispatch_semaphore_signal(preparedSignal);
    return launch;
}
@end

static void waitFor(BOOL (^condition)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && end.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    assert(condition());
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 3 && !strcmp(argv[1], "--check-host-bundle")) {
            NSString *expected = [NSString stringWithUTF8String:argv[2]];
            NSBundle *host = SCMirrorHostBundle();
            assert([host.bundlePath.stringByResolvingSymlinksInPath
                isEqualToString:expected.stringByResolvingSymlinksInPath]);
            assert(![host.bundlePath isEqualToString:NSBundle.mainBundle.bundlePath]);
            assert([SCMirrorHostBundleIdentifier() isEqualToString:host.bundleIdentifier]);
            return 0;
        }
        NSArray *arguments = SCMirrorArguments(@[@"scrcpy", @"-s", @"old", @"--serial=other",
            @"-d", @"--tcpip=192.0.2.1", @"--no-audio"], @"new");
        assert(([arguments isEqualToArray:@[@"--serial", @"new", @"--no-audio"]]));
        NSFileManager *files = NSFileManager.defaultManager;
        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *hostURL = [root URLByAppendingPathComponent:@"Host.app"];
        NSURL *contents = [hostURL URLByAppendingPathComponent:@"Contents"];
        NSURL *macOS = [contents URLByAppendingPathComponent:@"MacOS"];
        NSURL *resources = [contents URLByAppendingPathComponent:@"Resources"];
        assert([files createDirectoryAtURL:macOS withIntermediateDirectories:YES attributes:nil error:nil]);
        assert([files createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil]);
        NSURL *binary = [macOS URLByAppendingPathComponent:@"scrcpy"];
        assert([files copyItemAtURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]]
                             toURL:binary error:nil]);
        NSDictionary *info = @{@"CFBundleExecutable":@"scrcpy", @"CFBundlePackageType":@"APPL",
            @"CFBundleIdentifier":@"org.scrcpy.mirror.testhost", @"CFBundleName":@"Host"};
        assert([info writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);
        NSData *original = [NSData dataWithContentsOfURL:binary];
        NSError *error = nil;
        SCMirrorLaunch *launch = [SCMirrorLaunch prepareWithName:@"Google Pixel 7"
            serial:@"adb-28151FDH200EZG-test._adb-tls-connect._tcp"
            hostBundle:[NSBundle bundleWithURL:hostURL] error:&error];
        assert(launch && !error);
        NSBundle *mirror = [NSBundle bundleWithURL:launch.bundleURL];
        assert([launch.bundleURL.lastPathComponent isEqualToString:@"Google Pixel 7.app"]);
        assert([[mirror objectForInfoDictionaryKey:@"CFBundleDisplayName"] isEqualToString:@"Google Pixel 7"]);
        assert([[mirror objectForInfoDictionaryKey:@"ScrcpyXDeviceSerial"]
            isEqualToString:@"adb-28151FDH200EZG-test._adb-tls-connect._tcp"]);
        assert([[mirror objectForInfoDictionaryKey:@"ScrcpyXHostBundleIdentifier"] isEqualToString:info[@"CFBundleIdentifier"]]);
        assert(![mirror.bundleIdentifier isEqualToString:info[@"CFBundleIdentifier"]]);
        assert([original isEqualToData:[NSData dataWithContentsOfURL:binary]]);
        NSString *expectedADB = NSProcessInfo.processInfo.environment[@"ADB"] ?: [macOS URLByAppendingPathComponent:@"adb"].path;
        assert([launch.environment[@"ADB"] isEqualToString:expectedADB]);
        NSTask *verify = [[NSTask alloc] init];
        verify.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
        verify.arguments = @[@"--verify", @"--strict", launch.bundleURL.path];
        assert([verify launchAndReturnError:nil]); [verify waitUntilExit];
        assert(!verify.terminationStatus);
        // Resolve the icon host from inside a real new launcher process, not
        // only by inspecting its plist from the parent's bundle context.
        NSTask *child = [[NSTask alloc] init];
        child.executableURL = launch.executableURL;
        child.arguments = @[@"--check-host-bundle", hostURL.path];
        assert([child launchAndReturnError:nil]); [child waitUntilExit];
        assert(!child.terminationStatus);
        NSURL *sessionRoot = launch.bundleURL.URLByDeletingLastPathComponent;
        [launch cleanup];
        assert(![files fileExistsAtPath:sessionRoot.path]);
        __block BOOL completed = NO;
        [SCMirrorLaunch prepareWithName:@"Async device" serial:@"test-serial"
            hostBundle:[NSBundle bundleWithURL:hostURL] completion:^(SCMirrorLaunch *prepared, NSError *failure) {
            assert(NSThread.isMainThread && prepared && !failure);
            [prepared cleanup];
            completed = YES;
        }];
        waitFor(^BOOL { return completed; });
        completed = NO;
        preparedSignal = dispatch_semaphore_create(0);
        SCMirrorPreparation *request = [SCCancelledMirrorLaunch prepareWithName:@"Cancelled device"
            serial:@"cancelled" hostBundle:[NSBundle bundleWithURL:hostURL]
            completion:^(SCMirrorLaunch *prepared, NSError *failure) {
            assert(NSThread.isMainThread && !prepared && failure.code == NSUserCancelledError);
            completed = YES;
        }];
        // Cancel after the copy is actually signed, before main publishes it.
        // Waiting here keeps its completion queued until cancellation is set.
        assert(!dispatch_semaphore_wait(preparedSignal, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)));
        [request cancel];
        waitFor(^BOOL { return completed; });
        assert(cancelledRoot && ![files fileExistsAtPath:cancelledRoot.path]);
        assert([original isEqualToData:[NSData dataWithContentsOfURL:binary]]);
        [files removeItemAtURL:root error:nil];
        puts("Mirror session tests passed.");
    }
    return 0;
}
