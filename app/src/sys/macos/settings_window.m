#import "settings_window.h"
#import "device_ui.h"
#import "localization.h"

static NSImage *SCSettingsTintedIcon(NSImage *source, NSColor *color) {
    return [NSImage imageWithSize:source.size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [source drawInRect:bounds];
        [color setFill]; NSRectFillUsingOperation(bounds, NSCompositingOperationSourceIn);
        return YES;
    }];
}

static NSColor *SCSettingsBase(BOOL group) {
    BOOL dark = [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    return dark ? [NSColor colorWithWhite:group ? .115 : .075 alpha:1]
        : group ? NSColor.whiteColor : [NSColor colorWithSRGBRed:.965 green:.969 blue:.978 alpha:1];
}

@interface SCSettingsSurface : NSView
@property(nonatomic) BOOL group;
@end
@implementation SCSettingsSurface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)rect {
    (void)rect;
    [SCSettingsBase(self.group) setFill];
    if (!self.group) { NSRectFill(self.bounds); return; }
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:11 yRadius:11];
    [outline fill];
    [[NSColor.labelColor colorWithAlphaComponent:.10] setStroke];
    outline.lineWidth = 1; [outline stroke];
    [[NSColor.labelColor colorWithAlphaComponent:.08] setFill];
    for (NSUInteger row = 1; row < 3; ++row) {
        NSRectFill(NSMakeRect(18, row * 52, self.bounds.size.width - 36, .5));
    }
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface SCSettingsIcon : NSView
@property(nonatomic, copy) NSString *symbol;
@end
@implementation SCSettingsIcon
- (void)drawRect:(NSRect)rect {
    (void)rect;
    [[NSColor.labelColor colorWithAlphaComponent:.045] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:7 yRadius:7] fill];
    NSImage *image = [SCDeviceSymbol(self.symbol) imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]];
    [SCSettingsTintedIcon(image, NSColor.secondaryLabelColor) drawInRect:NSInsetRect(self.bounds, 6, 6)];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

static NSImage *SCSettingsThemeSymbol(NSString *choice) {
    if (![choice isEqualToString:@"system"]) { return SCDeviceSymbol([choice isEqualToString:@"dark"] ? @"moon.fill" : @"sun.max"); }
    return [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:9 yBy:9]; [transform rotateByDegrees:45]; [transform concat];
        [SCDeviceSymbol(@"circle.lefthalf.filled") drawInRect:NSMakeRect(-8, -8, 16, 16)];
        [NSGraphicsContext restoreGraphicsState];
        (void)bounds; return YES;
    }];
}

@interface SCSettingsThemeButton : NSButton
@property(nonatomic, copy) NSString *choice;
@property(nonatomic) BOOL keyboardFocused;
@end
@implementation SCSettingsThemeButton
+ (Class)cellClass { return SCDeviceCardCell.class; }
- (void)drawRect:(NSRect)rect {
    (void)rect;
    if (self.state == NSControlStateValueOn || self.highlighted) {
        NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:7 yRadius:7];
        [[SCDeviceBlue() colorWithAlphaComponent:self.highlighted ? .15 : .07] setFill]; [shape fill];
        [SCDeviceBlue() setStroke]; shape.lineWidth = 1; [shape stroke];
    }
    NSDictionary *attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:NSColor.labelColor};
    NSSize size = [self.title sizeWithAttributes:attributes];
    CGFloat x = (self.bounds.size.width - size.width - 22) / 2;
    [SCSettingsTintedIcon(SCSettingsThemeSymbol(self.choice), NSColor.labelColor)
        drawInRect:NSMakeRect(x, NSMidY(self.bounds) - 8, 16, 16)];
    [self.title drawAtPoint:NSMakePoint(x + 22, NSMidY(self.bounds) - size.height / 2) withAttributes:attributes];
    if (self.keyboardFocused && self.window.keyWindow) {
        NSBezierPath *focus = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:5 yRadius:5];
        [NSColor.keyboardFocusIndicatorColor setStroke]; focus.lineWidth = 1; [focus stroke];
    }
}
- (BOOL)becomeFirstResponder {
    BOOL accepted = [super becomeFirstResponder];
    self.keyboardFocused = accepted && NSApp.currentEvent.type == NSEventTypeKeyDown;
    self.needsDisplay = YES; return accepted;
}
- (BOOL)resignFirstResponder { self.keyboardFocused = NO; self.needsDisplay = YES; return [super resignFirstResponder]; }
- (void)mouseDown:(NSEvent *)event { self.keyboardFocused = NO; [super mouseDown:event]; }
- (BOOL)accessibilityPerformPress {
    BOOL accepted = [super accessibilityPerformPress];
    self.keyboardFocused = NO; self.needsDisplay = YES; return accepted;
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode >= 123 && event.keyCode <= 126) {
        NSArray *buttons = self.superview.subviews;
        NSInteger index = [buttons indexOfObjectIdenticalTo:self];
        NSInteger next = (index + ((event.keyCode == 123 || event.keyCode == 126) ? 2 : 1)) % 3;
        SCSettingsThemeButton *button = buttons[next]; [button performClick:self]; [self.window makeFirstResponder:button];
        button.keyboardFocused = YES; button.needsDisplay = YES;
    } else { [super keyDown:event]; }
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface SCSettingsThemeStrip : NSView
@end
@implementation SCSettingsThemeStrip
- (void)drawRect:(NSRect)rect {
    (void)rect;
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:8 yRadius:8];
    [[NSColor.labelColor colorWithAlphaComponent:.025] setFill]; [outline fill];
    [[NSColor.labelColor colorWithAlphaComponent:.10] setStroke]; outline.lineWidth = 1; [outline stroke];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface SCSettingsWindowController ()
