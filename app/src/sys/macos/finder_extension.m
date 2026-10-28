#import <AppKit/AppKit.h>
#import <FinderSync/FinderSync.h>
#import <os/log.h>
#include <pwd.h>
#include <string.h>
#include <unistd.h>
#import "finder_device_menu.h"

static NSString *SCFinderLocalized(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:nil];
}

static NSPasteboardName const SCAPKInstallPasteboardName =
    @"io.github.laobie.anmir.install-request";
static NSPasteboardType const SCAPKInstallPasteboardType =
    @"io.github.laobie.anmir.install-request";

static BOOL SCFinderUsesDarkAppearance(void) {
    // Finder Sync may keep its extension process alive across automatic
    // light/dark transitions. NSApp.effectiveAppearance can consequently
    // describe the old host appearance, so refresh and read the global
    // preference each time Finder asks us to build the contextual menu.
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef value = CFPreferencesCopyValue(
        CFSTR("AppleInterfaceStyle"), kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *style = CFBridgingRelease(value);
    return [style isKindOfClass:NSString.class] &&
        [style caseInsensitiveCompare:@"Dark"] == NSOrderedSame;
}

static NSImage *SCFinderMenuSymbol(NSString *name) {
    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:15
            weight:NSFontWeightRegular];
    NSImage *source = [[NSImage imageWithSystemSymbolName:name
        accessibilityDescription:nil]
        imageWithSymbolConfiguration:configuration];
    NSSize size = NSMakeSize(16, 16);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [source drawInRect:NSMakeRect(0, 0, size.width, size.height)
        fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
        fraction:1 respectFlipped:NO hints:nil];
    [[NSColor colorWithWhite:SCFinderUsesDarkAppearance() ? 0.90 : 0.15
        alpha:1.0] setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height),
        NSCompositingOperationSourceAtop);
    [image unlockFocus];
    // Finder Sync serializes menu images into the Finder process and drops
    // template rendering metadata. Send an already tinted bitmap instead.
    image.template = NO;
    return image;
}

static NSURL *SCFinderUserHomeURL(void) {
    // NSHomeDirectory() resolves to the extension's sandbox container. Finder
    // needs the login user's actual home directory so that contextual menus
    // are requested for files in Desktop, Downloads, and other home folders.
    struct passwd *user = getpwuid(getuid());
    if (user && user->pw_dir && user->pw_dir[0]) {
        NSString *path = [NSFileManager.defaultManager
            stringWithFileSystemRepresentation:user->pw_dir
                                         length:strlen(user->pw_dir)];
        if (path.length) {
            return [NSURL fileURLWithPath:path isDirectory:YES];
        }
    }
    return [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
}

@interface AnmirFinderSync : FIFinderSync
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *devices;
@property(nonatomic, copy) NSDictionary<NSNumber *, NSString *> *serialsByMenuTag;
@property(nonatomic) BOOL deviceRefreshRunning;
@end

@implementation AnmirFinderSync

- (instancetype)init {
    self = [super init];
    if (self) {
        _devices = @[];
        NSMutableSet<NSURL *> *directories = [NSMutableSet setWithObject:
            SCFinderUserHomeURL()];
        NSURL *volumes = [NSURL fileURLWithPath:@"/Volumes" isDirectory:YES];
        if ([NSFileManager.defaultManager fileExistsAtPath:volumes.path]) {
            [directories addObject:volumes];
        }
        FIFinderSyncController.defaultController.directoryURLs = directories;
        os_log(OS_LOG_DEFAULT, "Anmir Finder monitoring: %{public}@", directories);
        [self refreshDevices];
    }
    return self;
}

- (void)refreshDevices {
    @synchronized (self) {
        if (self.deviceRefreshRunning) {
            return;
        }
        self.deviceRefreshRunning = YES;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSDictionary<NSString *, NSString *> *> *devices =
            SCFinderParseADBDevices([self runADBDevices]);
        self.devices = devices;
        @synchronized (self) {
            self.deviceRefreshRunning = NO;
        }
        os_log(OS_LOG_DEFAULT, "Anmir Finder cached %lu device(s)",
            (unsigned long)devices.count);
    });
}

