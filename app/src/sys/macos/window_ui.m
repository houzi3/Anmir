#include "device_picker.h"

#import <AppKit/AppKit.h>
#import "localization.h"
#import "settings_ui.h"
#import "device_picker_ui.h"
#import <objc/runtime.h>

#include "window_ui.h"
#include "theme.h"
#include "toolbar.h"
#import "device_ui.h"
#import "mirror_session.h"
#include "events.h"

#define SC_STATUS_BUBBLE_TAIL 6.f
#define SC_STATUS_BUBBLE_CORNER_RADIUS 9.f

@interface SCStatusBubbleView : NSView
@property(nonatomic, strong) NSTextField *label;
@property(nonatomic) BOOL pointsLeft;
@property(nonatomic) BOOL timer;
@property(nonatomic) BOOL lightTheme;
- (instancetype)initWithText:(NSString *)text timer:(BOOL)timer
    lightTheme:(BOOL)lightTheme;
- (void)updateText:(NSString *)text;
- (void)applyLightTheme:(BOOL)lightTheme;
@end

@implementation SCStatusBubbleView
- (instancetype)initWithText:(NSString *)text timer:(BOOL)timer
    lightTheme:(BOOL)lightTheme {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _timer = timer;
        _pointsLeft = YES;
        _label = [NSTextField labelWithString:text];
        _label.font = timer
            ? [NSFont monospacedDigitSystemFontOfSize:12
                                               weight:NSFontWeightMedium]
            : [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        _label.alignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByClipping;
        _label.maximumNumberOfLines = 1;
        [self addSubview:_label];
        [self applyLightTheme:lightTheme];
        [self updateText:text];
    }
    return self;
}
- (void)setPointsLeft:(BOOL)pointsLeft {
    if (_pointsLeft == pointsLeft) { return; }
    _pointsLeft = pointsLeft;
    [self updateText:self.label.stringValue];
    self.needsDisplay = YES;
}
- (void)updateText:(NSString *)text {
    self.label.stringValue = text;
    NSSize labelSize = self.label.fittingSize;
    CGFloat labelWidth = ceil(labelSize.width);
    CGFloat labelHeight = ceil(labelSize.height);
    CGFloat height = self.timer ? 28 : 30;
    // NSTextField's fitting width includes its internal text insets. Center
    // that complete control and let the bubble grow when the duration gains
    // an hour digit, instead of clipping the glyphs inside a fixed field.
    CGFloat bodyWidth = MAX(self.timer ? 54 : 72, labelWidth + 14);
    self.frame = NSMakeRect(0, 0, bodyWidth + SC_STATUS_BUBBLE_TAIL,
                            height);
    CGFloat bodyX = self.pointsLeft ? SC_STATUS_BUBBLE_TAIL : 0;
    // NSTextField draws a single-line label against the top of a tall frame.
    // Give it its natural height and center that frame explicitly so the
    // glyphs sit on the visual center of both status-bubble sizes.
    CGFloat labelY = floor((height - labelHeight) / 2.f);
    CGFloat labelX = bodyX + floor((bodyWidth - labelWidth) / 2.f);
    self.label.frame = NSMakeRect(labelX, labelY,
                                  labelWidth, labelHeight);
    self.needsDisplay = YES;
}
- (void)applyLightTheme:(BOOL)lightTheme {
    _lightTheme = lightTheme;
    self.appearance = [NSAppearance appearanceNamed:lightTheme
        ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    self.label.textColor = [NSColor colorWithWhite:lightTheme ? .18 : .95
                                             alpha:1];
    self.needsDisplay = YES;
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void) dirtyRect;
    NSColor *fill = [NSColor colorWithWhite:self.lightTheme ? .99 : .105
                                      alpha:.98];
    NSColor *border = [NSColor colorWithWhite:self.lightTheme ? 0 : 1
                                         alpha:.08];
    CGFloat bodyX = self.pointsLeft ? SC_STATUS_BUBBLE_TAIL : 0;
    NSRect body = NSMakeRect(bodyX, .5,
        NSWidth(self.bounds) - SC_STATUS_BUBBLE_TAIL,
        NSHeight(self.bounds) - 1);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:body
        xRadius:SC_STATUS_BUBBLE_CORNER_RADIUS
        yRadius:SC_STATUS_BUBBLE_CORNER_RADIUS];
    CGFloat middle = NSMidY(self.bounds);
    NSBezierPath *tail = [NSBezierPath bezierPath];
    if (self.pointsLeft) {
        [tail moveToPoint:NSMakePoint(0, middle)];
        [tail lineToPoint:NSMakePoint(SC_STATUS_BUBBLE_TAIL,
                                      middle - 5)];
        [tail lineToPoint:NSMakePoint(SC_STATUS_BUBBLE_TAIL,
                                      middle + 5)];
    } else {
        [tail moveToPoint:NSMakePoint(NSWidth(self.bounds), middle)];
        [tail lineToPoint:NSMakePoint(NSWidth(self.bounds)
                                      - SC_STATUS_BUBBLE_TAIL,
                                      middle - 5)];
        [tail lineToPoint:NSMakePoint(NSWidth(self.bounds)
                                      - SC_STATUS_BUBBLE_TAIL,
                                      middle + 5)];
    }
    [tail closePath];
    [fill setFill];
    [shape fill];
    [tail fill];
    [border setStroke];
    shape.lineWidth = .75;
    [shape stroke];
}
@end

