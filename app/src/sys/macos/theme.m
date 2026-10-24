#include "theme.h"
#include "events.h"
#include "util/log.h"
#import <AppKit/AppKit.h>
#import "theme_chooser.h"
#import "settings.h"
#import "settings_ui.h"
#import "localization.h"

static BOOL lightTheme;
static BOOL initialized;
static void *SCThemeAppearanceContext = &SCThemeAppearanceContext;

@interface SCThemeController : NSObject
@property(nonatomic, copy) NSString *choice;
- (void)apply:(NSString *)choice;
- (void)refreshAppearance;
- (void)settingsChanged:(NSNotification *)notification;
@end
@implementation SCThemeController
- (instancetype)init {
    self = [super init];
    if (self) {
        [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:SCThemeAppearanceContext];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:)
            name:SCSettingsChangedNotification object:nil];
    }
    return self;
}
- (void)dealloc {
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:SCThemeAppearanceContext];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == SCThemeAppearanceContext) { [self refreshAppearance]; }
    else { [super observeValueForKeyPath:path ofObject:object change:change context:context]; }
}
- (void)apply:(NSString *)choice {
    self.choice = choice;
    NSApp.appearance = [choice isEqualToString:@"system"] ? nil
        : [NSAppearance appearanceNamed:[choice isEqualToString:@"light"] ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    [self refreshAppearance];
}
- (void)refreshAppearance {
    lightTheme = [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameAqua];
    for (NSWindow *window in NSApp.windows) { [window.contentView setNeedsDisplay:YES]; }
    sc_push_event(SC_EVENT_THEME_CHANGED);
}
- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    if (![self.choice isEqualToString:SCSettingsTheme()]) { [self apply:SCSettingsTheme()]; }
}
@end
static SCThemeController *themeController;

bool sc_theme_is_light(void) { return lightTheme; }

bool sc_theme_initialize(void) {
    if (initialized || !sc_settings_is_app()) { return true; }
    if (!SDL_WasInit(SDL_INIT_VIDEO) && !SDL_InitSubSystem(SDL_INIT_VIDEO)) {
        LOGE("Could not initialize application settings: %s", SDL_GetError()); return false;
    }
    SCSettingsInitialize();
    themeController = [[SCThemeController alloc] init];
    initialized = YES;
    [themeController apply:SCSettingsTheme()];
    if (!SCSettingsHasTheme()) {
        NSString *savedLanguage = SCSettingsLanguage();
        SCThemeChooser *chooser = [[SCThemeChooser alloc] initWithLanguage:savedLanguage];
        chooser.change = ^(NSString *choice) { [themeController apply:choice]; };
        chooser.languageChanged = ^(NSString *choice) { SCSettingsPreviewLanguage(choice); };
        [chooser.window center]; [NSApp activateIgnoringOtherApps:YES]; [chooser.window makeKeyAndOrderFront:nil];
        NSModalResponse response = [NSApp runModalForWindow:chooser.window];
        [chooser.window orderOut:nil];
        if (response != NSModalResponseOK) {
            SCSettingsEndLanguagePreview();
            initialized = NO; themeController = nil; return false;
        }
        SCSettingsAcceptOnboarding(chooser.selection, chooser.languageSelection);
    }
    SCSettingsInstallMenu();
    return true;
}

void sc_theme_install_menu(void) { SCSettingsInstallMenu(); }
