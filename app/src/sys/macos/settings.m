#include "events.h"
#include "toolbar_preferences.h"
#import "settings.h"
#import "localization.h"
#import "mirror_session.h"
#import <AppKit/AppKit.h>

NSNotificationName const SCSettingsChangedNotification = @"AnmirSettingsChanged";
static NSString *const SCThemeKey = @"AnmirTheme";
static NSString *const SCLanguageKey = @"AnmirLanguage";
static NSString *const SCToolbarKey = @"AnmirToolbarVisible";
static NSUserDefaults *defaults;
static NSString *previewLanguage;

bool sc_settings_is_app(void) {
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundlePackageType"] isEqualToString:@"APPL"];
}

static NSUserDefaults *SCSettingsDefaults(void) {
    if (!defaults) {
        defaults = [SCMirrorHostBundleIdentifier() isEqualToString:NSBundle.mainBundle.bundleIdentifier]
            ? NSUserDefaults.standardUserDefaults
            : [[NSUserDefaults alloc] initWithSuiteName:SCMirrorHostBundleIdentifier()];
        // Preserve choices made in the development app without changing its store.
        if ([SCMirrorHostBundleIdentifier() isEqualToString:@"io.github.laobie.anmir"]) {
            NSDictionary *legacy = [defaults persistentDomainForName:@"com.genymobile.scrcpy"];
            NSDictionary *keys = @{@"ScrcpyXTheme": SCThemeKey,
                @"ScrcpyXLanguage": SCLanguageKey, @"ScrcpyXToolbarVisible": SCToolbarKey};
            for (NSString *oldKey in keys) {
                NSString *newKey = keys[oldKey];
                if (![defaults objectForKey:newKey] && legacy[oldKey]) {
                    [defaults setObject:legacy[oldKey] forKey:newKey];
                }
            }
        }
    }
    return defaults;
}

NSString *SCSettingsTheme(void) {
    NSString *value = [SCSettingsDefaults() stringForKey:SCThemeKey];
    return [@[@"system", @"light", @"dark"] containsObject:value ?: @""] ? value : @"system";
}
BOOL SCSettingsHasTheme(void) {
    return [@[@"system", @"light", @"dark"] containsObject:[SCSettingsDefaults() stringForKey:SCThemeKey] ?: @""];
}
NSString *SCSettingsLanguage(void) {
    NSString *value = [SCSettingsDefaults() stringForKey:SCLanguageKey];
    return [@[@"system", @"en", @"zh-Hans", @"zh-Hant"] containsObject:value ?: @""] ? value : @"system";
}
bool sc_settings_toolbar_visible(void) {
    id value = [SCSettingsDefaults() objectForKey:SCToolbarKey];
    if (value) { return [value boolValue]; }
    bool visible;
    return sc_toolbar_preferences_load_saved_visible(&visible) ? visible : true;
}

@interface SCSettingsObserver : NSObject
@property(nonatomic, copy) NSString *notification;
@property(nonatomic, copy) NSArray *snapshot;
- (void)refresh:(NSNotification *)notification;
@end
@implementation SCSettingsObserver
- (void)refresh:(NSNotification *)notification {
    (void)notification;
    NSAssert(NSThread.isMainThread, @"Settings updates run on the main thread");
    [SCSettingsDefaults() synchronize];
    NSArray *latest = @[SCSettingsTheme(), SCSettingsLanguage(), @(sc_settings_toolbar_visible())];
    // Re-resolve System at activation even if the stored choice is unchanged.
    SCUseLanguage(previewLanguage ?: latest[1]);
    if ([latest isEqualToArray:self.snapshot]) { return; }
    self.snapshot = latest;
    [NSNotificationCenter.defaultCenter postNotificationName:SCSettingsChangedNotification object:nil];
    sc_push_event(SC_EVENT_SETTINGS_CHANGED);
}
@end
static SCSettingsObserver *observer;

static BOOL SCSettingsSave(NSString *key, id value) {
    [SCSettingsDefaults() setObject:value forKey:key];
    BOOL saved = [SCSettingsDefaults() synchronize];
    [observer refresh:nil];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:observer.notification
        object:nil userInfo:nil deliverImmediately:YES];
    return saved;
}
void SCSettingsAcceptOnboarding(NSString *theme, NSString *language) {
    previewLanguage = nil;
    [SCSettingsDefaults() setObject:language forKey:SCLanguageKey];
    SCSettingsSave(SCThemeKey, theme);
}
void SCSettingsSetTheme(NSString *choice) {
    if ([@[@"system", @"light", @"dark"] containsObject:choice]) { SCSettingsSave(SCThemeKey, choice); }
}
void SCSettingsSetLanguage(NSString *choice) {
    if ([@[@"system", @"en", @"zh-Hans", @"zh-Hant"] containsObject:choice]) { SCSettingsSave(SCLanguageKey, choice); }
}
void SCSettingsPreviewLanguage(NSString *choice) {
    previewLanguage = [choice copy];
    SCUseLanguage(choice);
}
void SCSettingsEndLanguagePreview(void) {
    previewLanguage = nil;
    [observer refresh:nil];
}
bool sc_settings_set_toolbar_visible(bool visible) { return SCSettingsSave(SCToolbarKey, @(visible)); }

void SCSettingsInitialize(void) {
    if (observer) { return; }
    observer = [[SCSettingsObserver alloc] init];
    observer.notification = [SCMirrorHostBundleIdentifier() stringByAppendingString:@".SettingsChanged"];
    SCLocalizationInitialize(SCMirrorHostBundle(), SCSettingsLanguage());
    [observer refresh:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:observer selector:@selector(refresh:)
        name:observer.notification object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(refresh:)
        name:NSApplicationDidBecomeActiveNotification object:nil];
}