@interface SCScrcpyWindowUI : NSObject <NSToolbarDelegate>
@property(nonatomic, strong) NSStackView *titleStack;
@property(nonatomic, strong) NSTextField *primaryLabel;
@property(nonatomic, strong) NSTextField *secondaryLabel;
@property(nonatomic, strong) NSPanel *toastPanel;
@property(nonatomic) NSUInteger toastGeneration;
@property(nonatomic, strong) NSPanel *toolbarFeedbackPanel;
@property(nonatomic) NSUInteger toolbarFeedbackGeneration;
@property(nonatomic) CGFloat toolbarFeedbackAnchorY;
@property(nonatomic, strong) NSPanel *recordingTimerPanel;
@property(nonatomic) sc_window_ui_toolbar_toggle_cb toolbarToggleCallback;
@property(nonatomic) void *toolbarToggleUserdata;
@property(nonatomic, strong) NSMenuItem *toolbarMenuItem;
@property(nonatomic, strong) NSMenuItem *toolbarMenuContainer;
@property(nonatomic) BOOL ownsToolbarMenuContainer;
@property(nonatomic, strong) NSToolbar *titleToolbar;
@end

@implementation SCScrcpyWindowUI
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"Anmir.Mirror.Actions"];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar; (void)inserted;
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    NSView *container = SCDeviceToolbarGroup(@[SCDevicePickerButton(), SCSettingsButton()]);
    item.view = container;
    item.minSize = item.maxSize = container.frame.size;
    item.bordered = NO;
    item.autovalidates = NO;
    item.enabled = YES;
    SCBind(item, @"label", @"Device actions");
    return item;
}
- (void)toggleToolbar:(id)sender {
    (void) sender;
    if (self.toolbarToggleCallback) {
        self.toolbarToggleCallback(self.toolbarToggleUserdata);
    }
}
@end

static const void *SC_WINDOW_UI_KEY = &SC_WINDOW_UI_KEY;