@property(nonatomic, strong) NSArray<SCSettingsThemeButton *> *themes;
@property(nonatomic, strong) NSPopUpButton *languages;
@property(nonatomic, strong) NSSwitch *toolbarSwitch;
@property(nonatomic, strong) NSLayoutConstraint *themeWidth;
@end
@implementation SCSettingsWindowController
- (instancetype)initWithTheme:(NSString *)theme language:(NSString *)language toolbarVisible:(BOOL)visible {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 188)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (!self) { return nil; }
    window.releasedWhenClosed = NO;
    window.titlebarAppearsTransparent = YES;
    SCBind(window, @"title", @"Anmir Settings");
    window.contentView = [[SCSettingsSurface alloc] initWithFrame:window.contentView.bounds];
    window.backgroundColor = SCSettingsBase(NO);
    SCSettingsSurface *group = [[SCSettingsSurface alloc] init]; group.group = YES;
    group.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:group];
    [NSLayoutConstraint activateConstraints:@[
        [group.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:16],
        [group.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-16],
        [group.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:16],
        [group.heightAnchor constraintEqualToConstant:156],
    ]];
    SCSettingsThemeStrip *strip = [[SCSettingsThemeStrip alloc] init];
    strip.accessibilityRole = NSAccessibilityRadioGroupRole;
    SCBind(strip, @"accessibilityLabel", @"Theme");
    NSMutableArray *themes = [NSMutableArray array];
    NSArray *choices = @[@"system", @"light", @"dark"];
    NSArray *titles = @[@"Follow System", @"Light", @"Dark"];
    for (NSUInteger index = 0; index < 3; ++index) {
        SCSettingsThemeButton *button = [[SCSettingsThemeButton alloc] initWithFrame:NSMakeRect(0, 0, 0, 32)];
        button.choice = choices[index]; button.identifier = [@"Theme." stringByAppendingString:choices[index]];
        [button setButtonType:NSButtonTypeRadio]; button.bordered = NO;
        button.focusRingType = NSFocusRingTypeNone;
        button.target = self; button.action = @selector(selectTheme:);
        SCBind(button, @"title", titles[index]); SCBind(button, @"accessibilityLabel", titles[index]);
        [strip addSubview:button]; [themes addObject:button];
    }
    self.themes = themes;
    self.languages = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.languages.identifier = @"Settings.language";
    [self.languages addItemsWithTitles:@[@"Follow System", @"简体中文", @"繁體中文", @"English"]];
    SCBind(self.languages.itemArray.firstObject, @"title", @"Follow System");
    self.languages.font = [NSFont systemFontOfSize:13];
    self.languages.target = self; self.languages.action = @selector(selectLanguage:);
    SCBind(self.languages, @"accessibilityLabel", @"Display language");
    self.toolbarSwitch = [[NSSwitch alloc] init];
    self.toolbarSwitch.identifier = @"Settings.toolbar";
    self.toolbarSwitch.target = self; self.toolbarSwitch.action = @selector(selectToolbar:);
    SCBind(self.toolbarSwitch, @"accessibilityLabel", @"Show floating toolbar");
    SCBind(self.toolbarSwitch, @"accessibilityHelp", @"Show Back, Home, Screenshot and Record beside the mirror window.");
    SCBind(self.toolbarSwitch, @"toolTip", @"Show Back, Home, Screenshot and Record beside the mirror window.");
    NSArray *controls = @[strip, self.languages, self.toolbarSwitch];
    NSArray *labels = @[@"Theme", @"Display language", @"Show floating toolbar"];
    NSArray *symbols = @[@"circle.lefthalf.filled", @"globe", @"sidebar.left"];
    for (NSUInteger row = 0; row < 3; ++row) {
        SCSettingsIcon *icon = [[SCSettingsIcon alloc] init]; icon.symbol = symbols[row];
        NSTextField *label = SCDeviceLocalizedLabel(labels[row], 13, NSFontWeightMedium, NO);
        NSView *control = controls[row];
        for (NSView *view in @[icon, label, control]) { view.translatesAutoresizingMaskIntoConstraints = NO; [group addSubview:view]; }
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:group.leadingAnchor constant:18],
            [icon.topAnchor constraintEqualToAnchor:group.topAnchor constant:row * 52 + 12],
            [icon.widthAnchor constraintEqualToConstant:28], [icon.heightAnchor constraintEqualToConstant:28],
            [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
            [label.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12],
            [control.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
            [control.trailingAnchor constraintEqualToAnchor:group.trailingAnchor constant:-18],
        ]];
    }
    self.themeWidth = [strip.widthAnchor constraintEqualToConstant:0];
    self.themeWidth.active = YES;
    [strip.heightAnchor constraintEqualToConstant:32].active = YES;
    [self.languages.widthAnchor constraintEqualToConstant:154].active = YES;
    [self updateTheme:theme language:language toolbarVisible:visible];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged:)
        name:SCLanguageChangedNotification object:nil];
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layoutThemeOptions {
    NSDictionary *attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]};
    CGFloat x = 0;
    for (SCSettingsThemeButton *button in self.themes) {
        // Equal padding around each icon + title, measured after localization.
        CGFloat width = MAX(72, ceil([button.title sizeWithAttributes:attributes].width) + 22 + 24);
        button.frame = NSMakeRect(x, 0, width, 32); x += width;
    }
    self.themeWidth.constant = x;
}
- (void)languageChanged:(NSNotification *)notification { (void)notification; [self layoutThemeOptions]; }
- (void)updateTheme:(NSString *)theme language:(NSString *)language toolbarVisible:(BOOL)visible {
    [self layoutThemeOptions];
    for (SCSettingsThemeButton *button in self.themes) {
        button.state = [button.choice isEqualToString:theme] ? NSControlStateValueOn : NSControlStateValueOff;
        button.needsDisplay = YES;
    }
    NSUInteger index = [@[@"system", @"zh-Hans", @"zh-Hant", @"en"] indexOfObject:language];
    [self.languages selectItemAtIndex:index == NSNotFound ? 0 : index];
    self.toolbarSwitch.state = visible ? NSControlStateValueOn : NSControlStateValueOff;
    self.window.backgroundColor = SCSettingsBase(NO);
}
- (void)selectTheme:(SCSettingsThemeButton *)button { if (self.themeChanged) { self.themeChanged(button.choice); } }
- (void)selectLanguage:(NSPopUpButton *)sender {
    if (self.languageChanged) { self.languageChanged(@[@"system", @"zh-Hans", @"zh-Hant", @"en"][sender.indexOfSelectedItem]); }
}
- (void)selectToolbar:(NSSwitch *)sender { if (self.toolbarChanged) { self.toolbarChanged(sender.state == NSControlStateValueOn); } }
@end
