#import "theme_chooser.h"
#import "device_ui.h"
#import "localization.h"

static NSImage *SCThemeTintedIcon(NSImage *source, NSColor *color) {
    return [NSImage imageWithSize:source.size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [source drawInRect:bounds];
        [color setFill];
        NSRectFillUsingOperation(bounds, NSCompositingOperationSourceIn);
        return YES;
    }];
}

@interface SCThemeRow : NSButton
@property(nonatomic) BOOL dark;
@property(nonatomic) BOOL followsSystem;
@property(nonatomic, copy) NSString *choice;
@property(nonatomic, strong) NSButtonCell *indicator;
@property(nonatomic, strong) NSTrackingArea *tracking;
@property(nonatomic) BOOL hovering;
@property(nonatomic) BOOL keyboardFocused;
@end

@implementation SCThemeRow
+ (Class)cellClass { return SCDeviceCardCell.class; }
- (BOOL)isFlipped { return NO; }
- (NSEdgeInsets)alignmentRectInsets {
    // This row paints its entire bounds, independently of native radio bezels.
    return NSEdgeInsetsMake(0, 0, 0, 0);
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.focusRingType = NSFocusRingTypeNone;
        [self setButtonType:NSButtonTypeRadio];
        self.accessibilityRole = NSAccessibilityRadioButtonRole;
        _indicator = [[NSButtonCell alloc] initTextCell:@""];
        [_indicator setButtonType:NSButtonTypeRadio];
        _indicator.controlSize = NSControlSizeSmall;
        _indicator.bordered = NO;
    }
    return self;
}
- (void)drawSymbol:(NSRect)rect {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMidX(rect) yBy:NSMidY(rect)];
    [transform concat];
    CGFloat half = rect.size.width / 2;
    NSRect glyph = NSMakeRect(-half, -half, rect.size.width, rect.size.height);
    if (self.followsSystem) {
        NSImage *disc = SCDeviceSymbol(@"circle.fill");
        [SCThemeTintedIcon(disc, NSColor.whiteColor) drawInRect:glyph];
        [NSGraphicsContext saveGraphicsState];
        // Keep the native circle upright so its rim stays crisp at 18pt.
        // AppKit's upward y axis makes this lower/right half a visual '/'.
        NSBezierPath *darkHalf = [NSBezierPath bezierPath];
        [darkHalf moveToPoint:NSMakePoint(-half, -half)];
        [darkHalf lineToPoint:NSMakePoint(half, -half)];
        [darkHalf lineToPoint:NSMakePoint(half, half)];
        [darkHalf closePath];
        [darkHalf addClip];
        [SCThemeTintedIcon(disc, [NSColor colorWithWhite:0.16 alpha:1]) drawInRect:glyph];
        [NSGraphicsContext restoreGraphicsState];
        NSImage *rim = [SCDeviceSymbol(@"circle") imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightLight]];
        [SCThemeTintedIcon(rim, [NSColor.labelColor colorWithAlphaComponent:0.25]) drawInRect:glyph];
    } else {
        NSImage *symbol = [SCDeviceSymbol(self.dark ? @"moon" : @"sun.max")
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration
                configurationWithPointSize:18 weight:NSFontWeightRegular]];
        CGFloat scale = rect.size.width / MAX(symbol.size.width, symbol.size.height);
        NSSize size = NSMakeSize(symbol.size.width * scale, symbol.size.height * scale);
        [SCThemeTintedIcon(symbol, NSColor.labelColor) drawInRect:
            NSMakeRect(-size.width/2, -size.height/2, size.width, size.height)];
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    BOOL selected = self.state == NSControlStateValueOn;
    if (selected || self.hovering || self.cell.highlighted) {
        NSColor *color = selected ? SCDeviceBlue() : NSColor.labelColor;
        CGFloat alpha = selected ? 0.10 : 0.035;
        if (self.cell.highlighted) { alpha += 0.045; }
        [NSGraphicsContext saveGraphicsState];
        NSRect group = [self convertRect:NSInsetRect(self.superview.bounds, 1, 1)
            fromView:self.superview];
        [[NSBezierPath bezierPathWithRoundedRect:group xRadius:7 yRadius:7] addClip];
        [[color colorWithAlphaComponent:alpha] setFill];
        NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
        [NSGraphicsContext restoreGraphicsState];
    }
    [self drawSymbol:NSMakeRect(18, NSMidY(self.bounds) - 9, 18, 18)];
    NSDictionary *attributes = @{
        NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:NSColor.labelColor,
    };
    NSSize textSize = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(56, NSMidY(self.bounds) - textSize.height/2)
        withAttributes:attributes];
    self.indicator.state = self.state;
    self.indicator.enabled = self.enabled;
    self.indicator.highlighted = self.cell.highlighted;
    [self.indicator drawWithFrame:NSMakeRect(self.bounds.size.width - 30,
        NSMidY(self.bounds) - 8, 16, 16) inView:self];
    if (self.keyboardFocused && self.window.keyWindow) {
        NSBezierPath *focus = [NSBezierPath bezierPathWithRoundedRect:
            NSInsetRect(self.bounds, 3, 3) xRadius:4 yRadius:4];
        [[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.7] setStroke];
        focus.lineWidth = 1;
        [focus stroke];
    }
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.tracking) { [self removeTrackingArea:self.tracking]; }
    self.tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.tracking];
}
- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovering = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { (void)event; self.hovering = NO; self.needsDisplay = YES; }
- (BOOL)becomeFirstResponder {
    BOOL accepted = [super becomeFirstResponder];
    self.keyboardFocused = accepted && NSApp.currentEvent.type == NSEventTypeKeyDown;
    self.needsDisplay = YES;
    return accepted;
}
- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if (resigned) { self.keyboardFocused = NO; }
    self.needsDisplay = YES;
    return resigned;
}
- (void)mouseDown:(NSEvent *)event {
    self.keyboardFocused = NO;
    [super mouseDown:event];
}
- (BOOL)accessibilityPerformPress {
    BOOL accepted = [super accessibilityPerformPress];
    self.keyboardFocused = NO;
    self.needsDisplay = YES;
    return accepted;
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode >= 123 && event.keyCode <= 126) {
        NSArray<SCThemeRow *> *rows = self.superview.subviews;
        NSInteger index = [rows indexOfObjectIdenticalTo:self];
        NSInteger direction = event.keyCode == 123 || event.keyCode == 126 ? -1 : 1;
        NSInteger nextIndex = (index + direction + rows.count) % rows.count;
        SCThemeRow *next = rows[nextIndex];
        [next performClick:self];
        [self.window makeFirstResponder:next];
        next.keyboardFocused = YES;
        next.needsDisplay = YES;
    } else {
        [super keyDown:event];
    }
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