static NSWindow *
sc_window_ui_get_native_sdl_window(SDL_Window *window) {
    if (!window) { return nil; }
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    void *pointer = SDL_GetPointerProperty(
        props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    return (__bridge NSWindow *) pointer;
}

static NSWindow *
sc_window_ui_get_native_window(struct sc_window_ui *ui) {
    return sc_window_ui_get_native_sdl_window(ui->window);
}

static NSTextField *
sc_window_ui_create_label(void) {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    return label;
}

static SCScrcpyWindowUI *
sc_window_ui_get_controller(NSWindow *window) {
    SCScrcpyWindowUI *ui = objc_getAssociatedObject(window, SC_WINDOW_UI_KEY);
    if (ui) {
        return ui;
    }

    ui = [[SCScrcpyWindowUI alloc] init];
    objc_setAssociatedObject(window, SC_WINDOW_UI_KEY, ui,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return ui;
}

static bool
sc_window_ui_is_app(void) {
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundlePackageType"]
        isEqualToString:@"APPL"];
}

static void
sc_window_ui_apply_title_colors(SCScrcpyWindowUI *ui) {
    // Standalone CLI windows follow AppKit's appearance, independently from
    // the GUI app's saved theme. Keep their native title contrast intact.
    ui.primaryLabel.textColor = sc_window_ui_is_app()
        ? [NSColor colorWithWhite:sc_theme_is_light() ? 0.16 : 0.92 alpha:1]
        : NSColor.labelColor;
    ui.secondaryLabel.textColor = sc_window_ui_is_app()
        ? [NSColor colorWithWhite:sc_theme_is_light() ? 0.46 : 0.65 alpha:1]
        : NSColor.secondaryLabelColor;
}

static SCScrcpyWindowUI *
sc_window_ui_get_or_create_title(NSWindow *window) {
    SCScrcpyWindowUI *ui = sc_window_ui_get_controller(window);
    if (ui.titleStack) {
        return ui;
    }

    NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
    NSButton *lastWindowButton = [window standardWindowButton:NSWindowZoomButton]
        ?: closeButton;
    NSView *titlebar = closeButton.superview;
    if (!titlebar) {
        return ui;
    }

    ui.primaryLabel = sc_window_ui_create_label();
    ui.primaryLabel.font = [NSFont systemFontOfSize:13
                                            weight:NSFontWeightSemibold];
    [ui.primaryLabel
        setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
        forOrientation:NSLayoutConstraintOrientationHorizontal];

    ui.secondaryLabel = sc_window_ui_create_label();
    ui.secondaryLabel.font = [NSFont systemFontOfSize:9
                                              weight:NSFontWeightRegular];
    sc_window_ui_apply_title_colors(ui);
    ui.secondaryLabel.alphaValue = 1;
    [ui.secondaryLabel
        setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
        forOrientation:NSLayoutConstraintOrientationHorizontal];

    ui.titleStack = [NSStackView stackViewWithViews:@[
        ui.primaryLabel, ui.secondaryLabel
    ]];
    ui.titleStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    ui.titleStack.alignment = NSLayoutAttributeCenterY;
    ui.titleStack.spacing = 6;
    ui.titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [titlebar addSubview:ui.titleStack];
    [NSLayoutConstraint activateConstraints:@[
        [ui.titleStack.centerXAnchor
            constraintEqualToAnchor:titlebar.centerXAnchor],
        [ui.titleStack.centerYAnchor
            constraintEqualToAnchor:titlebar.centerYAnchor constant:-.5],
        [ui.titleStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:
            lastWindowButton.trailingAnchor constant:12],
        [ui.titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:
            titlebar.trailingAnchor constant:sc_window_ui_is_app() ? -84 : -48],
    ]];

    window.titleVisibility = NSWindowTitleHidden;
    return ui;
}

void
sc_window_ui_init(struct sc_window_ui *ui, SDL_Window *window) {
    ui->window = window;
    ui->data = NULL;
    sc_device_picker_install_menu(window);
    sc_theme_install_menu();
    if (sc_window_ui_is_app()) {
        SCDeviceInstallMirrorIcon(NSBundle.mainBundle);
        NSWindow *native = sc_window_ui_get_native_window(ui);
        SCScrcpyWindowUI *controller = sc_window_ui_get_controller(native);
        // Let AppKit size and align the traffic lights and device/settings controls in a
        // roomier native titlebar rather than adding a second accessory row.
        controller.titleToolbar = [[NSToolbar alloc]
            initWithIdentifier:@"Anmir.Mirror.Toolbar"];
        controller.titleToolbar.delegate = controller;
        controller.titleToolbar.allowsUserCustomization = NO;
        controller.titleToolbar.displayMode = NSToolbarDisplayModeIconOnly;
        native.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
        native.toolbar = controller.titleToolbar;
    }
}

bool
sc_window_ui_has_bundle_icon(void) {
    NSString *icon = [NSBundle.mainBundle.infoDictionary
        objectForKey:@"CFBundleIconFile"];
    return icon.length > 0;
}

void
sc_window_ui_set_device_title(struct sc_window_ui *window_ui,
                              const char *primary,
                              const char *secondary) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window) {
        return;
    }

    SCScrcpyWindowUI *ui = sc_window_ui_get_or_create_title(window);
    if (!ui.titleStack) {
        return;
    }

    ui.primaryLabel.stringValue = primary
        ? [NSString stringWithUTF8String:primary] : @"";
    bool hasSecondary = secondary && *secondary;
    ui.secondaryLabel.hidden = !hasSecondary;
    ui.secondaryLabel.stringValue = hasSecondary
        ? [NSString stringWithUTF8String:secondary] : @"";
}

