#import "device_ui.h"
#import "localization.h"

NSColor *SCDeviceBackground(void) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:
            @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithSRGBRed:0.070 green:0.075 blue:0.082 alpha:1] : NSColor.whiteColor;
    }];
}

NSColor *SCDeviceBlue(void) {
    return [NSColor colorWithSRGBRed:0 green:0.40 blue:1 alpha:1];
}

NSTextField *SCDeviceLabel(NSString *text, CGFloat size, NSFontWeight weight, BOOL secondary) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

NSImage *SCDeviceSymbol(NSString *name) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
}

NSTextField *SCDeviceLocalizedLabel(NSString *key, CGFloat size, NSFontWeight weight, BOOL secondary) {
    NSTextField *label = SCDeviceLabel(@"", size, weight, secondary);
    SCBind(label, @"stringValue", key);
    return label;
}

NSImage *SCDeviceWiFiSymbol(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        (void)bounds;
        // Keep the two upper arcs of the native symbol. The centered plus is
        // the signal's origin, so it stays legible without a separate badge.
        [NSGraphicsContext saveGraphicsState];
        NSRectClip(NSMakeRect(0, 7, 16, 9));
        [SCDeviceSymbol(@"wifi") drawInRect:NSMakeRect(0, 3, 16, 12)];
        [NSGraphicsContext restoreGraphicsState];
        [NSColor.blackColor setStroke];
        NSBezierPath *plus = [NSBezierPath bezierPath];
        plus.lineWidth = 1.25;
        plus.lineCapStyle = NSLineCapStyleRound;
        [plus moveToPoint:NSMakePoint(8, 1)]; [plus lineToPoint:NSMakePoint(8, 5.5)];
        [plus moveToPoint:NSMakePoint(5.75, 3.25)]; [plus lineToPoint:NSMakePoint(10.25, 3.25)];
        [plus stroke];
        return YES;
    }];
    image.template = YES;
    SCBind(image, @"accessibilityDescription", @"Connect via Wi-Fi");
    return image;
}

NSImage *SCDeviceListSymbol(void) {
    NSImage *frame = SCDeviceSymbol(@"rectangle.portrait");
    NSImage *home = SCDeviceSymbol(@"minus");
    // Compose stock SF outlines at phone proportions. The iPhone glyph has a
    // shaded screen and the stock overlapping rectangles are too wide for the
    // approved design. A native short bar identifies the front phone.
    NSImage *image = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        (void)bounds;
        [frame drawInRect:NSMakeRect(1, 4, 10, 12)];
        NSRectFillUsingOperation(NSMakeRect(5, 0, 10, 12), NSCompositingOperationClear);
        [frame drawInRect:NSMakeRect(5, 0, 10, 12)];
        [home drawInRect:NSMakeRect(8, 1.6, 4.5, 2)];
        return YES;
    }];
    image.template = YES;
    SCBind(image, @"accessibilityDescription", @"Open device list");
    return image;
}

NSView *SCDeviceToolbarGroup(NSArray<NSButton *> *buttons) {
    CGFloat width = buttons.count ? buttons.count * 30 - 2 : 0;
    NSView *group = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 28)];
    for (NSUInteger i = 0; i < buttons.count; ++i) {
        NSButton *button = buttons[i];
        button.frame = NSMakeRect(i * 30, 0, 28, 28);
        if ([button isKindOfClass:SCDeviceIconButton.class]) {
            ((SCDeviceIconButton *)button).glyphSize = 16;
        }
        [group addSubview:button];
    }
    return group;
}

NSStackView *SCDeviceStack(NSArray<NSView *> *views, BOOL vertical, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

@implementation SCDeviceSurface
- (void)drawRect:(NSRect)dirtyRect {
    [SCDeviceBackground() setFill];
    NSRectFill(dirtyRect);
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
    for (NSView *view in self.subviews) {
        view.needsDisplay = YES;
    }
}
@end

@interface SCDeviceButtonCell : NSButtonCell
@end

@implementation SCDeviceButtonCell
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)view {
    SCDeviceButton *button = (SCDeviceButton *)view;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 0.5, 0.5) xRadius:6 yRadius:6];
    NSColor *color = button.primary && self.enabled ? SCDeviceBlue() : NSColor.controlBackgroundColor;
    if (self.highlighted) {
        color = [color blendedColorWithFraction:0.12 ofColor:NSColor.labelColor];
    }
    [color setFill];
    [path fill];
    [(button.primary && self.enabled ? SCDeviceBlue() : NSColor.separatorColor) setStroke];
    path.lineWidth = 1;
    [path stroke];
}
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)view {
    SCDeviceButton *button = (SCDeviceButton *)view;
    NSMutableAttributedString *text = [title mutableCopy];
    [text addAttribute:NSForegroundColorAttributeName value:
        !self.enabled ? NSColor.disabledControlTextColor : button.primary ? NSColor.whiteColor : NSColor.labelColor
        range:NSMakeRange(0, text.length)];
    return [super drawTitle:text withFrame:frame inView:view];
}
@end