@interface SCThemeOptions : NSView
@end
@implementation SCThemeOptions
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityRole = NSAccessibilityRadioGroupRole;
        SCBind(self, @"accessibilityLabel", @"Appearance");
    }
    return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:
        NSInsetRect(self.bounds, 0.5, 0.5) xRadius:8 yRadius:8];
    [[NSColor.labelColor colorWithAlphaComponent:0.025] setFill];
    [outline fill];
    [[NSColor.labelColor colorWithAlphaComponent:0.13] setStroke];
    outline.lineWidth = 1;
    [outline stroke];
    [[NSColor.labelColor colorWithAlphaComponent:0.10] setFill];
    for (NSUInteger i = 1; i < 3; ++i) {
        NSRectFillUsingOperation(NSMakeRect(16, i * 36 - 0.5,
            self.bounds.size.width - 32, 0.5), NSCompositingOperationSourceOver);
    }
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
    for (NSView *view in self.subviews) { view.needsDisplay = YES; }
}
@end

@interface SCThemeContinueButton : SCDeviceButton
@end
@implementation SCThemeContinueButton
// Keep the chooser's primary action reachable with Tab even when macOS is
// configured to skip ordinary buttons during keyboard navigation.
- (BOOL)acceptsFirstResponder { return YES; }
@end

@interface SCThemeWindow : NSWindow
@property(nonatomic, weak) NSButton *primaryButton;
@property(nonatomic, weak) NSPopUpButton *languageControl;
@end
@implementation SCThemeWindow
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown && event.keyCode == 48 &&
        !(event.modifierFlags & (NSEventModifierFlagCommand |
            NSEventModifierFlagControl | NSEventModifierFlagOption))) {
        // The radio group is one tab stop; arrows choose its active row.
        NSArray *stops = @[self.languageControl, self.initialFirstResponder, self.primaryButton];
        NSUInteger index = [stops indexOfObjectIdenticalTo:self.firstResponder];
        NSInteger step = event.modifierFlags & NSEventModifierFlagShift ? 2 : 1;
        NSResponder *next = stops[((index == NSNotFound ? 0 : index) + step) % 3];
        if (next && [self makeFirstResponder:next]) { return; }
    }
    [super sendEvent:event];
}
@end

@interface SCThemeChooser () <NSWindowDelegate>
@property(nonatomic, copy, readwrite) NSString *selection;
@property(nonatomic, copy, readwrite) NSString *languageSelection;
@property(nonatomic, strong) NSArray<SCThemeRow *> *rows;
@property(nonatomic) BOOL accepted;
@end

