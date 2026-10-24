#include "device_picker.h"
#include "options.h"
#include "device_info.h"
#include "adb/adb.h"
#include "adb/adb_parser.h"
#include "events.h"
#import <AppKit/AppKit.h>
#import "sys/macos/settings.h"
#import "sys/macos/settings_ui.h"
#import "sys/macos/mirror_session.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>

// Keep the production native window flow, with ADB disabled so this test
// cannot discover phones, start a server or affect an existing mirror.
static unsigned adbStarts;
const char *sc_adb_get_executable(void) { return "/usr/bin/false"; }
bool sc_adb_start_server(struct sc_intr *intr, unsigned flags) {
    (void)intr; (void)flags; ++adbStarts; return false;
}
bool sc_adb_list_devices(struct sc_intr *intr, unsigned flags, struct sc_vec_adb_devices *out) {
    (void)intr; (void)flags; (void)out; assert(false); return false;
}
bool sc_adb_parse_devices(char *text, struct sc_vec_adb_devices *out) { (void)text; (void)out; return false; }
void sc_adb_devices_destroy(struct sc_vec_adb_devices *devices) { assert(!devices->size); }
enum sc_adb_device_type sc_adb_device_get_type(const char *serial) { (void)serial; return SC_ADB_DEVICE_TYPE_USB; }
void sc_device_info_init(struct sc_device_info *info) { memset(info, 0, sizeof(*info)); }
void sc_device_info_destroy(struct sc_device_info *info) { (void)info; }
void sc_device_info_load(struct sc_device_info *info, struct sc_intr *intr, const char *serial) {
    (void)info; (void)intr; (void)serial; assert(false);
}
char *sc_device_info_build_name(const struct sc_device_info *info, const char *fallback) {
    (void)info; return strdup(fallback);
}
void sc_theme_install_menu(void) { SCSettingsInstallMenu(); }
bool sc_toolbar_preferences_load_saved_visible(bool *visible) { (void)visible; return false; }
bool sc_push_event_impl(uint32_t type, void *ptr, const char *name) {
    (void)name; SDL_Event event = {.type = type}; event.user.data1 = ptr; return SDL_PushEvent(&event);
}