- (NSURL *)containingApplicationURL {
    NSURL *url = NSBundle.mainBundle.bundleURL;
    for (NSUInteger i = 0; i < 3; ++i) {
        url = url.URLByDeletingLastPathComponent;
    }
    return url;
}

- (NSString *)adbExecutable {
    return [[self containingApplicationURL].path
        stringByAppendingPathComponent:@"Contents/MacOS/adb"];
}

- (NSString *)runADBDevices {
    NSString *adb = self.adbExecutable;
    if (![NSFileManager.defaultManager isExecutableFileAtPath:adb]) {
        return @"";
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:adb];
    task.arguments = @[@"devices", @"-l"];
    NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"anmir-adb-%@.txt", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createFileAtPath:outputPath contents:nil attributes:nil];
    NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:outputPath];
    task.standardOutput = output;
    task.standardError = output;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [output closeFile];
        [NSFileManager.defaultManager removeItemAtPath:outputPath error:nil];
        os_log_error(OS_LOG_DEFAULT, "Anmir Finder extension could not start ADB: %{public}@",
            error.localizedDescription);
        return @"";
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (task.running && deadline.timeIntervalSinceNow > 0) {
        usleep(10000);
    }
    if (task.running) {
        [task terminate];
        [output closeFile];
        [NSFileManager.defaultManager removeItemAtPath:outputPath error:nil];
        return @"";
    }
    [output closeFile];
    NSData *data = [NSData dataWithContentsOfFile:outputPath];
    [NSFileManager.defaultManager removeItemAtPath:outputPath error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSString *)localizedTransport:(NSString *)transport {
    if ([transport isEqualToString:@"Wi-Fi"]) {
        return @"Wi-Fi";
    }
    return SCFinderLocalized(transport);
}

