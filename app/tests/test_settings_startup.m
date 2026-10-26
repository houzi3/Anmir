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
#import "sys/macos/device_relay.h"
#import "sys/macos/device_reconnect.h"
#import "sys/macos/application_lifecycle.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

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
    setenv("ANMIR_SHOW_SETTINGS", "1", 1); setenv("ANMIR_SHOW_DEVICES", "1", 1);
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
            assert(!windowNamed(@"Anmir")); // No manager even constructed.
            assert(adbStarts == 0); // Settings alone does not scan devices.
            settings = windowNamed(@"Anmir Settings"); assert(settings);
            NSMenuItem *devices = [[NSApp.mainMenu itemAtIndex:0].submenu itemWithTag:0x53434456]; assert(devices);
            assert([NSApp sendAction:devices.action to:devices.target from:devices]);
            manager = windowNamed(@"Anmir"); assert(manager.visible);
            [settings close];
        } else if (phase == 1) {
            // Closing Settings must not end a subsequently opened device list.
            assert(manager.visible && !SCSettingsWindowVisible());
            [manager orderOut:nil]; SCSettingsShow();
        } else if (phase == 2) {
            assert(SCSettingsWindowVisible() && !manager.visible);
            assert(windowNamed(@"Anmir Settings") == settings); // Reuse Settings.
            SCSettingsShow();
            assert(!manager.visible); // Repeated open cannot reveal the list.
            request = [[NSTask alloc] init];
            request.executableURL = [NSURL fileURLWithPath:requestBinary]; request.arguments = @[@"request"];
            assert([request launchAndReturnError:nil]);
        } else if (phase == 3) {
            if (request.running || !requests) { return; }
            assert(request.terminationStatus == 0 && requests == 1);
            assert(SCSettingsWindowVisible() && !manager.visible);
            assert(windowNamed(@"Anmir Settings") == settings);
            NSMenuItem *devices = [[NSApp.mainMenu itemAtIndex:0].submenu itemWithTag:0x53434456];
            assert([NSApp sendAction:devices.action to:devices.target from:devices]);
            assert(windowNamed(@"Anmir") == manager && manager.visible);
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

static BOOL relayListening(NSDictionary *registration) {
    int fd = socket(AF_INET, SOCK_STREAM, 0); assert(fd >= 0);
    struct sockaddr_in address = {.sin_len=sizeof(address), .sin_family=AF_INET,
        .sin_addr.s_addr=htonl(INADDR_LOOPBACK), .sin_port=htons([registration[@"port"] intValue])};
    BOOL listening = !connect(fd, (struct sockaddr *)&address, sizeof(address));
    close(fd); return listening;
}

static int lifecycleMirrorFixture(void) {
    assert(SDL_Init(SDL_INIT_VIDEO));
    sc_device_picker_install_menu(NULL);
    SDL_Window *mirror = SDL_CreateWindow("Independent lifecycle mirror", 320, 240, 0); assert(mirror);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    SDL_Event event;
    while (deadline.timeIntervalSinceNow > 0) {
        if (SDL_WaitEventTimeout(&event, 100) && event.type == SDL_EVENT_QUIT) {
            SDL_DestroyWindow(mirror); SDL_Quit();
            puts("Independent mirror received application Quit through its SDL loop.");
            return 0;
        }
    }
    assert(false); return 1;
}

static int lifecycleFixture(NSString *mirrorBinary) {
    unsetenv("ANMIR_SHOW_SETTINGS"); unsetenv("ANMIR_CHECK_UPDATES"); unsetenv("ANDROID_SERIAL");
    setenv("ANMIR_SHOW_DEVICES", "1", 1);
    assert(SDL_Init(SDL_INIT_VIDEO));
    SCSettingsInitialize();
    // Real persisted routes in a disposable app domain, never the user's phones.
    SCDeviceReconnect *seed = [[SCDeviceReconnect alloc] initWithExecutable:@"/usr/bin/false"
        defaults:NSUserDefaults.standardUserDefaults];
    for (NSUInteger i = 0; i < 2; ++i) {
        SCDeviceRelay *relay = [SCDeviceRelay listenOnHost:@"127.0.0.1" error:nil]; assert(relay);
        NSString *identity = [NSString stringWithFormat:@"fixture-phone-%lu", (unsigned long)i];
        assert([seed rememberRelay:relay guid:identity serial:@"127.0.0.1:37123"
            properties:@{@"ro.serialno":identity}]);
    }
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:@"CompanyNetworkPhones.v1"];
    assert(saved.count == 2); [seed stop];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    __block NSUInteger phase = 0;
    __block NSWindow *manager, *settings;
    __block NSTask *opener;
    __block NSTask *mirrorProcess;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    NSTimer *timer = [NSTimer timerWithTimeInterval:.15 repeats:YES block:^(NSTimer *tick) {
        if (deadline.timeIntervalSinceNow <= 0) {
            fprintf(stderr, "Dock lifecycle timed out in phase %lu (activation policy %ld)\n",
                (unsigned long)phase, (long)NSApp.activationPolicy);
            for (NSWindow *window in NSApp.windows) {
                fprintf(stderr, "Window %s: visible=%d minimized=%d\n", window.title.UTF8String,
                    window.visible, window.miniaturized);
            }
            abort();
        }
        if (phase == 0) {
            manager = windowNamed(@"Anmir");
            if (!manager.visible || NSApp.activationPolicy != NSApplicationActivationPolicyRegular) { return; }
            assert(NSApp.activationPolicy == NSApplicationActivationPolicyRegular);
            [manager miniaturize:nil];
        } else if (phase == 1) {
            // Miniaturization completes asynchronously; its animation is slower
            // than one polling interval on some Intel runners.
            if (!manager.miniaturized) { return; }
            assert(manager.miniaturized && SCApplicationHasWindows());
            assert(NSApp.activationPolicy == NSApplicationActivationPolicyRegular);
            // A real LaunchServices reopen, shared by Finder and Spotlight.
            opener = [[NSTask alloc] init]; opener.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
            opener.arguments = @[@"-a", NSBundle.mainBundle.bundlePath]; assert([opener launchAndReturnError:nil]);
        } else if (phase == 2) {
            if (opener.running || manager.miniaturized || !manager.visible) { return; }
            assert(opener.terminationStatus == 0 && windowNamed(@"Anmir") == manager && manager.visible);
            SCSettingsShow(); settings = windowNamed(@"Anmir Settings"); assert(settings.visible);
            [manager close];
        } else if (phase == 3) {
            assert(settings.visible && NSApp.activationPolicy == NSApplicationActivationPolicyRegular);
            [settings close];
        } else if (phase == 4) {
            if (SCApplicationHasWindows() || NSApp.activationPolicy != NSApplicationActivationPolicyAccessory) { return; }
            assert(!SCApplicationHasWindows());
            assert(NSApp.activationPolicy == NSApplicationActivationPolicyAccessory);
            for (NSDictionary *route in saved) { assert(relayListening(route)); }
            opener = [[NSTask alloc] init]; opener.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
            opener.arguments = @[@"-a", NSBundle.mainBundle.bundlePath]; assert([opener launchAndReturnError:nil]);
        } else if (phase == 5) {
            if (opener.running || !manager.visible || NSApp.activationPolicy != NSApplicationActivationPolicyRegular) { return; }
            assert(opener.terminationStatus == 0 && windowNamed(@"Anmir") == manager);
            assert(NSApp.activationPolicy == NSApplicationActivationPolicyRegular);
            NSUInteger count = NSApp.windows.count;
            [NSApp.delegate applicationShouldHandleReopen:NSApp hasVisibleWindows:YES];
            assert(NSApp.windows.count == count && windowNamed(@"Anmir") == manager);
            // Exercise SDL's real mirror NSWindow without involving an Android phone.
            [manager close];
            SDL_Window *mirror = SDL_CreateWindow("Lifecycle mirror", 320, 240, SDL_WINDOW_HIDDEN);
            assert(mirror); SDL_ShowWindow(mirror);
            SDL_SetPointerProperty(SDL_GetGlobalProperties(), "anmir.test.mirror", mirror);
        } else if (phase == 6) {
            if (NSApp.activationPolicy != NSApplicationActivationPolicyRegular) { return; }
            assert(NSApp.activationPolicy == NSApplicationActivationPolicyRegular);
            SDL_Window *mirror = SDL_GetPointerProperty(SDL_GetGlobalProperties(), "anmir.test.mirror", NULL);
            SDL_DestroyWindow(mirror);
        } else if (phase == 7) {
            // SDL teardown and the queued activation-policy update can span
            // multiple AppKit event-loop iterations as well.
            if (SCApplicationHasWindows() || NSApp.activationPolicy != NSApplicationActivationPolicyAccessory) { return; }
            assert(NSApp.activationPolicy == NSApplicationActivationPolicyAccessory);
            mirrorProcess = [[NSTask alloc] init];
            mirrorProcess.executableURL = [NSURL fileURLWithPath:mirrorBinary];
            mirrorProcess.arguments = @[@"lifecycle-mirror"];
            assert([mirrorProcess launchAndReturnError:nil]);
        } else if (phase == 8) {
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:mirrorProcess.processIdentifier];
            if (!app || app.activationPolicy != NSApplicationActivationPolicyRegular) { return; }
            assert(mirrorProcess.running && NSApp.activationPolicy == NSApplicationActivationPolicyAccessory);
            [NSApp.delegate applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
        } else {
            assert(manager.visible);
            // Cmd-Q uses this menu action and must unwind the background loop.
            NSMenu *menu = [NSApp.mainMenu itemAtIndex:0].submenu;
            NSMenuItem *quit = nil;
            for (NSMenuItem *item in menu.itemArray) { if (item.action == @selector(terminate:)) { quit = item; } }
            assert(quit && [NSApp sendAction:quit.action to:quit.target from:quit]);
            [tick invalidate];
        }
        ++phase;
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    struct scrcpy_options options = {.window = true};
    assert(sc_device_picker_run(&options, NULL) == SC_DEVICE_PICKER_FINISHED);
    [timer invalidate]; assert(phase == 10);
    while (mirrorProcess.running && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
    assert(!mirrorProcess.running && mirrorProcess.terminationStatus == 0);
    for (NSDictionary *route in saved) { assert(!relayListening(route)); }
    SDL_Quit();
    puts("Dock lifecycle: two remembered routes, last-window close, minimized reopen, LaunchServices reopen, window reuse, Settings, SDL mirror and Quit passed.");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "request")) { return requestSettings(); }
        if (argc > 1 && !strcmp(argv[1], "lifecycle-mirror")) { return lifecycleMirrorFixture(); }
        if (argc > 2 && !strcmp(argv[1], "lifecycle")) { return lifecycleFixture([NSString stringWithUTF8String:argv[2]]); }
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
        NSString *domain = [@"com.anmir.test.routing." stringByAppendingString:NSUUID.UUID.UUIDString];
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
        mirrorInfo[@"AnmirHostBundlePath"] = bundle;
        mirrorInfo[@"AnmirHostBundleIdentifier"] = domain;
        assert([mirrorInfo writeToFile:[mirrorContents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);
        NSTask *child = [[NSTask alloc] init]; child.executableURL = [NSURL fileURLWithPath:binary]; child.arguments = @[@"fixture", mirrorBinary];
        assert([child launchAndReturnError:nil]); [child waitUntilExit];
        int status = child.terminationStatus;
        if (!status) {
            NSMutableDictionary *lifecycleInfo = [info mutableCopy];
            [lifecycleInfo removeObjectForKey:@"LSUIElement"];
            assert([lifecycleInfo writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);
            child = [[NSTask alloc] init]; child.executableURL = [NSURL fileURLWithPath:binary];
            child.arguments = @[@"lifecycle", mirrorBinary];
            assert([child launchAndReturnError:nil]); [child waitUntilExit];
            status = child.terminationStatus;
        }
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