static NSPanel *
sc_window_ui_create_toast_panel(NSString *message) {
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 178, 38)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = YES;
    panel.ignoresMouseEvents = YES;
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorTransient
                             | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSDictionary *font = @{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]};
    CGFloat width = MAX([message sizeWithAttributes:font].width, [SCLocalized(message) sizeWithAttributes:font].width);
    [panel setContentSize:NSMakeSize(MAX(178, ceil(width) + 28), 38)];
    NSView *background =
        [[NSView alloc] initWithFrame:panel.contentView.bounds];
    background.wantsLayer = YES;
    background.layer.backgroundColor =
        [NSColor colorWithWhite:sc_theme_is_light() ? .98 : .08 alpha:.94].CGColor;
    background.layer.cornerRadius = 12;
    panel.contentView = background;

    NSTextField *label = SCDeviceLocalizedLabel(message, 13, NSFontWeightMedium, NO);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.textColor = sc_window_ui_is_app() ? NSColor.labelColor : NSColor.whiteColor;
    label.alignment = NSTextAlignmentCenter;
    [background addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:
            background.leadingAnchor constant:14],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:
            background.trailingAnchor constant:-14],
    ]];
    return panel;
}

void
sc_window_ui_show_toast(struct sc_window_ui *window_ui, const char *text) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window || !text) {
        return;
    }

    SCScrcpyWindowUI *ui = sc_window_ui_get_controller(window);

    if (ui.toastPanel) {
        [window removeChildWindow:ui.toastPanel];
        [ui.toastPanel orderOut:nil];
    }
    NSString *message = [NSString stringWithUTF8String:text];
    ui.toastPanel = sc_window_ui_create_toast_panel(message);
    [window addChildWindow:ui.toastPanel ordered:NSWindowAbove];

    NSRect parentFrame = window.frame;
    NSRect toastFrame = ui.toastPanel.frame;
    toastFrame.origin.x = NSMidX(parentFrame) - NSWidth(toastFrame) / 2;
    toastFrame.origin.y = NSMinY(parentFrame) + 58;
    [ui.toastPanel setFrame:toastFrame display:NO];
    ui.toastPanel.alphaValue = 0;
    [ui.toastPanel orderFront:nil];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = .12;
        ui.toastPanel.animator.alphaValue = 1;
    } completionHandler:nil];

    NSUInteger generation = ++ui.toastGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t) (2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (ui.toastGeneration != generation || !ui.toastPanel) {
            return;
        }
        NSPanel *panel = ui.toastPanel;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = .18;
            panel.animator.alphaValue = 0;
        } completionHandler:^{
            if (ui.toastGeneration == generation) {
                [window removeChildWindow:panel];
                [panel orderOut:nil];
                ui.toastPanel = nil;
            }
        }];
    });
}

static NSPanel *
sc_window_ui_create_status_panel(NSString *text, BOOL timer) {
    SCStatusBubbleView *view = [[SCStatusBubbleView alloc]
        initWithText:text timer:timer lightTheme:sc_theme_is_light()];
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:view.bounds
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = YES;
    panel.ignoresMouseEvents = YES;
    panel.hidesOnDeactivate = NO;
    panel.collectionBehavior = NSWindowCollectionBehaviorTransient
                             | NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.contentView = view;
    return panel;
}

