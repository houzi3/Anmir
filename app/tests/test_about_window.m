#import <AppKit/AppKit.h>
#import "sys/macos/about_window.h"
#import "sys/macos/localization.h"
#import <objc/runtime.h>
#include <assert.h>

static NSURL *opened;
static BOOL captureURL(id workspace, SEL selector, NSURL *url) { (void)workspace; (void)selector; opened = url; return YES; }
static NSView *find(NSView *view, NSString *identifier) {
    if ([view.identifier isEqual:identifier]) { return view; }
    for (NSView *child in view.subviews) { NSView *result = find(child, identifier); if (result) { return result; } }
    return nil;
}
static NSBundle *bundle(NSURL *root, NSString *build, NSString *icon) {
    NSURL *app = [root URLByAppendingPathComponent:[build stringByAppendingPathExtension:@"app"]];
    NSURL *contents = [app URLByAppendingPathComponent:@"Contents"];
    NSURL *resources = [contents URLByAppendingPathComponent:@"Resources"];
    NSFileManager *files = NSFileManager.defaultManager;
    assert(([files createDirectoryAtURL:[resources URLByAppendingPathComponent:@"licenses"] withIntermediateDirectories:YES attributes:nil error:nil]));
    NSDictionary *info = @{@"CFBundlePackageType":@"APPL", @"CFBundleIdentifier":[@"org.anmir.about." stringByAppendingString:build],
        @"CFBundleShortVersionString":@"0.0.9", @"CFBundleVersion":build, @"CFBundleIconFile":@"anmir.icns"};
    assert(([info writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] atomically:YES]));
    assert(([files copyItemAtPath:icon toPath:[resources URLByAppendingPathComponent:@"anmir.icns"].path error:nil]));
    for (NSString *path in @[@"LICENSE", @"NOTICE", @"THIRD_PARTY.md", @"licenses/dependency.txt"]) {
        assert(([[@"Unmodified license fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[resources URLByAppendingPathComponent:path] atomically:YES]));
    }
    return [NSBundle bundleWithURL:app];
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    assert((argc == 3));
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    SCLocalizationInitialize([NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]], @"en");
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSBundle *same = bundle(root, @"0.0.9", [NSString stringWithUTF8String:argv[2]]);
    NSBundle *different = bundle(root, @"17", [NSString stringWithUTF8String:argv[2]]);
    SCAboutWindowController *about = [[SCAboutWindowController alloc] initWithBundle:same];
    SCAboutWindowController *numbered = [[SCAboutWindowController alloc] initWithBundle:different];
    NSView *view = about.window.contentView;
    Method method = class_getInstanceMethod(NSWorkspace.class, @selector(openURL:));
    IMP original = method_setImplementation(method, (IMP)captureURL);
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSApp.appearance = [NSAppearance appearanceNamed:appearance];
        for (NSString *language in @[@"en", @"zh-Hans", @"zh-Hant"]) {
            SCUseLanguage(language);
            [view layoutSubtreeIfNeeded];
            assert(([about.window.title isEqual:[NSString stringWithFormat:SCLocalized(@"About %@"), @"Anmir"]]));
            NSTextField *version = (NSTextField *)find(view, @"About.version");
            assert(([version.stringValue isEqual:[NSString stringWithFormat:SCLocalized(@"Version %@"), @"0.0.9"]]));
            assert(([((NSTextField *)find(numbered.window.contentView, @"About.version")).stringValue
                isEqual:[NSString stringWithFormat:SCLocalized(@"Version %@ (Build %@)"), @"0.0.9", @"17"]]));
            assert(([((NSTextField *)find(view, @"About.description")).stringValue isEqual:SCLocalized(@"Mirror and control Android devices from your Mac.")]));
            assert((((NSImageView *)find(view, @"About.icon")).image));
            for (NSString *identifier in @[@"About.project", @"About.feedback", @"About.licenses"]) {
                NSButton *button = (NSButton *)find(view, identifier);
                NSRect rect = [button convertRect:button.bounds toView:view];
                assert((NSMinX(rect) >= 0 && NSMaxX(rect) <= view.bounds.size.width));
                assert((NSMinY(rect) >= 0 && NSMaxY(rect) <= view.bounds.size.height));
            }
            [(NSButton *)find(view, @"About.project") performClick:nil];
            assert(([opened.absoluteString isEqual:@"https://github.com/houzi3/Anmir"]));
            [(NSButton *)find(view, @"About.feedback") performClick:nil];
            assert(([opened.absoluteString isEqual:@"https://github.com/houzi3/Anmir/issues"]));
            [(NSButton *)find(view, @"About.licenses") performClick:nil];
            NSWindowController *licenses = [about valueForKey:@"licenses"];
            assert(([licenses.window.title isEqual:SCLocalized(@"Open Source Licenses")]));
            NSTextView *text = [about valueForKey:@"licenseText"];
            assert(([text.string containsString:SCLocalized(@"Upstream Notices")]));
            assert(([text.string containsString:@"Unmodified license fixture"]));
            assert(([text.string containsString:@"dependency.txt"]));
            assert((about.anyWindowVisible));
            // Keep the license window open so the next language change updates
            // both its heading and its contents, without reopening About.
        }
    }
    method_setImplementation(method, original);
    [(NSWindowController *)[about valueForKey:@"licenses"] close];
    [about close]; assert((!about.anyWindowVisible));
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("About links, version display, bundled licenses and three live languages in both appearances passed");
} return 0; }
