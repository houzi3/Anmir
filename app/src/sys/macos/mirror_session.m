#import "mirror_session.h"
#import <AppKit/AppKit.h>
#include <signal.h>
#include <stdlib.h>

static NSString *const SCHostPath = @"AnmirHostBundlePath";
static NSString *const SCHostIdentifier = @"AnmirHostBundleIdentifier";
static NSString *const SCMirrorRoot = @"AnmirMirrorRoot";
static NSString *const SCMirrorSerial = @"AnmirDeviceSerial";

NSBundle *SCMirrorHostBundle(void) {
    NSString *path = [NSBundle.mainBundle objectForInfoDictionaryKey:SCHostPath];
    return path.length ? ([NSBundle bundleWithPath:path] ?: NSBundle.mainBundle) : NSBundle.mainBundle;
}

NSString *SCMirrorHostBundleIdentifier(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:SCHostIdentifier]
        ?: NSBundle.mainBundle.bundleIdentifier ?: @"io.github.laobie.anmir";
}

NSArray<NSString *> *
SCMirrorArguments(NSArray<NSString *> *original, NSString *serial) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObjects:
        @"--serial", serial, nil];
    for (NSUInteger i = 1; i < original.count; ++i) {
        NSString *argument = original[i];
        // The menu may be opened from an explicitly selected mirror. Replace
        // its selector instead of letting a later -s override the new device.
        if ([argument isEqualToString:@"--serial"] ||
                [argument isEqualToString:@"-s"]) {
            ++i;
            continue;
        }
        if ([argument hasPrefix:@"--serial="] ||
                ([argument hasPrefix:@"-s"] && ![argument hasPrefix:@"--"]) ||
                [argument isEqualToString:@"-d"] ||
                [argument isEqualToString:@"-e"] ||
                [argument isEqualToString:@"--select-usb"] ||
                [argument isEqualToString:@"--select-tcpip"] ||
                [argument hasPrefix:@"--tcpip="]) {
            continue;
        }
        [arguments addObject:argument];
    }
    return arguments;
}

static NSURL *ownedRoot;
static void SCMirrorCleanupAtExit(void) {
    @autoreleasepool {
        if (ownedRoot) { [NSFileManager.defaultManager removeItemAtURL:ownedRoot error:nil]; }
    }
}

void SCMirrorInstallCleanup(void) {
    NSString *root = [NSBundle.mainBundle objectForInfoDictionaryKey:SCMirrorRoot];
    NSString *parent = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"AnmirMirrors"] stringByResolvingSymlinksInPath];
    NSString *canonicalRoot = root.stringByResolvingSymlinksInPath;
    NSString *bundleParent = NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.path.stringByResolvingSymlinksInPath;
    if (root.length && [canonicalRoot.stringByDeletingLastPathComponent isEqualToString:parent]
            && [bundleParent isEqualToString:canonicalRoot]) {
        ownedRoot = [NSURL fileURLWithPath:root isDirectory:YES];
        atexit(SCMirrorCleanupAtExit);
    }
}