static void
sc_window_ui_position_status_panel(NSPanel *panel, SDL_Window *toolbar,
                                   float anchorY, bool outwardLeft) {
    NSWindow *nativeToolbar = sc_window_ui_get_native_sdl_window(toolbar);
    if (!panel || !nativeToolbar) { return; }
    SCStatusBubbleView *view = (SCStatusBubbleView *) panel.contentView;
    view.pointsLeft = !outwardLeft;
    [panel setContentSize:view.frame.size];

    NSRect toolbarFrame = nativeToolbar.frame;
    NSSize size = panel.frame.size;
    CGFloat panelLeft = NSMinX(toolbarFrame) + SC_TOOLBAR_SHADOW_MARGIN;
    CGFloat x = outwardLeft
        ? panelLeft - SC_TOOLBAR_ACCESSORY_GAP - size.width
        : panelLeft + SC_TOOLBAR_PANEL_WIDTH + SC_TOOLBAR_ACCESSORY_GAP;
    CGFloat centerY = NSMaxY(toolbarFrame) - anchorY;
    CGFloat y = centerY - size.height / 2;

    NSScreen *screen = nativeToolbar.screen ?: NSScreen.mainScreen;
    if (screen) {
        NSRect visible = NSInsetRect(screen.visibleFrame, 4, 4);
        x = MAX(NSMinX(visible), MIN(x, NSMaxX(visible) - size.width));
        y = MAX(NSMinY(visible), MIN(y, NSMaxY(visible) - size.height));
    }
    [panel setFrameOrigin:NSMakePoint(round(x), round(y))];
}

static void
sc_window_ui_announce(NSString *message) {
    if (!message.length) { return; }
    NSAccessibilityPostNotificationWithUserInfo(
        NSApp, NSAccessibilityAnnouncementRequestedNotification, @{
            NSAccessibilityAnnouncementKey: message,
            NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium),
        });
}

void
sc_window_ui_show_toolbar_feedback(struct sc_window_ui *window_ui,
                                   SDL_Window *toolbar, float anchorY,
                                   bool outwardLeft, const char *text) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window || !toolbar || !text
            || !sc_window_ui_get_native_sdl_window(toolbar)) {
        sc_window_ui_show_toast(window_ui, text);
        return;
    }
    SCScrcpyWindowUI *ui = sc_window_ui_get_controller(window);
    if (ui.toolbarFeedbackPanel) {
        [window removeChildWindow:ui.toolbarFeedbackPanel];
        [ui.toolbarFeedbackPanel orderOut:nil];
    }
    NSString *key = [NSString stringWithUTF8String:text];
    NSString *message = SCLocalized(key);
    NSPanel *panel = sc_window_ui_create_status_panel(message, NO);
    ui.toolbarFeedbackPanel = panel;
    ui.toolbarFeedbackAnchorY = anchorY;
    [window addChildWindow:panel ordered:NSWindowAbove];
    sc_window_ui_position_status_panel(panel, toolbar, anchorY,
                                       outwardLeft);
    panel.alphaValue = 0;
    [panel orderFront:nil];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = .12;
        panel.animator.alphaValue = 1;
    } completionHandler:nil];
    sc_window_ui_announce(message);

    NSUInteger generation = ++ui.toolbarFeedbackGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t) (1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (ui.toolbarFeedbackGeneration != generation
                || ui.toolbarFeedbackPanel != panel) {
            return;
        }
        ui.toolbarFeedbackPanel = nil;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = .16;
            panel.animator.alphaValue = 0;
        } completionHandler:^{
            [window removeChildWindow:panel];
            [panel orderOut:nil];
        }];
    });
}

static NSString *
sc_window_ui_recording_time(uint64_t elapsed) {
    uint64_t seconds = elapsed % 60;
    uint64_t minutes = elapsed / 60;
    if (minutes < 60) {
        return [NSString stringWithFormat:@"%02llu:%02llu", minutes,
                                          seconds];
    }
    return [NSString stringWithFormat:@"%llu:%02llu:%02llu", minutes / 60,
                                      minutes % 60, seconds];
}

