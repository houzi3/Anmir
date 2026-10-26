#import <AppKit/AppKit.h>
#import "sys/macos/device_ui.h"
#include <assert.h>
#include <math.h>

@interface SCDeviceUIActionProbe : NSObject
@property(nonatomic) NSUInteger count;
- (void)activate:(id)sender;
@end
@implementation SCDeviceUIActionProbe
- (void)activate:(id)sender { (void)sender; ++_count; }
@end

static NSData *SCButtonSnapshot(NSView *view) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:view.bounds.size.width * 2 pixelsHigh:view.bounds.size.height * 2
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = view.bounds.size;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    }];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static void SCCheckToolbarStates(void) {
    NSString *output = NSProcessInfo.processInfo.environment[@"ANMIR_UI_SNAPSHOTS"];
    if (output.length) {
        assert([NSFileManager.defaultManager createDirectoryAtPath:output
            withIntermediateDirectories:YES attributes:nil error:nil]);
    }
    for (NSString *theme in @[@"light", @"dark"]) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 90, 28)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.appearance = [NSAppearance appearanceNamed:[theme isEqualToString:@"light"]
            ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
        SCDeviceSurface *surface = [[SCDeviceSurface alloc] initWithFrame:NSMakeRect(0, 0, 90, 28)];
        window.contentView = surface;
        NSEvent *entered = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
            context:nil eventNumber:0 trackingNumber:0 userData:NULL];
        NSEvent *exited = [NSEvent enterExitEventWithType:NSEventTypeMouseExited
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
            context:nil eventNumber:0 trackingNumber:0 userData:NULL];
        NSArray *images = @[SCDeviceSymbol(@"arrow.clockwise"), SCDeviceWiFiSymbol(),
            SCDeviceSymbol([theme isEqualToString:@"light"] ? @"moon" : @"sun.max")];
        NSMutableArray<SCDeviceIconButton *> *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < images.count; ++i) {
            SCDeviceIconButton *button = [SCDeviceIconButton buttonWithImage:images[i] target:nil action:nil];
            button.frame = NSMakeRect(i * 30, 0, 28, 28);
            [surface addSubview:button];
            [buttons addObject:button];
        }
        NSData *normal = SCButtonSnapshot(surface);
        if (output.length) { [normal writeToFile:[output stringByAppendingPathComponent:
            [theme stringByAppendingString:@"-default.png"]] atomically:YES]; }
        for (SCDeviceIconButton *button in buttons) { [button mouseEntered:entered]; }
        NSData *hover = SCButtonSnapshot(surface);
        assert(![normal isEqualToData:hover]);
        if (output.length) { [hover writeToFile:[output stringByAppendingPathComponent:
            [theme stringByAppendingString:@"-hover.png"]] atomically:YES]; }
        for (SCDeviceIconButton *button in buttons) { [button highlight:YES]; }
        NSData *pressed = SCButtonSnapshot(surface);
        assert(![hover isEqualToData:pressed]);
        if (output.length) { [pressed writeToFile:[output stringByAppendingPathComponent:
            [theme stringByAppendingString:@"-pressed.png"]] atomically:YES]; }
        for (SCDeviceIconButton *button in buttons) {
            [button highlight:NO];
            [button mouseExited:exited];
        }
        // Releasing and leaving a button must restore the exact original
        // rendering, with no sticky highlight or native focus outline.
        assert([normal isEqualToData:SCButtonSnapshot(surface)]);
        [buttons.firstObject mouseEntered:entered];
        buttons.firstObject.enabled = NO;
        NSData *disabled = SCButtonSnapshot(surface);
        if (output.length) { [disabled writeToFile:[output stringByAppendingPathComponent:
            [theme stringByAppendingString:@"-scanning.png"]] atomically:YES]; }
        [buttons.firstObject mouseExited:exited];
        buttons.firstObject.enabled = YES;
        assert([normal isEqualToData:SCButtonSnapshot(surface)]);
        [window close];
    }
}