void SCMirrorMarkReady(void) {
    if (ownedRoot) {
        [@(NSProcessInfo.processInfo.processIdentifier).stringValue
            writeToURL:[ownedRoot URLByAppendingPathComponent:@"ready"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

@interface SCMirrorSession ()
@property(nonatomic, copy, readwrite) NSString *serial;
@property(nonatomic, strong, readwrite) NSRunningApplication *application;
@property(nonatomic, readwrite) BOOL ready;
@end
@implementation SCMirrorSession
@end

@interface SCMirrorPreparation ()
@property(atomic) BOOL cancelled;
@end
@implementation SCMirrorPreparation
- (void)cancel { self.cancelled = YES; }
@end

NSArray<SCMirrorSession *> *SCMirrorRunningSessions(void) {
    NSMutableArray *sessions = [NSMutableArray array];
    NSString *host = SCMirrorHostBundleIdentifier();
    NSString *prefix = [host stringByAppendingString:@".mirror."];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        if (app.terminated || ![app.bundleIdentifier hasPrefix:prefix]) { continue; }
        NSBundle *bundle = [NSBundle bundleWithURL:app.bundleURL];
        NSString *serial = [bundle objectForInfoDictionaryKey:SCMirrorSerial];
        if (!serial.length || ![[bundle objectForInfoDictionaryKey:SCHostIdentifier] isEqualToString:host]) { continue; }
        SCMirrorSession *session = [[SCMirrorSession alloc] init];
        session.serial = serial;
        session.application = app;
        NSString *root = [bundle objectForInfoDictionaryKey:SCMirrorRoot];
        NSString *pid = root.length ? [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"ready"]
            encoding:NSUTF8StringEncoding error:nil] : nil;
        session.ready = pid.intValue == app.processIdentifier;
        [sessions addObject:session];
    }
    return sessions;
}

@interface SCMirrorLaunch ()
@property(nonatomic, strong) NSURL *root;
@property(nonatomic, strong, readwrite) NSURL *bundleURL;
@property(nonatomic, strong, readwrite) NSURL *executableURL;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *environment;
@end

@implementation SCMirrorLaunch
+ (SCMirrorPreparation *)prepareWithName:(NSString *)name serial:(NSString *)serial
    hostBundle:(NSBundle *)host completion:(void (^)(SCMirrorLaunch *, NSError *))completion {
    SCMirrorPreparation *request = [[SCMirrorPreparation alloc] init];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            SCMirrorLaunch *launch = request.cancelled ? nil
                : [self prepareWithName:name serial:serial hostBundle:host error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (request.cancelled) {
                    [launch cleanup];
                    completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain
                        code:NSUserCancelledError userInfo:nil]);
                } else {
                    completion(launch, error);
                }
            });
        }
    });
    return request;
}
+ (instancetype)prepareWithName:(NSString *)name serial:(NSString *)serial hostBundle:(NSBundle *)host error:(NSError **)error {
    if (!host.executableURL || !host.resourceURL || !host.bundleIdentifier.length) {
        if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSExecutableNotLoadableError userInfo:nil]; }
        return nil;
    }
    SCMirrorLaunch *launch = [[self alloc] init];
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *token = NSUUID.UUID.UUIDString;
    launch.root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"AnmirMirrors" stringByAppendingPathComponent:token] isDirectory:YES];
    NSString *displayName = name.length ? name : @"Android device";
    NSString *filename = [[displayName componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"/:\n\r"]] componentsJoinedByString:@" "];
    launch.bundleURL = [launch.root URLByAppendingPathComponent:[filename stringByAppendingPathExtension:@"app"] isDirectory:YES];
    NSURL *contents = [launch.bundleURL URLByAppendingPathComponent:@"Contents" isDirectory:YES];
    NSURL *macOS = [contents URLByAppendingPathComponent:@"MacOS" isDirectory:YES];
    launch.executableURL = [macOS URLByAppendingPathComponent:@"anmir"];
    if (![files createDirectoryAtURL:macOS withIntermediateDirectories:YES attributes:nil error:error]
            || ![files copyItemAtURL:host.executableURL toURL:launch.executableURL error:error]
            || ![files copyItemAtURL:host.resourceURL toURL:[contents URLByAppendingPathComponent:@"Resources"] error:error]) {
        [launch cleanup]; return nil;
    }
    NSMutableDictionary *info = [host.infoDictionary mutableCopy];
    info[@"CFBundleName"] = displayName;
    info[@"CFBundleDisplayName"] = displayName;
    info[@"CFBundleExecutable"] = @"anmir";
    info[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"%@.mirror.%@", host.bundleIdentifier, token];
    info[SCHostPath] = host.bundlePath;
    info[SCHostIdentifier] = host.bundleIdentifier;
    info[SCMirrorRoot] = launch.root.path;
    info[SCMirrorSerial] = serial;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!plist || ![plist writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] options:NSDataWritingAtomic error:error]) {
        [launch cleanup]; return nil;
    }
    // A copied executable is signed for its own Info.plist. Never hard-link or
    // re-sign the installed host binary when assigning a device display name.
    NSTask *sign = [[NSTask alloc] init];
    sign.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
    sign.arguments = @[@"--force", @"--sign", @"-", @"--timestamp=none", launch.bundleURL.path];
    sign.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    sign.standardError = NSFileHandle.fileHandleWithNullDevice;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    sign.terminationHandler = ^(NSTask *task) { (void)task; dispatch_semaphore_signal(done); };
    if (![sign launchAndReturnError:error]) { [launch cleanup]; return nil; }
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
        if (sign.running) { kill(sign.processIdentifier, SIGKILL); }
        [sign waitUntilExit];
    }
    if (sign.terminationStatus) {
        if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSExecutableNotLoadableError userInfo:@{NSLocalizedDescriptionKey:@"Could not prepare the device window."}]; }
        [launch cleanup]; return nil;
    }
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    if (![environment[@"ADB"] length]) { environment[@"ADB"] = [host.executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"adb"].path; }
    if (![environment[@"SCRCPY_SERVER_PATH"] length]) { environment[@"SCRCPY_SERVER_PATH"] = [host.resourceURL URLByAppendingPathComponent:@"scrcpy-server"].path; }
    launch.environment = environment;
    return launch;
}
- (void)cleanup { [NSFileManager.defaultManager removeItemAtURL:self.root error:nil]; }
@end