- (NSMenu *)menuForMenuKind:(FIMenuKind)kind {
    os_log(OS_LOG_DEFAULT, "Anmir Finder menu request: kind=%ld selection=%{public}@",
        (long)kind, FIFinderSyncController.defaultController.selectedItemURLs);
    if (kind != FIMenuKindContextualMenuForItems) {
        return nil;
    }
    NSArray<NSURL *> *rawSelection =
        FIFinderSyncController.defaultController.selectedItemURLs;
    NSMutableArray<NSURL *> *selection = [NSMutableArray array];
    for (NSURL *url in rawSelection ?: @[]) {
        // Recent Finder versions may return a stable file-reference URL such
        // as file:///.file/id=…; normalize it before checking the extension
        // or passing its path to the host application.
        [selection addObject:url.filePathURL ?: url];
    }
    os_log(OS_LOG_DEFAULT, "Anmir Finder normalized selection: %{public}@", selection);
    if (!SCFinderSelectionIsSingleAPK(selection ?: @[])) {
        os_log(OS_LOG_DEFAULT, "Anmir Finder ignored non-APK selection");
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *install = [[NSMenuItem alloc]
        initWithTitle:SCFinderLocalized(@"Install on phone") action:nil keyEquivalent:@""];
    install.image = SCFinderMenuSymbol(@"iphone.and.arrow.forward");
    NSMenu *devicesMenu = [[NSMenu alloc] initWithTitle:install.title];
    NSArray *devices = self.devices ?: @[];
    os_log(OS_LOG_DEFAULT, "Anmir Finder menu uses %lu cached device(s)",
        (unsigned long)devices.count);
    [self refreshDevices];
    if (!devices.count) {
        NSMenuItem *empty = [[NSMenuItem alloc]
            initWithTitle:SCFinderLocalized(@"No available devices") action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [devicesMenu addItem:empty];
    } else {
        NSMutableDictionary<NSNumber *, NSString *> *serialsByMenuTag =
            [NSMutableDictionary dictionary];
        NSInteger menuTag = 1;
        for (NSDictionary<NSString *, NSString *> *device in devices) {
            NSString *title = [NSString stringWithFormat:@"%@ · %@",
                device[SCFinderDeviceModelKey],
                [self localizedTransport:device[SCFinderDeviceTransportKey]]];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                action:@selector(installAPK:) keyEquivalent:@""];
            // Finder Sync dispatches actions to the extension's principal
            // object. Keep the target nil so Finder can route the selector
            // after copying the menu across its extension boundary.
            item.tag = menuTag;
            serialsByMenuTag[@(menuTag)] = device[SCFinderDeviceSerialKey];
            menuTag++;
            [devicesMenu addItem:item];
        }
        self.serialsByMenuTag = serialsByMenuTag;
    }
    NSMenuItem *open = [[NSMenuItem alloc]
        initWithTitle:SCFinderLocalized(@"Open Anmir…") action:@selector(openAnmir:) keyEquivalent:@""];
    [devicesMenu addItem:open];
    install.submenu = devicesMenu;
    [menu addItem:install];
    return menu;
}

- (void)installAPK:(NSMenuItem *)sender {
    os_log(OS_LOG_DEFAULT,
        "Anmir Finder install action received: tag=%ld title=%{public}@",
        (long)sender.tag, sender.title);
    NSArray<NSURL *> *rawSelection =
        FIFinderSyncController.defaultController.selectedItemURLs;
    NSURL *apk = rawSelection.firstObject.filePathURL ?: rawSelection.firstObject;
    NSString *serial = self.serialsByMenuTag[@(sender.tag)];
    NSString *deviceName = sender.title;
    if (!apk.fileURL || !serial.length) {
        os_log_error(OS_LOG_DEFAULT,
            "Anmir Finder install action missing APK or device: selection=%{public}@ tag=%ld",
            rawSelection, (long)sender.tag);
        return;
    }
    os_log(OS_LOG_DEFAULT,
        "Anmir Finder requested installation of %{public}@ on %{public}@",
        apk.lastPathComponent, serial);
    NSPasteboard *handoff = [NSPasteboard pasteboardWithName:SCAPKInstallPasteboardName];
    [handoff clearContents];
    BOOL wroteRequest = [handoff setPropertyList:@{
        @"apk": apk.path,
        @"serial": serial,
        @"deviceName": deviceName.length ? deviceName : serial,
        @"created": @([NSDate date].timeIntervalSince1970),
    } forType:SCAPKInstallPasteboardType];
    if (!wroteRequest) {
        os_log_error(OS_LOG_DEFAULT,
            "Anmir Finder could not prepare the APK installation request");
        return;
    }
    NSWorkspaceOpenConfiguration *configuration =
        [NSWorkspaceOpenConfiguration configuration];
    configuration.createsNewApplicationInstance = YES;
    configuration.activates = YES;
    configuration.addsToRecentItems = NO;
    configuration.arguments = @[@"--anmir-install-apk", apk.path,
                                @"--serial", serial,
                                @"--device-name", deviceName.length ? deviceName : serial];
    // NSWorkspace explicitly ignores `arguments` when the caller is
    // sandboxed (Finder Sync extensions always are). Keep both arguments and
    // environment as convenient fallbacks; the reliable sandbox handoff is
    // the short-lived, app-specific named pasteboard request above.
    configuration.environment = @{
        @"ANMIR_INSTALL_APK": apk.path,
        @"ANMIR_INSTALL_SERIAL": serial,
        @"ANMIR_INSTALL_DEVICE": deviceName.length ? deviceName : serial,
    };
    [NSWorkspace.sharedWorkspace openApplicationAtURL:self.containingApplicationURL
        configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
            (void)app;
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "Anmir could not start APK installation: %{public}@",
                    error.localizedDescription);
            }
        }];
}

- (void)openAnmir:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:self.containingApplicationURL
        configuration:NSWorkspaceOpenConfiguration.configuration
        completionHandler:^(NSRunningApplication *app, NSError *error) {
            (void)app;
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "Anmir could not open: %{public}@",
                    error.localizedDescription);
            }
        }];
}

@end
