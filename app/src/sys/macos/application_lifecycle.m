#import "application_lifecycle.h"
#import "mirror_session.h"
#include <SDL3/SDL.h>

static BOOL SCApplicationWindowOpen(NSWindow *window) {
    return (window.styleMask & NSWindowStyleMaskTitled)
        && (window.visible || window.miniaturized);
}

BOOL SCApplicationHasWindows(void) {
    for (NSWindow *window in NSApp.windows) {
        if (SCApplicationWindowOpen(window)) { return YES; }
    }
    return NO;
}

static NSString *SCApplicationQuitNotification(void) {
    return [SCMirrorHostBundleIdentifier() stringByAppendingString:@".Quit"];
}

@interface SCApplicationLifecycle : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) id<NSApplicationDelegate> sdlDelegate;
@property(nonatomic, copy) void (^showDevices)(void);
@property(nonatomic, copy) BOOL (^openFile)(NSString *path);
@property(nonatomic) BOOL quitting, scheduled;
- (void)terminate:(id)sender;
@end

@implementation SCApplicationLifecycle
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.sdlDelegate respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return [self.sdlDelegate respondsToSelector:selector] ? self.sdlDelegate
        : [super forwardingTargetForSelector:selector];
}
- (void)updateActivationPolicy {
    if (self.quitting || NSApp.activationPolicy == NSApplicationActivationPolicyProhibited) { return; }
    NSApplicationActivationPolicy policy = SCApplicationHasWindows()
        ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory;
    if (NSApp.activationPolicy != policy) { [NSApp setActivationPolicy:policy]; }
}
- (void)windowChanged:(NSNotification *)notification {
    (void)notification;
    if (self.scheduled) { return; }
    self.scheduled = YES;
    // WillClose is delivered before the window is removed from AppKit's list.
    dispatch_async(dispatch_get_main_queue(), ^{
        self.scheduled = NO;
        [self updateActivationPolicy];
    });
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    (void)sender; (void)visible;
    if (self.quitting) { return NO; }
    if (NSApp.activationPolicy != NSApplicationActivationPolicyProhibited) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    }
    // Restore an existing window, including a minimized one, before creating UI.
    NSWindow *existing = nil;
    for (NSWindow *window in NSApp.orderedWindows) {
        if (SCApplicationWindowOpen(window)) { existing = window; break; }
    }
    if (!existing) {
        for (NSWindow *window in NSApp.windows) {
            if (SCApplicationWindowOpen(window)) { existing = window; break; }
        }
    }
    if (existing) {
        if (existing.miniaturized) { [existing deminiaturize:nil]; }
        [NSApp unhide:nil];
        [existing makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    } else if (self.showDevices) {
        self.showDevices();
    }
    return NO; // We handled the reopen; AppKit must not create another window.
}
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if (self.openFile && self.openFile(filename)) {
        return YES;
    }
    if ([self.sdlDelegate respondsToSelector:@selector(application:openFile:)]) {
        return [self.sdlDelegate application:sender openFile:filename];
    }
    return NO;
}
- (void)quitReceived:(NSNotification *)notification {
    (void)notification;
    if (self.quitting) { return; }
    self.quitting = YES;
    SDL_Event event = {.type = SDL_EVENT_QUIT};
    SDL_PushEvent(&event);
}
- (void)terminate:(id)sender {
    (void)sender;
    SCApplicationRequestQuit();
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    SCApplicationRequestQuit();
    return NSTerminateCancel; // Let SDL unwind and stop reconnect listeners.
}
@end

static SCApplicationLifecycle *lifecycle;

void SCApplicationRequestQuit(void) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:SCApplicationQuitNotification()
        object:nil userInfo:nil deliverImmediately:YES];
    [lifecycle quitReceived:nil];
}

void SCApplicationLifecycleInstall(void (^showDevices)(void),
                                   BOOL (^openFile)(NSString *path)) {
    if (!lifecycle) {
        lifecycle = [[SCApplicationLifecycle alloc] init];
        lifecycle.sdlDelegate = NSApp.delegate;
        NSApp.delegate = lifecycle;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[NSWindowDidUpdateNotification, NSWindowWillCloseNotification,
                NSWindowDidMiniaturizeNotification, NSWindowDidDeminiaturizeNotification]) {
            [center addObserver:lifecycle selector:@selector(windowChanged:) name:name object:nil];
        }
        [NSDistributedNotificationCenter.defaultCenter addObserver:lifecycle selector:@selector(quitReceived:)
            name:SCApplicationQuitNotification() object:nil
            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    }
    lifecycle.showDevices = showDevices;
    lifecycle.openFile = openFile;
    NSMenu *appMenu = NSApp.mainMenu.numberOfItems ? [NSApp.mainMenu itemAtIndex:0].submenu : nil;
    for (NSMenuItem *item in appMenu.itemArray) {
        if (item.action == @selector(terminate:)) { item.target = lifecycle; }
    }
    [lifecycle windowChanged:nil];
}