static void SCCheckChoiceCardHitArea(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 260, 210)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSButton *card = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 228, 174)];
    card.cell = [[SCDeviceCardCell alloc] init];
    card.bordered = NO;
    [card setButtonType:NSButtonTypeRadio];
    card.title = @"Dark";
    SCDeviceUIActionProbe *probe = [[SCDeviceUIActionProbe alloc] init];
    card.target = probe;
    card.action = @selector(activate:);
    [window.contentView addSubview:card];
    // The old stock radio cell only tracked a small native indicator/title
    // region. Check the preview, caption, center and near all four corners.
    NSArray<NSValue *> *points = @[
        [NSValue valueWithPoint:NSMakePoint(114, 120)],
        [NSValue valueWithPoint:NSMakePoint(114, 20)],
        [NSValue valueWithPoint:NSMakePoint(114, 87)],
        [NSValue valueWithPoint:NSMakePoint(1, 1)],
        [NSValue valueWithPoint:NSMakePoint(227, 1)],
        [NSValue valueWithPoint:NSMakePoint(1, 173)],
        [NSValue valueWithPoint:NSMakePoint(227, 173)],
        [NSValue valueWithPoint:NSMakePoint(-1, 87)],
        [NSValue valueWithPoint:NSMakePoint(229, 87)],
    ];
    for (NSNumber *enabled in @[@YES, @NO]) {
        card.enabled = enabled.boolValue;
        for (NSValue *value in points) {
            NSPoint point = value.pointValue;
            NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                location:[card convertPoint:point toView:nil] modifierFlags:0 timestamp:0
                windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            NSCellHitResult hit = [card.cell hitTestForEvent:event inRect:card.bounds ofView:card];
            BOOL tracks = (hit & NSCellHitTrackableArea) != 0;
            assert(tracks == (card.enabled && NSPointInRect(point, card.bounds)));
            if (tracks) {
                card.state = NSControlStateValueOff;
                NSUInteger before = probe.count;
                NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                    location:event.locationInWindow modifierFlags:0 timestamp:1
                    windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
                // This queue belongs to the prohibited, offscreen test app;
                // no desktop or other application's events are synthesized.
                [NSApp postEvent:up atStart:YES];
                [card mouseDown:event];
                assert(probe.count == before + 1);
                assert(card.state == NSControlStateValueOn);
            }
        }
    }
    [window close];
}

static NSBitmapImageRep *SCIconBitmap(NSImage *image, NSInteger size) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = NSMakeSize(size, size);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    NSRect bounds = NSMakeRect(0, 0, size, size);
    NSRectFillUsingOperation(bounds, NSCompositingOperationClear);
    [image drawInRect:bounds];
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