@implementation SCDeviceButton
+ (Class)cellClass { return SCDeviceButtonCell.class; }
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    SCDeviceButton *button = [super buttonWithTitle:title target:target action:action];
    SCBind(button, @"title", title);
    return button;
}
- (void)setPrimary:(BOOL)primary { _primary = primary; self.needsDisplay = YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface SCDeviceIconCell : NSButtonCell
@end
@implementation SCDeviceIconCell
- (NSRect)imageRectForBounds:(NSRect)bounds {
    SCDeviceIconButton *button = (SCDeviceIconButton *)self.controlView;
    CGFloat size = button ? button.glyphSize : 14;
    return NSMakeRect(NSMidX(bounds) - size / 2, NSMidY(bounds) - size / 2, size, size);
}
@end

@interface SCDeviceIconButton ()
@property(nonatomic, strong) NSTrackingArea *tracking;
@property(nonatomic) BOOL hovering;
@property(nonatomic) BOOL keyboardFocused;
@end
@implementation SCDeviceIconButton
+ (Class)cellClass { return SCDeviceIconCell.class; }
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _glyphSize = 14;
        self.bordered = NO;
        self.imagePosition = NSImageOnly;
        self.contentTintColor = NSColor.labelColor;
        self.focusRingType = NSFocusRingTypeNone;
    }
    return self;
}
- (void)setGlyphSize:(CGFloat)glyphSize {
    _glyphSize = glyphSize > 0 ? glyphSize : 14;
    self.needsDisplay = YES;
}
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
- (void)clearToolbarKeyboardFocus {
    NSResponder *focused = self.window.firstResponder;
    if ([focused isKindOfClass:SCDeviceIconButton.class]) {
        SCDeviceIconButton *button = (SCDeviceIconButton *)focused;
        button.keyboardFocused = NO;
        button.needsDisplay = YES;
    }
    self.keyboardFocused = NO;
    self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)event {
    [self clearToolbarKeyboardFocus];
    [super mouseDown:event];
}
- (BOOL)accessibilityPerformPress {
    [self clearToolbarKeyboardFocus];
    return [super accessibilityPerformPress];
}
- (void)setImage:(NSImage *)image {
    if (!image) { [super setImage:nil]; return; }
    // SF Symbols carry different baseline padding. Normalize their visible
    // artwork once so scan, Wi-Fi and theme share an optical center.
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:64 pixelsHigh:64 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData, 0, bitmap.bytesPerRow * bitmap.pixelsHigh);
    CGFloat scale = 48 / MAX(image.size.width, image.size.height);
    NSSize size = NSMakeSize(image.size.width * scale, image.size.height * scale);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [image drawInRect:NSMakeRect((64-size.width)/2, (64-size.height)/2, size.width, size.height)];
    [NSGraphicsContext restoreGraphicsState];
    NSInteger left = 64, bottom = 64, right = -1, top = -1;
    for (NSInteger y = 0; y < 64; ++y) {
        for (NSInteger x = 0; x < 64; ++x) {
            if (bitmap.bitmapData[y * bitmap.bytesPerRow + x * 4 + 3] <= 8) { continue; }
            left = MIN(left, x); right = MAX(right, x);
            bottom = MIN(bottom, y); top = MAX(top, y);
        }
    }
    if (right < left || top < bottom) { [super setImage:image]; return; }
    CGImageRef cropped = CGImageCreateWithImageInRect(bitmap.CGImage,
        CGRectMake(left, bottom, right-left+1, top-bottom+1));
    NSImage *artwork = [[NSImage alloc] initWithCGImage:cropped size:NSZeroSize];
    CGImageRelease(cropped);
    NSImage *centered = [NSImage imageWithSize:NSMakeSize(14, 14) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        CGFloat ratio = MIN(bounds.size.width/artwork.size.width, bounds.size.height/artwork.size.height);
        NSSize fitted = NSMakeSize(artwork.size.width * ratio, artwork.size.height * ratio);
        [artwork drawInRect:NSMakeRect(NSMidX(bounds)-fitted.width/2, NSMidY(bounds)-fitted.height/2, fitted.width, fitted.height)];
        return YES;
    }];
    centered.template = YES;
    [super setImage:centered];
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
- (void)drawRect:(NSRect)dirtyRect {
    BOOL keyboardFocus = self.keyboardFocused && self.window.keyWindow;
    if (self.enabled && (self.hovering || self.cell.highlighted || keyboardFocus)) {
        NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:5 yRadius:5];
        [[NSColor.labelColor colorWithAlphaComponent:self.cell.highlighted ? 0.11 : keyboardFocus ? 0.08 : 0.055] setFill];
        [shape fill];
        if (keyboardFocus) {
            [[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.6] setStroke];
            shape.lineWidth = 1;
            [shape stroke];
        }
    }
    [super drawRect:dirtyRect];
}
@end