static NSWindow *windowNamed(NSString *name) {
    for (NSWindow *window in NSApp.windows) { if ([window.title isEqualToString:name]) { return window; } }
    return nil;
}
static BOOL activateWithoutOtherWindows(id app, SEL selector, NSApplicationActivationOptions options) {
    (void)app; (void)selector;
    assert(!(options & NSApplicationActivateAllWindows));
    return YES;
}
static int requestSettings(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    assert(SDL_Init(SDL_INIT_VIDEO));
    assert([NSRunningApplication runningApplicationsWithBundleIdentifier:SCMirrorHostBundleIdentifier()].count == 1);
    // The real mirror route must never activate all host windows. Intercept
    // this API only in the disposable requesting process, avoiding focus changes.
    method_setImplementation(class_getInstanceMethod(NSRunningApplication.class, @selector(activateWithOptions:)),
        (IMP)activateWithoutOtherWindows);
    SCSettingsInitialize(); SCSettingsShow();
    assert(!SCSettingsWindowVisible()); // Settings belongs to the host.
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    SDL_Quit(); return 0;
}
static int fixture(NSString *requestBinary) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    assert(SDL_Init(SDL_INIT_VIDEO));
    // UI-element fixtures do not get SDL's regular-app menu automatically.
    NSMenu *bar = [[NSMenu alloc] init];
    NSMenuItem *app = [[NSMenuItem alloc] init]; app.submenu = [[NSMenu alloc] init];
    [bar addItem:app]; NSApp.mainMenu = bar;
    SCSettingsInitialize();
    // Settings takes precedence even if a parent exported Show Devices.
    setenv("SCRCPYX_SHOW_SETTINGS", "1", 1); setenv("SCRCPYX_SHOW_DEVICES", "1", 1);
    unsetenv("ANDROID_SERIAL");
    __block NSUInteger phase = 0;
    __block NSWindow *settings, *manager;
    __block NSTask *request;
    __block NSUInteger requests = 0;
    id observer = [NSDistributedNotificationCenter.defaultCenter addObserverForName:
        [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".ShowSettings"] object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; ++requests; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    NSTimer *timer = [NSTimer timerWithTimeInterval:.03 repeats:YES block:^(NSTimer *tick) {
        assert(deadline.timeIntervalSinceNow > 0);
        if (phase == 0) {
            assert(SCSettingsWindowVisible());
            assert(!windowNamed(@"ScrcpyX")); // No manager even constructed.
            assert(adbStarts == 0); // Settings alone does not scan devices.
            settings = windowNamed(@"ScrcpyX Settings"); assert(settings);
            NSMenuItem *devices = [[NSApp.mainMenu itemAtIndex:0].submenu itemWithTag:0x53434456]; assert(devices);
            assert([NSApp sendAction:devices.action to:devices.target from:devices]);
            manager = windowNamed(@"ScrcpyX"); assert(manager.visible);
            [settings close];
        } else if (phase == 1) {
            // Closing Settings must not end a subsequently opened device list.
            assert(manager.visible && !SCSettingsWindowVisible());
            [manager orderOut:nil]; SCSettingsShow();
        } else if (phase == 2) {
            assert(SCSettingsWindowVisible() && !manager.visible);
            assert(windowNamed(@"ScrcpyX Settings") == settings); // Reuse Settings.
            SCSettingsShow();
            assert(!manager.visible); // Repeated open cannot reveal the list.
            request = [[NSTask alloc] init];
            request.executableURL = [NSURL fileURLWithPath:requestBinary]; request.arguments = @[@"request"];
            assert([request launchAndReturnError:nil]);
        } else if (phase == 3) {
            if (request.running || !requests) { return; }
            assert(request.terminationStatus == 0 && requests == 1);
            assert(SCSettingsWindowVisible() && !manager.visible);
            assert(windowNamed(@"ScrcpyX Settings") == settings);
            NSMenuItem *devices = [[NSApp.mainMenu itemAtIndex:0].submenu itemWithTag:0x53434456];
            assert([NSApp sendAction:devices.action to:devices.target from:devices]);
            assert(windowNamed(@"ScrcpyX") == manager && manager.visible);
            [manager close];
        } else {
            assert(SCSettingsWindowVisible() && !manager.visible);
            [settings close]; [tick invalidate];
        }
        ++phase;
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    struct scrcpy_options options = {.window = true};
    enum sc_device_picker_result result = sc_device_picker_run(&options, NULL);
    [timer invalidate];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:observer];
    assert(result == SC_DEVICE_PICKER_FINISHED && phase == 5 && adbStarts == 0);
    SDL_Quit();
    puts("Settings-only startup, real cross-process Settings request, unchanged hidden manager, window reuse and device-list lifetime passed.");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "request")) { return requestSettings(); }
        if (argc > 2) { return fixture([NSString stringWithUTF8String:argv[2]]); }
        // Disposable UI-element bundles exercise real host and mirror identities.
        // Unregister and remove it on both success and failure.
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *bundle = [root stringByAppendingPathComponent:@"WindowRoutingTest.app"];
        NSString *contents = [bundle stringByAppendingPathComponent:@"Contents"];
        NSString *macOS = [contents stringByAppendingPathComponent:@"MacOS"];
        assert([files createDirectoryAtPath:macOS withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *binary = [macOS stringByAppendingPathComponent:@"test_settings_startup"];
        assert([files copyItemAtPath:[NSString stringWithUTF8String:argv[0]] toPath:binary error:nil]);
        NSString *domain = [@"com.scrcpyx.test.routing." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSDictionary *info = @{@"CFBundleIdentifier":domain, @"CFBundleExecutable":@"test_settings_startup",
            @"CFBundlePackageType":@"APPL", @"LSUIElement":@YES};
        assert([info writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);
        NSString *mirror = [root stringByAppendingPathComponent:@"WindowRequester.app"];
        NSString *mirrorContents = [mirror stringByAppendingPathComponent:@"Contents"];
        NSString *mirrorMacOS = [mirrorContents stringByAppendingPathComponent:@"MacOS"];
        assert([files createDirectoryAtPath:mirrorMacOS withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *mirrorBinary = [mirrorMacOS stringByAppendingPathComponent:@"test_settings_startup"];
        assert([files copyItemAtPath:binary toPath:mirrorBinary error:nil]);
        NSMutableDictionary *mirrorInfo = [info mutableCopy];
        mirrorInfo[@"CFBundleIdentifier"] = [domain stringByAppendingString:@".mirror"];
        mirrorInfo[@"ScrcpyXHostBundlePath"] = bundle;
        mirrorInfo[@"ScrcpyXHostBundleIdentifier"] = domain;
        assert([mirrorInfo writeToFile:[mirrorContents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);
        NSTask *child = [[NSTask alloc] init]; child.executableURL = [NSURL fileURLWithPath:binary]; child.arguments = @[@"fixture", mirrorBinary];
        assert([child launchAndReturnError:nil]); [child waitUntilExit];
        int status = child.terminationStatus;
        NSTask *unregister = [[NSTask alloc] init];
        unregister.executableURL = [NSURL fileURLWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"];
        unregister.arguments = @[@"-u", bundle, mirror];
        if ([unregister launchAndReturnError:nil]) { [unregister waitUntilExit]; }
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:domain];
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:[domain stringByAppendingString:@".mirror"]];
        [NSUserDefaults.standardUserDefaults synchronize];
        assert([files removeItemAtPath:root error:nil]);
        return status;
    }
}