@implementation SCThemeChooser
- (instancetype)init { return [self initWithLanguage:@"system"]; }
- (instancetype)initWithLanguage:(NSString *)language {
    SCThemeWindow *window = [[SCThemeWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 228)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    // Native titlebar heights vary by macOS version; keep the outer footprint.
    [window setFrame:NSMakeRect(0, 0, 400, 326) display:NO];
    self = [super initWithWindow:window];
    if (self) {
        _selection = @"system";
        _languageSelection = language;
        window.title = @"Anmir";
        window.releasedWhenClosed = NO;
        window.delegate = self;
        window.backgroundColor = SCDeviceBackground();
        window.titlebarAppearsTransparent = YES;
        window.contentView = [[SCDeviceSurface alloc] initWithFrame:window.contentView.bounds];
        NSView *view = window.contentView;
        NSTextField *heading = SCDeviceLocalizedLabel(@"Choose a theme", 15, NSFontWeightSemibold, NO);
        NSTextField *subtitle = SCDeviceLocalizedLabel(@"Change anytime.", 11, NSFontWeightRegular, YES);
        SCThemeOptions *options = [[SCThemeOptions alloc] init];
        options.translatesAutoresizingMaskIntoConstraints = NO;
        NSMutableArray *rows = [NSMutableArray array];
        NSArray *choices = @[@"system", @"light", @"dark"];
        for (NSUInteger i = 0; i < choices.count; ++i) {
            SCThemeRow *row = [[SCThemeRow alloc] init];
            row.choice = choices[i];
            row.followsSystem = i == 0;
            row.dark = i == 2;
            NSString *title = @[@"Follow System", @"Light", @"Dark"][i];
            SCBind(row, @"title", title);
            SCBind(row, @"accessibilityLabel", title);
            row.identifier = [@"Theme." stringByAppendingString:row.choice];
            row.state = i ? NSControlStateValueOff : NSControlStateValueOn;
            row.target = self;
            row.action = @selector(select:);
            row.translatesAutoresizingMaskIntoConstraints = NO;
            SCBind(row, @"toolTip", row.followsSystem ? @"Match macOS appearance" : title);
            [options addSubview:row];
            [NSLayoutConstraint activateConstraints:@[
                [row.leadingAnchor constraintEqualToAnchor:options.leadingAnchor],
                [row.trailingAnchor constraintEqualToAnchor:options.trailingAnchor],
                [row.topAnchor constraintEqualToAnchor:options.topAnchor constant:i * 36],
                [row.heightAnchor constraintEqualToConstant:36],
            ]];
            [rows addObject:row];
        }
        self.rows = rows;
        window.initialFirstResponder = rows.firstObject;
        SCDeviceButton *next = [SCThemeContinueButton buttonWithTitle:@"Continue" target:self action:@selector(accept:)];
        next.bezelStyle = NSBezelStyleRounded;
        next.primary = YES;
        next.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        next.keyEquivalent = @"\r";
        next.translatesAutoresizingMaskIntoConstraints = NO;
        window.primaryButton = next;
        NSTextField *languageTitle = SCDeviceLocalizedLabel(@"Display language", 12, NSFontWeightMedium, NO);
        NSPopUpButton *languages = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        languages.identifier = @"Onboarding.language";
        [languages addItemsWithTitles:@[@"Follow System", @"简体中文", @"繁體中文", @"English"]];
        SCBind(languages.itemArray.firstObject, @"title", @"Follow System");
        SCBind(languages, @"accessibilityLabel", @"Display language");
        NSUInteger languageIndex = [@[@"system", @"zh-Hans", @"zh-Hant", @"en"] indexOfObject:language];
        [languages selectItemAtIndex:languageIndex == NSNotFound ? 0 : languageIndex];
        languages.target = self; languages.action = @selector(selectLanguage:);
        languages.translatesAutoresizingMaskIntoConstraints = NO;
        window.languageControl = languages;
        for (NSView *item in @[languageTitle, languages, heading, subtitle, options, next]) { [view addSubview:item]; }
        [NSLayoutConstraint activateConstraints:@[
            [heading.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
            [heading.topAnchor constraintEqualToAnchor:view.topAnchor constant:78],
            [languageTitle.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
            [languages.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
            [languages.topAnchor constraintEqualToAnchor:view.topAnchor constant:18],
            [languages.widthAnchor constraintEqualToConstant:190],
            [languageTitle.centerYAnchor constraintEqualToAnchor:languages.centerYAnchor],
            [subtitle.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:4],
            [options.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
            [options.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
            [options.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14],
            [options.heightAnchor constraintEqualToConstant:108],
            [next.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
            [next.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-16],
            [next.widthAnchor constraintEqualToConstant:80], [next.heightAnchor constraintEqualToConstant:26],
        ]];
    }
    return self;
}
- (void)select:(SCThemeRow *)sender {
    self.selection = sender.choice;
    self.window.initialFirstResponder = sender;
    [self.window makeFirstResponder:sender];
    for (SCThemeRow *row in self.rows) {
        row.state = row == sender ? NSControlStateValueOn : NSControlStateValueOff;
        row.needsDisplay = YES;
    }
    if (self.change) { self.change(self.selection); }
}
- (void)selectLanguage:(NSPopUpButton *)sender {
    self.languageSelection = @[@"system", @"zh-Hans", @"zh-Hant", @"en"][sender.indexOfSelectedItem];
    if (self.languageChanged) { self.languageChanged(self.languageSelection); }
}
- (void)accept:(id)sender { (void)sender; self.accepted = YES; [NSApp stopModalWithCode:NSModalResponseOK]; }
- (void)windowWillClose:(NSNotification *)notification { (void)notification; if (!self.accepted) { [NSApp abortModal]; } }
@end