void
sc_window_ui_update_toolbar_accessories(struct sc_window_ui *window_ui,
                                        SDL_Window *toolbar,
                                        float recordAnchorY,
                                        bool outwardLeft, bool visible,
                                        bool recording,
                                        uint64_t elapsedSeconds) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window) { return; }
    SCScrcpyWindowUI *ui = sc_window_ui_get_controller(window);

    if (ui.toolbarFeedbackPanel) {
        sc_window_ui_position_status_panel(ui.toolbarFeedbackPanel, toolbar,
                                           ui.toolbarFeedbackAnchorY,
                                           outwardLeft);
        if (visible && !ui.toolbarFeedbackPanel.visible) {
            [ui.toolbarFeedbackPanel orderFront:nil];
        } else if (!visible && ui.toolbarFeedbackPanel.visible) {
            [ui.toolbarFeedbackPanel orderOut:nil];
        }
    }

    if (!recording && ui.recordingTimerPanel) {
        NSPanel *panel = ui.recordingTimerPanel;
        ui.recordingTimerPanel = nil;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = .12;
            panel.animator.alphaValue = 0;
        } completionHandler:^{
            [window removeChildWindow:panel];
            [panel orderOut:nil];
        }];
    }
    if (!recording) { return; }

    NSString *time = sc_window_ui_recording_time(elapsedSeconds);
    BOOL created = !ui.recordingTimerPanel;
    if (created) {
        ui.recordingTimerPanel = sc_window_ui_create_status_panel(time, YES);
        [window addChildWindow:ui.recordingTimerPanel ordered:NSWindowAbove];
    } else {
        SCStatusBubbleView *view =
            (SCStatusBubbleView *) ui.recordingTimerPanel.contentView;
        if (![view.label.stringValue isEqualToString:time]) {
            [view updateText:time];
            [ui.recordingTimerPanel setContentSize:view.frame.size];
        }
    }
    sc_window_ui_position_status_panel(ui.recordingTimerPanel, toolbar,
                                       recordAnchorY, outwardLeft);
    if (!visible) {
        [ui.recordingTimerPanel orderOut:nil];
    } else if (created || !ui.recordingTimerPanel.visible) {
        ui.recordingTimerPanel.alphaValue = 0;
        [ui.recordingTimerPanel orderFront:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = .12;
            ui.recordingTimerPanel.animator.alphaValue = 1;
        } completionHandler:nil];
    }
}

bool
sc_window_ui_should_reduce_motion(void) {
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

static NSMenu *
sc_window_ui_get_or_create_view_menu(SCScrcpyWindowUI *ui) {
    NSMenu *mainMenu = NSApp.mainMenu;
    if (!mainMenu) {
        return nil;
    }

    for (NSMenuItem *item in mainMenu.itemArray) {
        if (item.tag == 0x53435649) {
            ui.toolbarMenuContainer = item;
            return item.submenu;
        }
    }

    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View"
                                                     action:nil
                                              keyEquivalent:@""];
    viewItem.submenu = viewMenu;
    viewItem.tag = 0x53435649;
    SCBind(viewItem, @"title", @"View"); SCBind(viewMenu, @"title", @"View");

    NSInteger insertionIndex = mainMenu.numberOfItems;
    if (NSApp.windowsMenu) {
        for (NSInteger i = 0; i < mainMenu.numberOfItems; ++i) {
            if ([mainMenu itemAtIndex:i].submenu == NSApp.windowsMenu) {
                insertionIndex = i;
                break;
            }
        }
    }
    [mainMenu insertItem:viewItem atIndex:insertionIndex];
    ui.toolbarMenuContainer = viewItem;
    ui.ownsToolbarMenuContainer = YES;
    return viewMenu;
}

void
sc_window_ui_set_toolbar_menu_visible(struct sc_window_ui *window_ui,
                                      bool visible) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window) {
        return;
    }

    SCScrcpyWindowUI *ui = objc_getAssociatedObject(window, SC_WINDOW_UI_KEY);
    if (!ui.toolbarMenuItem) {
        return;
    }
    SCBind(ui.toolbarMenuItem, @"title", visible ? @"Hide Toolbar" : @"Show Toolbar");
}