@implementation SCDeviceCardCell
- (NSCellHitResult)hitTestForEvent:(NSEvent *)event inRect:(NSRect)frame ofView:(NSView *)view {
    NSPoint point = [view convertPoint:event.locationInWindow fromView:nil];
    return self.enabled && NSPointInRect(point, frame)
        ? NSCellHitContentArea | NSCellHitTrackableArea : NSCellHitNone;
}
@end

@implementation SCDeviceStepBadge
- (instancetype)initWithNumber:(NSUInteger)number {
    self = [super initWithFrame:NSMakeRect(0, 0, 36, 36)];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        NSTextField *label = SCDeviceLabel([NSString stringWithFormat:@"%lu", (unsigned long)number],
            15, NSFontWeightSemibold, NO);
        label.textColor = SCDeviceBlue();
        label.alignment = NSTextAlignmentCenter;
        [self addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:36],
            [self.heightAnchor constraintEqualToConstant:36],
            [label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityStaticTextRole;
        SCBindFormat(self, @"accessibilityLabel", @"Step %@", @[label.stringValue]);
    }
    return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[SCDeviceBlue() colorWithAlphaComponent:0.12] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface SCDeviceTextField : NSTextField
@end
@implementation SCDeviceTextField
- (BOOL)becomeFirstResponder {
    BOOL focused = [super becomeFirstResponder];
    self.superview.needsDisplay = YES;
    return focused;
}
- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    self.superview.needsDisplay = YES;
}
@end

@interface SCDeviceInput ()
@property(nonatomic, strong, readwrite) NSTextField *textField;
@property(nonatomic, strong) NSTextField *placeholderLabel;
@property(nonatomic, strong) NSLayoutConstraint *height;
@end

