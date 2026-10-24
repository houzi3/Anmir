#import <AppKit/AppKit.h>
#import "sys/macos/theme_chooser.h"
#include <assert.h>

static NSButton *findButton(NSView *view, NSString *title) {
    if ([view isKindOfClass:NSButton.class] &&
            [((NSButton *)view).title isEqualToString:title]) {
        return (NSButton *)view;
    }
    for (NSView *child in view.subviews) {
        NSButton *button = findButton(child, title);
        if (button) { return button; }
    }
    return nil;
}

static NSEvent *key(NSWindow *window, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil
        characters:code == 48 ? @"\t" : @"\uf701" charactersIgnoringModifiers:@""
        isARepeat:NO keyCode:code];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        SCThemeChooser *chooser = [[SCThemeChooser alloc] init];
        NSWindow *window = chooser.window;
        [window.contentView layoutSubtreeIfNeeded];
        assert(window.contentView.bounds.size.width == 400);
        assert(window.frame.size.height == 260);
        assert(!window.contentView.hasAmbiguousLayout);
        NSArray<NSButton *> *rows = @[
            findButton(window.contentView, @"System"),
            findButton(window.contentView, @"Light"),
            findButton(window.contentView, @"Dark")];
        __block NSUInteger changes = 0;
        chooser.change = ^(NSString *choice) { (void)choice; ++changes; };
        for (NSUInteger i = 0; i < rows.count; ++i) {
            NSButton *row = rows[i];
            assert(NSEqualSizes(row.bounds.size, NSMakeSize(360, 36)));
            assert([row.accessibilityRole isEqualToString:NSAccessibilityRadioButtonRole]);
            for (NSValue *value in @[
                [NSValue valueWithPoint:NSMakePoint(2, 2)],
                [NSValue valueWithPoint:NSMakePoint(18, 18)],
                [NSValue valueWithPoint:NSMakePoint(80, 18)],
                [NSValue valueWithPoint:NSMakePoint(180, 18)],
                [NSValue valueWithPoint:NSMakePoint(338, 18)],
                [NSValue valueWithPoint:NSMakePoint(358, 34)]]) {
                NSPoint point = [row convertPoint:value.pointValue toView:nil];
                NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                    location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
                    context:nil eventNumber:0 clickCount:1 pressure:1];
                NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                    location:point modifierFlags:0 timestamp:1 windowNumber:window.windowNumber
                    context:nil eventNumber:1 clickCount:1 pressure:0];
                NSUInteger before = changes;
                [NSApp postEvent:up atStart:YES];
                [row mouseDown:down];
                assert(changes == before + 1);
                assert([chooser.selection isEqualToString:row.title.lowercaseString]);
                for (NSUInteger j = 0; j < rows.count; ++j) {
                    assert(rows[j].state == (i == j ? NSControlStateValueOn : NSControlStateValueOff));
                }
            }
        }
        for (NSUInteger i = 0; i < 6; ++i) {
            [(NSButton *)window.firstResponder keyDown:key(window, 125, 0)];
            assert([chooser.selection isEqualToString:rows[i % 3].title.lowercaseString]);
        }
        NSResponder *selected = window.firstResponder;
        [window sendEvent:key(window, 48, 0)];
        assert(window.firstResponder == findButton(window.contentView, @"Continue"));
        [window sendEvent:key(window, 48, NSEventModifierFlagShift)];
        assert(window.firstResponder == selected);
        NSRect before = rows[0].frame;
        for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            window.appearance = [NSAppearance appearanceNamed:name];
            [window.contentView layoutSubtreeIfNeeded];
            assert(NSEqualRects(before, rows[0].frame));
        }
        [window close];
        puts("Theme chooser mouse, keyboard, selection and geometry tests passed.");
    }
    return 0;
}
