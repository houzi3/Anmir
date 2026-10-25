#import <AppKit/AppKit.h>
#import "sys/macos/settings_window.h"
#import "sys/macos/device_ui.h"
#import "sys/macos/device_wifi.h"
#import "sys/macos/device_connection.h"
#import "sys/macos/localization.h"
#include <assert.h>

static NSView *find(NSView *view, NSString *identifier) {
    if ([view.identifier isEqualToString:identifier]) { return view; }
    for (NSView *child in view.subviews) { NSView *result = find(child, identifier); if (result) { return result; } }
    return nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        SCLocalizationInitialize([NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]], @"en");
        SCSettingsWindowController *settings = [[SCSettingsWindowController alloc]
            initWithTheme:@"system" language:@"system" toolbarVisible:YES];
        [settings.window.contentView layoutSubtreeIfNeeded];
        assert(!settings.window.contentView.hasAmbiguousLayout);
        NSPopUpButton *languages = (NSPopUpButton *)find(settings.window.contentView, @"Settings.language");
        NSSwitch *toolbar = (NSSwitch *)find(settings.window.contentView, @"Settings.toolbar");
        assert(languages.numberOfItems == 4);
        assert(toolbar.state == NSControlStateValueOn);
        // A Chinese title must not inherit the English option's extra width.
        // All segments keep the same padding around their icon and title.
        NSArray<NSButton *> *themes = @[(NSButton *)find(settings.window.contentView, @"Theme.system"),
            (NSButton *)find(settings.window.contentView, @"Theme.light"), (NSButton *)find(settings.window.contentView, @"Theme.dark")];
        CGFloat englishWidth = 0;
        NSDictionary *font = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]};
        for (NSString *language in @[@"en", @"zh-Hans", @"zh-Hant"]) {
            SCUseLanguage(language); [settings.window.contentView layoutSubtreeIfNeeded];
            CGFloat end = 0;
            for (NSButton *button in themes) {
                assert(button.frame.origin.x == end);
                CGFloat padding = (button.bounds.size.width - [button.title sizeWithAttributes:font].width - 22) / 2;
                assert(padding >= 12 && padding <= 14);
                end = NSMaxX(button.frame);
            }
            assert(fabs(end - themes.firstObject.superview.bounds.size.width) < .5);
            if ([language isEqualToString:@"en"]) { englishWidth = end; }
            else { assert(end < englishWidth); }
        }
        __block NSString *selectedTheme, *selectedLanguage;
        __block BOOL selectedToolbar = YES;
        settings.themeChanged = ^(NSString *value) { selectedTheme = value; };
        settings.languageChanged = ^(NSString *value) { selectedLanguage = value; SCUseLanguage(value); };
        settings.toolbarChanged = ^(BOOL value) { selectedToolbar = value; };
        NSButton *dark = (NSButton *)find(settings.window.contentView, @"Theme.dark");
        [dark performClick:nil]; assert([selectedTheme isEqualToString:@"dark"]);
        [languages selectItemAtIndex:2]; [NSApp sendAction:languages.action to:languages.target from:languages];
        assert([selectedLanguage isEqualToString:@"zh-Hant"]);
        assert([settings.window.title isEqualToString:@"Anmir 設定"]);
        assert([dark.title isEqualToString:@"深色"]);
        assert([languages.itemArray.firstObject.title isEqualToString:@"跟隨系統"]);
        toolbar.state = NSControlStateValueOff;
        [NSApp sendAction:toolbar.action to:toolbar.target from:toolbar]; assert(!selectedToolbar);
        [settings updateTheme:@"dark" language:@"zh-Hant" toolbarVisible:NO];
        assert(dark.state == NSControlStateValueOn && toolbar.state == NSControlStateValueOff);
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSApp.appearance = [NSAppearance appearanceNamed:appearance];
            [settings.window.contentView layoutSubtreeIfNeeded];
            assert(!settings.window.contentView.hasAmbiguousLayout);
            // English is the widest title. It must fit beside the control.
            SCUseLanguage(@"en");
            [settings.window.contentView layoutSubtreeIfNeeded];
            for (NSView *child in settings.window.contentView.subviews.firstObject.subviews) {
                if ([child isKindOfClass:NSTextField.class]) {
                    assert(child.fittingSize.width <= child.bounds.size.width + 1);
                }
            }
        }

        // The real pairing form must survive live language changes without
        // invoking build/cancel or replacing an in-progress field editor.
        SCDeviceWiFiController *wifi = [[SCDeviceWiFiController alloc] initWithExecutable:@"/usr/bin/false"
            mirror:^BOOL(NSString *serial, NSDictionary *properties) { (void)serial; (void)properties; return NO; }];
        NSButton *codeAction = [wifi valueForKey:@"modeButton"];
        [codeAction performClick:nil];
        SCDeviceInput *code = [wifi valueForKey:@"code"];
        code.stringValue = @"012345";
        [wifi.window makeFirstResponder:code.textField];
        code.textField.currentEditor.selectedRange = NSMakeRange(1, 3);
        SCDeviceConnection *connection = [wifi valueForKey:@"connection"];
        for (NSString *choice in @[@"zh-Hans", @"zh-Hant", @"en"]) {
            SCUseLanguage(choice);
            assert([wifi valueForKey:@"code"] == code);
            assert([code.stringValue isEqualToString:@"012345"]);
            assert(NSEqualRanges(code.textField.currentEditor.selectedRange, NSMakeRange(1, 3)));
            assert([wifi valueForKey:@"connection"] == connection);
            assert(connection.phase == SCDeviceConnectionIdle);
        }
        [wifi close]; [settings close];
        puts("Settings actions, live localization, layout and real pairing field preservation passed.");
    }
    return 0;
}
