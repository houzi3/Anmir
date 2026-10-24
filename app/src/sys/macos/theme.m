#include "theme.h"
#include "events.h"
#include "util/log.h"

#import <AppKit/AppKit.h>
#import "device_ui.h"
#import "theme_ui.h"
#import "theme_chooser.h"
#import "mirror_session.h"

static NSString *const SCThemePreference = @"ScrcpyXTheme";
static BOOL lightTheme;
static BOOL initialized;
static NSUserDefaults *SCThemeDefaults(void) {
    static NSUserDefaults *defaults;
    if (!defaults) {
        defaults = [SCMirrorHostBundleIdentifier() isEqualToString:NSBundle.mainBundle.bundleIdentifier]
            ? NSUserDefaults.standardUserDefaults
            : [[NSUserDefaults alloc] initWithSuiteName:SCMirrorHostBundleIdentifier()];
    }
    return defaults;
}
static void *SCThemeAppearanceContext = &SCThemeAppearanceContext;

static BOOL SCThemeChoiceValid(NSString *choice) {
    return [@[@"system", @"light", @"dark"] containsObject:choice ?: @""];
}

static BOOL
sc_theme_is_app(void) {
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundlePackageType"]
        isEqualToString:@"APPL"];
}

@interface SCThemeController : NSObject <NSMenuItemValidation>
@property(nonatomic, copy) NSString *notificationName;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, strong) NSHashTable<NSButton *> *buttons;
@property(nonatomic, copy) NSString *choice;
- (void)apply:(NSString *)choice;
- (void)refreshAppearance;
- (void)selectTheme:(NSMenuItem *)item;
- (void)save:(NSString *)choice;
- (void)toggle:(id)sender;
- (void)preferenceChanged:(NSNotification *)notification;
@end

@implementation SCThemeController
- (instancetype)init {
    self = [super init];
    if (self) {
        [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:SCThemeAppearanceContext];
    }
    return self;
}
- (void)dealloc {
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:SCThemeAppearanceContext];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == SCThemeAppearanceContext) { [self refreshAppearance]; }
    else { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; }
}
- (void)apply:(NSString *)choice {
    self.choice = choice;
    NSApp.appearance = [choice isEqualToString:@"system"] ? nil
        : [NSAppearance appearanceNamed:[choice isEqualToString:@"light"]
            ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    [self refreshAppearance];
}
- (void)refreshAppearance {
    lightTheme = [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameAqua];
    for (NSWindow *window in NSApp.windows) {
        [window.contentView setNeedsDisplay:YES];
    }
    for (NSMenuItem *item in self.menu.itemArray) {
        item.state = [item.representedObject isEqualToString:self.choice]
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSButton *button in self.buttons) {
        button.image = SCDeviceSymbol(lightTheme ? @"moon" : @"sun.max");
        button.toolTip = lightTheme ? @"Switch to Dark" : @"Switch to Light";
        button.accessibilityLabel = button.toolTip;
    }
    sc_push_event(SC_EVENT_THEME_CHANGED);
}

- (void)selectTheme:(NSMenuItem *)item {
    [self save:item.representedObject];
}

- (void)toggle:(id)sender {
    (void)sender;
    [self save:lightTheme ? @"dark" : @"light"];
}

- (void)save:(NSString *)choice {
    NSUserDefaults *defaults = SCThemeDefaults();
    [defaults setObject:choice forKey:SCThemePreference];
    if (![defaults synchronize]) {
        LOGW("Could not persist the theme preference");
    }
    [self apply:choice];
    [NSDistributedNotificationCenter.defaultCenter
        postNotificationName:self.notificationName object:nil
        userInfo:nil deliverImmediately:YES];
}

- (void)preferenceChanged:(NSNotification *)notification {
    (void) notification;
    // Each mirror runs in its own process. Read the shared app preference so
    // switching in any window also updates the manager and the other mirrors.
    [SCThemeDefaults() synchronize];
    NSString *choice = [SCThemeDefaults()
        stringForKey:SCThemePreference];
    if (SCThemeChoiceValid(choice)) {
        [self apply:choice];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    item.state = [item.representedObject isEqualToString:self.choice]
        ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}
@end

static SCThemeController *themeController;

NSButton *SCThemeButton(void) {
    NSButton *button = [SCDeviceIconButton buttonWithImage:SCDeviceSymbol(lightTheme ? @"moon" : @"sun.max") target:themeController action:@selector(toggle:)];
    button.toolTip = lightTheme ? @"Switch to Dark" : @"Switch to Light";
    button.accessibilityLabel = button.toolTip;
    [themeController.buttons addObject:button];
    return button;
}


bool
sc_theme_is_light(void) {
    return lightTheme;
}

bool
sc_theme_initialize(void) {
    if (initialized || !sc_theme_is_app()) {
        return true;
    }
    if (!SDL_WasInit(SDL_INIT_VIDEO) && !SDL_InitSubSystem(SDL_INIT_VIDEO)) {
        LOGE("Could not initialize the theme chooser: %s", SDL_GetError());
        return false;
    }
    initialized = YES;
    themeController = [[SCThemeController alloc] init];
    themeController.buttons = [NSHashTable weakObjectsHashTable];
    themeController.notificationName = [SCMirrorHostBundleIdentifier()
        stringByAppendingString:@".ScrcpyXThemeChanged"];
    NSString *choice = [SCThemeDefaults()
        stringForKey:SCThemePreference];
    if (!SCThemeChoiceValid(choice)) {
        [themeController apply:@"system"];
        SCThemeChooser *chooser = [[SCThemeChooser alloc] init];
        chooser.change = ^(NSString *value) { [themeController apply:value]; };
        [chooser.window center];
        [NSApp activateIgnoringOtherApps:YES];
        [chooser.window makeKeyAndOrderFront:nil];
        NSModalResponse response = [NSApp runModalForWindow:chooser.window];
        [chooser.window orderOut:nil];
        if (response != NSModalResponseOK) {
            initialized = NO;
            themeController = nil;
            return false;
        }
        choice = chooser.selection;
        [themeController save:choice];
    } else {
        [themeController apply:choice];
    }
    [NSDistributedNotificationCenter.defaultCenter addObserver:themeController
        selector:@selector(preferenceChanged:) name:themeController.notificationName
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    sc_theme_install_menu();
    return true;
}

void
sc_theme_install_menu(void) {
    if (!themeController || !NSApp.mainMenu.numberOfItems) {
        return;
    }
    NSMenu *appMenu = [NSApp.mainMenu itemAtIndex:0].submenu;
    if (!appMenu || [appMenu itemWithTag:0x53435448]) {
        return;
    }
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"Theme"
        action:nil keyEquivalent:@""];
    root.tag = 0x53435448;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Theme"];
    for (NSString *choice in @[@"system", @"light", @"dark"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice.capitalizedString
            action:@selector(selectTheme:) keyEquivalent:@""];
        item.target = themeController;
        item.representedObject = choice;
        [menu addItem:item];
    }
    root.submenu = menu;
    themeController.menu = menu;
    [appMenu insertItem:root atIndex:MIN(3, appMenu.numberOfItems)];
}