void
sc_window_ui_configure_toolbar_menu(struct sc_window_ui *window_ui,
                                    bool visible,
                                    bool shortcut_enabled,
                                    sc_window_ui_toolbar_toggle_cb on_toggle,
                                    void *userdata) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window) {
        return;
    }

    SCScrcpyWindowUI *ui = sc_window_ui_get_controller(window);
    ui.toolbarToggleCallback = on_toggle;
    ui.toolbarToggleUserdata = userdata;

    if (!ui.toolbarMenuItem) {
        NSMenu *viewMenu = sc_window_ui_get_or_create_view_menu(ui);
        if (!viewMenu) {
            return;
        }
        ui.toolbarMenuItem = [[NSMenuItem alloc]
            initWithTitle:@""
                   action:@selector(toggleToolbar:)
            keyEquivalent:@""];
        ui.toolbarMenuItem.target = ui;
        [viewMenu addItem:ui.toolbarMenuItem];
    }
    if (shortcut_enabled) {
        ui.toolbarMenuItem.keyEquivalent = @"t";
        ui.toolbarMenuItem.keyEquivalentModifierMask =
            NSEventModifierFlagCommand | NSEventModifierFlagShift;
    } else {
        ui.toolbarMenuItem.keyEquivalent = @"";
    }
    sc_window_ui_set_toolbar_menu_visible(window_ui, visible);
}

bool
sc_window_ui_handle_event(struct sc_window_ui *window_ui,
                          const SDL_Event *event) {
    if (event->type == SDL_EVENT_WINDOW_SHOWN
            && event->window.windowID == SDL_GetWindowID(window_ui->window)) {
        sc_device_picker_mirror_shown();
    }
    if (event->type == SC_EVENT_THEME_CHANGED) {
        NSWindow *window = sc_window_ui_get_native_window(window_ui);
        SCScrcpyWindowUI *ui = objc_getAssociatedObject(window, SC_WINDOW_UI_KEY);
        sc_window_ui_apply_title_colors(ui);
        NSView *background = ui.toastPanel.contentView;
        background.layer.backgroundColor = [NSColor colorWithWhite:
            sc_theme_is_light() ? .98 : .08 alpha:.94].CGColor;
        [(SCStatusBubbleView *) ui.toolbarFeedbackPanel.contentView
            applyLightTheme:sc_theme_is_light()];
        [(SCStatusBubbleView *) ui.recordingTimerPanel.contentView
            applyLightTheme:sc_theme_is_light()];
    }
    // Native menu commands are dispatched by AppKit.
    return false;
}

void
sc_window_ui_destroy(struct sc_window_ui *window_ui) {
    NSWindow *window = sc_window_ui_get_native_window(window_ui);
    if (!window) {
        return;
    }
    SCScrcpyWindowUI *ui = objc_getAssociatedObject(window, SC_WINDOW_UI_KEY);
    if (ui.toastPanel) {
        [window removeChildWindow:ui.toastPanel];
        [ui.toastPanel orderOut:nil];
    }
    ++ui.toolbarFeedbackGeneration;
    if (ui.toolbarFeedbackPanel) {
        [window removeChildWindow:ui.toolbarFeedbackPanel];
        [ui.toolbarFeedbackPanel orderOut:nil];
        ui.toolbarFeedbackPanel = nil;
    }
    if (ui.recordingTimerPanel) {
        [window removeChildWindow:ui.recordingTimerPanel];
        [ui.recordingTimerPanel orderOut:nil];
        ui.recordingTimerPanel = nil;
    }
    ui.toolbarToggleCallback = NULL;
    ui.toolbarToggleUserdata = NULL;
    [ui.toolbarMenuItem.menu removeItem:ui.toolbarMenuItem];
    if (ui.ownsToolbarMenuContainer
            && ui.toolbarMenuContainer.submenu.numberOfItems == 0) {
        [NSApp.mainMenu removeItem:ui.toolbarMenuContainer];
    }
    [ui.titleStack removeFromSuperview];
    if (window.toolbar == ui.titleToolbar) {
        window.toolbar = nil;
    }
    objc_setAssociatedObject(window, SC_WINDOW_UI_KEY, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    window_ui->window = NULL;
    window_ui->data = NULL;
}