static void SCCheckMirrorIcon(NSString *iconPath) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *bundleURL = [root URLByAppendingPathComponent:@"Icon test.app"];
    NSURL *contents = [bundleURL URLByAppendingPathComponent:@"Contents"];
    NSURL *resources = [contents URLByAppendingPathComponent:@"Resources"];
    assert([files createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil]);
    assert([files copyItemAtPath:iconPath toPath:
        [resources URLByAppendingPathComponent:@"anmir.icns"].path error:nil]);
    NSDictionary *info = @{@"CFBundlePackageType":@"APPL",
        @"CFBundleIdentifier":[@"org.scrcpy.icontest." stringByAppendingString:NSUUID.UUID.UUIDString],
        @"CFBundleIconFile":@"anmir.icns"};
    assert([info writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);
    NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
    assert(bundle);
    NSImage *normal = [NSWorkspace.sharedWorkspace iconForFile:bundleURL.path];
    NSImage *raw = [[NSImage alloc] initWithContentsOfFile:iconPath];
    assert(raw);
    NSImage *saved = NSApp.applicationIconImage;
    // Both startup representations must produce identical mirror artwork.
    NSApp.applicationIconImage = raw;
    NSImage *fromRaw = SCDeviceMirrorIcon(bundle);
    NSApp.applicationIconImage = normal;
    NSImage *fromNormal = SCDeviceMirrorIcon(bundle);
    NSApp.applicationIconImage = saved;
    for (NSNumber *value in @[@32, @44, @64, @128, @256, @512]) {
        NSInteger size = value.integerValue;
        NSBitmapImageRep *reference = SCIconBitmap(normal, size);
        NSBitmapImageRep *first = SCIconBitmap(fromRaw, size);
        NSBitmapImageRep *second = SCIconBitmap(fromNormal, size);
        assert([[first representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            isEqualToData:[second representationUsingType:NSBitmapImageFileTypePNG properties:@{}]]);
        // The middle row cannot intersect the lower-right phone badge.
        // Its silhouette must match the manager at every Dock/Retina size.
        for (NSInteger x = 0; x < size; ++x) {
            CGFloat expected = [reference colorAtX:x y:size / 2].alphaComponent;
            CGFloat actual = [first colorAtX:x y:size / 2].alphaComponent;
            assert(fabs(expected - actual) <= 1.0 / 255);
        }
        // System icon masks vary by macOS version. Preserve the host's actual
        // corners; downsampling may add a faint badge shadow at those pixels.
        for (NSValue *corner in @[
            [NSValue valueWithPoint:NSMakePoint(0, 0)],
            [NSValue valueWithPoint:NSMakePoint(size - 1, 0)],
            [NSValue valueWithPoint:NSMakePoint(0, size - 1)],
            [NSValue valueWithPoint:NSMakePoint(size - 1, size - 1)]]) {
            NSPoint pixel = corner.pointValue;
            CGFloat expected = [reference colorAtX:pixel.x y:pixel.y].alphaComponent;
            CGFloat actual = [first colorAtX:pixel.x y:pixel.y].alphaComponent;
            assert(fabs(expected - actual) < 0.1);
        }
        assert([first colorAtX:size / 2 y:size / 2].alphaComponent == 1);
    }
    assert([files removeItemAtURL:root error:nil]);
}

int main(int argc, const char *argv[]) {
    assert(argc == 2);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        // Keep the window offscreen and never order it onto the desktop.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 100)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        SCDeviceInput *input = [[SCDeviceInput alloc] initWithPlaceholder:@"6-digit code" identifier:@"Pairing code"];
        [input usePairingCodeStyle];
        [window.contentView addSubview:input];
        [NSLayoutConstraint activateConstraints:@[
            [input.widthAnchor constraintEqualToConstant:160],
            [input.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor],
            [input.centerYAnchor constraintEqualToAnchor:window.contentView.centerYAnchor],
        ]];
        [window.contentView layoutSubtreeIfNeeded];
        NSTextField *hint = nil;
        for (NSView *view in input.subviews) {
            if ([view isKindOfClass:NSTextField.class] && view != input.textField) {
                hint = (NSTextField *)view;
            }
        }
        assert(hint && !hint.hidden);
        assert(hint.font.pointSize == 13 && input.textField.font.pointSize == 17);
        assert(input.textField.placeholderString.length == 0);
        assert([input.textField.accessibilityPlaceholderValue isEqualToString:@"6-digit code"]);
        NSRect before = hint.frame;
        [window makeFirstResponder:input.textField];
        [window.contentView layoutSubtreeIfNeeded];
        assert(input.textField.currentEditor);
        assert(NSEqualRects(before, hint.frame) && hint.font.pointSize == 13 && !hint.hidden);

        NSFormatter *formatter = input.textField.formatter;
        for (NSString *valid in @[@"", @"0", @"012345"]) {
            assert([formatter isPartialStringValid:valid newEditingString:nil errorDescription:nil]);
        }
        for (NSString *invalid in @[@"0123456", @"12345a", @"１２３４５６", @"12 345"]) {
            assert(![formatter isPartialStringValid:invalid newEditingString:nil errorDescription:nil]);
        }
        input.stringValue = @"012345";
        assert([input.stringValue isEqualToString:@"012345"] && hint.hidden);
        input.stringValue = @"";
        assert(!hint.hidden);
        [window makeFirstResponder:nil];
        [window.contentView layoutSubtreeIfNeeded];
        assert(NSEqualRects(before, hint.frame) && hint.font.pointSize == 13);
        [window close];

        SCCheckMirrorIcon([NSString stringWithUTF8String:argv[1]]);
        SCCheckToolbarStates();
        SCCheckChoiceCardHitArea();
        puts("Native input, Dock icon, toolbar state and choice-card hit-area regressions passed.");
    }
    return 0;
}