@interface SCDeviceCodeFormatter : NSFormatter
@end
@implementation SCDeviceCodeFormatter
- (NSString *)stringForObjectValue:(id)object { return [object isKindOfClass:NSString.class] ? object : @""; }
- (BOOL)getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString **)error {
    (void)error;
    if (object) { *object = string; }
    return YES;
}
- (BOOL)isPartialStringValid:(NSString *)string newEditingString:(NSString **)replacement errorDescription:(NSString **)error {
    (void)replacement;
    BOOL valid = string.length <= 6 && [string rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound;
    if (!valid && error) { *error = SCLocalized(@"Use six digits (0–9)."); }
    return valid;
}
@end

@implementation SCDeviceInput
- (instancetype)initWithPlaceholder:(NSString *)placeholder identifier:(NSString *)identifier {
    self = [super initWithFrame:NSMakeRect(0, 0, 200, 34)];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.textField = [[SCDeviceTextField alloc] init];
        self.textField.translatesAutoresizingMaskIntoConstraints = NO;
        self.textField.bordered = NO;
        self.textField.bezeled = NO;
        self.textField.drawsBackground = NO;
        self.textField.focusRingType = NSFocusRingTypeNone;
        self.textField.font = [NSFont systemFontOfSize:13];
        self.textField.textColor = NSColor.labelColor;
        // AppKit's field editor does not always preserve an attributed
        // placeholder's font/baseline. Draw the hint in a fixed label so
        // entering and leaving editing changes only the focus outline.
        SCBind(self.textField, @"accessibilityPlaceholderValue", placeholder);
        self.placeholderLabel = SCDeviceLocalizedLabel(placeholder, 13, NSFontWeightRegular, YES);
        self.placeholderLabel.textColor = NSColor.placeholderTextColor;
        self.placeholderLabel.accessibilityElement = NO;
        self.textField.identifier = identifier;
        SCBind(self.textField, @"accessibilityLabel", identifier);
        self.textField.usesSingleLineMode = YES;
        self.textField.cell.scrollable = YES;
        [self addSubview:self.placeholderLabel];
        [self addSubview:self.textField];
        self.height = [self.heightAnchor constraintEqualToConstant:34];
        [NSLayoutConstraint activateConstraints:@[
            self.height,
            [self.textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [self.textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.textField.leadingAnchor],
            [self.placeholderLabel.trailingAnchor constraintEqualToAnchor:self.textField.trailingAnchor],
            [self.placeholderLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        for (NSNotificationName name in @[NSControlTextDidBeginEditingNotification,
                NSControlTextDidChangeNotification, NSControlTextDidEndEditingNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(editingChanged:) name:name object:self.textField];
        }
    }
    return self;
}
- (void)usePairingCodeStyle {
    self.height.constant = 40;
    self.textField.font = [NSFont monospacedDigitSystemFontOfSize:17 weight:NSFontWeightMedium];
    self.textField.alignment = NSTextAlignmentCenter;
    self.placeholderLabel.alignment = NSTextAlignmentCenter;
    SCBind(self.placeholderLabel, @"stringValue", @"6-digit code");
    SCBind(self.textField, @"accessibilityPlaceholderValue", @"6-digit code");
    self.textField.formatter = [[SCDeviceCodeFormatter alloc] init];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (NSString *)stringValue { return self.textField.stringValue; }
- (void)setStringValue:(NSString *)value {
    self.textField.stringValue = value ?: @"";
    self.placeholderLabel.hidden = self.textField.stringValue.length > 0;
}
- (BOOL)enabled { return self.textField.enabled; }
- (void)setEnabled:(BOOL)enabled {
    self.textField.enabled = enabled;
    self.placeholderLabel.alphaValue = enabled ? 1 : .5;
    self.needsDisplay = YES;
}
- (void)editingChanged:(NSNotification *)notification {
    (void)notification;
    self.placeholderLabel.hidden = self.textField.stringValue.length > 0;
    self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)event { (void)event; if (self.enabled) { [self.window makeFirstResponder:self.textField]; } }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    BOOL focused = self.textField.currentEditor && self.window.firstResponder == self.textField.currentEditor;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:6 yRadius:6];
    [NSColor.controlBackgroundColor setFill]; [path fill];
    [(focused ? [SCDeviceBlue() colorWithAlphaComponent:0.8]
        : [NSColor.labelColor colorWithAlphaComponent:0.16]) setStroke];
    path.lineWidth = focused ? 2 : 1;
    [path stroke];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

NSImage *SCDeviceMirrorIcon(NSBundle *bundle) {
    // applicationIconImage may be raw ICNS artwork or an already-normalized
    // Dock image, depending on how the process was opened. Mixing those inputs
    // enlarges some mirrors. Ask the system for one consistent bundle icon.
    NSImage *base = [NSWorkspace.sharedWorkspace iconForFile:bundle.bundlePath];
    NSImage *badged = [NSImage imageWithSize:NSMakeSize(256, 256) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        // Preserve the system's transparent margins and rounded silhouette.
        // The phone badge uses that same canvas; it never rescales the base.
        [base drawInRect:bounds];
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.2];
        shadow.shadowBlurRadius = 5;
        shadow.shadowOffset = NSMakeSize(0, -1);
        [shadow set];
        NSBezierPath *badge = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(176, 4, 76, 76) xRadius:18 yRadius:18];
        [NSColor.whiteColor setFill]; [badge fill];
        [NSGraphicsContext restoreGraphicsState];
        [[NSColor.blackColor colorWithAlphaComponent:0.12] setStroke];
        badge.lineWidth = 1; [badge stroke];
        NSBezierPath *phone = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(201, 18, 26, 48) xRadius:5 yRadius:5];
        [[NSColor colorWithSRGBRed:0.07 green:0.09 blue:0.12 alpha:1] setStroke];
        phone.lineWidth = 3; [phone stroke];
        NSBezierPath *details = [NSBezierPath bezierPath];
        details.lineWidth = 2; details.lineCapStyle = NSLineCapStyleRound;
        [details moveToPoint:NSMakePoint(210, 61)]; [details lineToPoint:NSMakePoint(218, 61)];
        [details moveToPoint:NSMakePoint(210, 23)]; [details lineToPoint:NSMakePoint(218, 23)];
        [details stroke];
        return YES;
    }];
    SCBind(badged, @"accessibilityDescription", @"Device mirroring");
    return badged;
}
