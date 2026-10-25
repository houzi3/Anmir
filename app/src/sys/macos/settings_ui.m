#include "util/log.h"
#import "settings_ui.h"
#import "settings_window.h"
#import "settings.h"
#import "localization.h"
#import "device_ui.h"
#import "mirror_session.h"

@interface SCSettingsActions : NSObject
@property(nonatomic, strong) SCSettingsWindowController *controller;
- (void)show:(id)sender;
- (void)refresh:(NSNotification *)notification;
- (void)refreshMenus:(NSNotification *)notification;
@end
static SCSettingsActions *actions;
static NSString *SCSettingsShowNotification(void) {
    return [SCMirrorHostBundleIdentifier() stringByAppendingString:@".ShowSettings"];
}

void SCLocalizeApplicationMenus(void) {
    NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"Anmir";
    NSDictionary *titles = @{@"terminate:":@"Quit %@", @"hide:":@"Hide %@",
        @"hideOtherApplications:":@"Hide Others", @"unhideAllApplications:":@"Show All",
        @"orderFrontStandardAboutPanel:":@"About %@", @"performMiniaturize:":@"Minimize",
        @"performZoom:":@"Zoom", @"performClose:":@"Close", @"arrangeInFront:":@"Bring All to Front"};
    NSMutableArray *menus = [NSMutableArray array];
    if (NSApp.mainMenu) { [menus addObject:NSApp.mainMenu]; }
    while (menus.count) {
        NSMenu *menu = menus.lastObject; [menus removeLastObject];
        for (NSMenuItem *item in menu.itemArray) {
            NSString *key = titles[NSStringFromSelector(item.action) ?: @""];
            if (item.action == @selector(toggleFullScreen:)) {
                key = NSApp.keyWindow.styleMask & NSWindowStyleMaskFullScreen ? @"Exit Full Screen" : @"Enter Full Screen";
            }
            if (key) {
                if ([key containsString:@"%@"]) { SCBindFormat(item, @"title", key, @[name]); }
                else { SCBind(item, @"title", key); }
            }
            if (item.submenu == NSApp.windowsMenu) {
                SCBind(item, @"title", @"Window"); SCBind(item.submenu, @"title", @"Window");
            } else if (item.submenu == NSApp.servicesMenu) {
                SCBind(item, @"title", @"Services"); SCBind(item.submenu, @"title", @"Services");
            }
            if (item.submenu) { [menus addObject:item.submenu]; }
        }
    }
}

@implementation SCSettingsActions
- (void)show:(id)sender {
    (void)sender;
    NSBundle *host = SCMirrorHostBundle();
    if (![host.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        NSArray *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:host.bundleIdentifier];
        if (running.count) {
            // Let the host select Settings before it activates. Activating all
            // host windows here also raises the device list behind the mirror.
            if (@available(macOS 14.0, *)) { [NSApp yieldActivationToApplication:running.firstObject]; }
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:SCSettingsShowNotification()
                object:nil userInfo:nil deliverImmediately:YES];
        } else {
            if (@available(macOS 14.0, *)) { [NSApp yieldActivationToApplicationWithBundleIdentifier:host.bundleIdentifier]; }
            NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
            configuration.activates = NO;
            configuration.environment = @{@"ANMIR_SHOW_SETTINGS":@"1"};
            [NSWorkspace.sharedWorkspace openApplicationAtURL:host.bundleURL configuration:configuration
                completionHandler:^(NSRunningApplication *app, NSError *error) {
                    (void)app;
                    if (error) { LOGE("Could not open settings: %s", error.localizedDescription.UTF8String); }
                }];
        }
        return;
    }
    if (!self.controller) {
        self.controller = [[SCSettingsWindowController alloc] initWithTheme:SCSettingsTheme()
            language:SCSettingsLanguage() toolbarVisible:sc_settings_toolbar_visible()];
        self.controller.themeChanged = ^(NSString *choice) { SCSettingsSetTheme(choice); };
        self.controller.languageChanged = ^(NSString *choice) { SCSettingsSetLanguage(choice); };
        self.controller.toolbarChanged = ^(BOOL visible) { sc_settings_set_toolbar_visible(visible); };
        [self.controller.window center];
    }
    [self refresh:nil];
    NSWindow *window = self.controller.window;
    if (window.miniaturized) { [window deminiaturize:nil]; }
    [window makeKeyAndOrderFront:nil];
    [window makeMainWindow];
    if (@available(macOS 14.0, *)) { [NSApp activate]; }
    else { [NSApp activateIgnoringOtherApps:YES]; }
}
- (void)refresh:(NSNotification *)notification {
    (void)notification;
    [self.controller updateTheme:SCSettingsTheme() language:SCSettingsLanguage() toolbarVisible:sc_settings_toolbar_visible()];
}
- (void)refreshMenus:(NSNotification *)notification {
    (void)notification;
    SCLocalizeApplicationMenus();
}
@end

static void SCSettingsEnsureActions(void) {
    if (actions) { return; }
    actions = [[SCSettingsActions alloc] init];
    [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(refreshMenus:)
        name:NSMenuDidBeginTrackingNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(refresh:)
        name:SCSettingsChangedNotification object:nil];
    // Only the host receives show requests. A mirror that receives its own
    // request would forward it again and create a notification loop.
    if ([SCMirrorHostBundleIdentifier() isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        [NSDistributedNotificationCenter.defaultCenter addObserver:actions selector:@selector(show:)
            name:SCSettingsShowNotification() object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    }
}
void SCSettingsShow(void) { SCSettingsEnsureActions(); [actions show:nil]; }
BOOL SCSettingsWindowVisible(void) { return actions.controller.window.visible; }

NSButton *SCSettingsButton(void) {
    SCSettingsEnsureActions();
    NSButton *button = [SCDeviceIconButton buttonWithImage:SCDeviceSymbol(@"gearshape") target:actions action:@selector(show:)];
    button.identifier = @"Anmir.Settings";
    SCBind(button, @"toolTip", @"Settings…"); SCBind(button, @"accessibilityLabel", @"Settings…");
    return button;
}

void SCSettingsInstallMenu(void) {
    if (!sc_settings_is_app() || !NSApp.mainMenu.numberOfItems) { return; }
    SCSettingsEnsureActions();
    NSMenu *menu = [NSApp.mainMenu itemAtIndex:0].submenu;
    if (![menu itemWithTag:0x53435345]) {
        NSMenuItem *item = nil;
        for (NSMenuItem *candidate in menu.itemArray) {
            if ([candidate.keyEquivalent isEqualToString:@","]) { item = candidate; break; }
        }
        if (!item) { item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@","]; [menu insertItem:item atIndex:MIN(2, menu.numberOfItems)]; }
        item.tag = 0x53435345; item.target = actions; item.action = @selector(show:);
        SCBind(item, @"title", @"Settings…");
    }
    SCLocalizeApplicationMenus();
}
