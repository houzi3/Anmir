#include "events.h"
#import <AppKit/AppKit.h>
#import "sys/macos/settings.h"
#import "sys/macos/localization.h"
#include <assert.h>

// Exercise the production settings store and notifications in two processes,
// using an isolated domain and resource bundle instead of the user's settings.
static NSString *domain;
static NSBundle *resources;
static BOOL legacyPresent, legacyVisible;
static NSUInteger events;
NSString *SCMirrorHostBundleIdentifier(void) { return domain; }
NSBundle *SCMirrorHostBundle(void) { return resources; }
bool sc_toolbar_preferences_load_saved_visible(bool *visible) {
    if (legacyPresent) { *visible = legacyVisible; }
    return legacyPresent;
}
bool sc_push_event_impl(uint32_t type, void *ptr, const char *name) {
    (void)ptr; (void)name;
    assert(type == SC_EVENT_SETTINGS_CHANGED); ++events; return true;
}

static BOOL updated(void) {
    return [SCSettingsLanguage() isEqualToString:@"zh-Hans"] &&
        [SCCurrentLanguage() isEqualToString:@"zh-Hans"] &&
        [SCSettingsTheme() isEqualToString:@"dark"] && sc_settings_toolbar_visible();
}
static BOOL spin(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    }
    return done();
}
static NSTask *child(NSString *executable, NSArray *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    NSError *error;
    assert([task launchAndReturnError:&error]);
    return task;
}
int main(int argc, const char *argv[]) {
    (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSArray *args = NSProcessInfo.processInfo.arguments;
        if (argc == 2) {
            // Use real bundle identities: the host uses standardUserDefaults,
            // while independent mirror apps must read the host's suite.
            NSString *testDomain = [@"com.anmir.test." stringByAppendingString:NSUUID.UUID.UUIDString];
            NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            NSMutableArray *executables = [NSMutableArray array];
            for (NSString *role in @[@"host", @"mirror"]) {
                NSString *contents = [[root stringByAppendingPathComponent:[role stringByAppendingString:@".app"]] stringByAppendingPathComponent:@"Contents"];
                NSString *macOS = [contents stringByAppendingPathComponent:@"MacOS"];
                assert([NSFileManager.defaultManager createDirectoryAtPath:macOS withIntermediateDirectories:YES attributes:nil error:nil]);
                NSString *executable = [macOS stringByAppendingPathComponent:@"test_settings_sync"];
                assert([NSFileManager.defaultManager copyItemAtPath:args[0] toPath:executable error:nil]);
                NSString *identifier = [role isEqualToString:@"host"] ? testDomain : [testDomain stringByAppendingString:@".mirror"];
                assert(([@{@"CFBundleIdentifier":identifier, @"CFBundleExecutable":@"test_settings_sync", @"CFBundlePackageType":@"APPL"}
                    writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]));
                [executables addObject:executable];
            }
            NSTask *writer = child(executables[0], @[@"writer", testDomain, args[1], executables[1]]);
            assert(spin(^BOOL { return !writer.running; }));
            assert(writer.terminationStatus == 0);
            assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
            return 0;
        }
        domain = args[2]; resources = [NSBundle bundleWithPath:args[3]];
        if (![args[1] isEqualToString:@"writer"]) {
            SCSettingsInitialize();
            if ([args[1] isEqualToString:@"verify"]) { assert(updated()); return 0; }
            assert(!sc_settings_toolbar_visible()); // Explicit OFF survives launch.
            NSUInteger initial = events;
            [@"ready" writeToFile:args[4] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            assert(spin(^BOOL { return updated() && events > initial; }));
            return 0;
        }
        NSUserDefaults *isolated = [[NSUserDefaults alloc] initWithSuiteName:domain];
        SCSettingsInitialize();
        assert(!SCSettingsHasTheme());
        assert([SCSettingsLanguage() isEqualToString:@"system"]);
        assert(sc_settings_toolbar_visible()); // Fresh installs default ON.
        legacyPresent = YES; legacyVisible = NO;
        assert(!sc_settings_toolbar_visible()); // Existing legacy OFF is honored.
        assert(sc_settings_set_toolbar_visible(true));
        assert(sc_settings_toolbar_visible()); // New settings take precedence.
        assert(sc_settings_set_toolbar_visible(false));
        SCSettingsPreviewLanguage(@"zh-Hant");
        [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidBecomeActiveNotification object:nil];
        assert([SCCurrentLanguage() isEqualToString:@"zh-Hant"]);
        assert([SCSettingsLanguage() isEqualToString:@"system"]); // Preview is not saved.
        SCSettingsEndLanguagePreview();
        assert([SCCurrentLanguage() isEqualToString:SCResolveLanguage(@"system", NSLocale.preferredLanguages)]);
        NSString *ready = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSTask *reader = child(args[4], @[@"reader", domain, args[3], ready]);
        assert(spin(^BOOL { return [NSFileManager.defaultManager fileExistsAtPath:ready]; }));
        SCSettingsAcceptOnboarding(@"dark", @"zh-Hans");
        assert(SCSettingsHasTheme());
        assert(sc_settings_set_toolbar_visible(true));
        assert(spin(^BOOL { return !reader.running; }));
        assert(reader.terminationStatus == 0);
        NSTask *reopened = child(args[4], @[@"verify", domain, args[3]]);
        assert(spin(^BOOL { return !reopened.running; }));
        assert(reopened.terminationStatus == 0);
        [isolated removePersistentDomainForName:domain]; [isolated synchronize];
        [NSFileManager.defaultManager removeItemAtPath:ready error:nil];
        puts("Defaults, legacy OFF, onboarding preview, cross-process live updates and relaunch persistence passed.");
    }
    return 0;
}
