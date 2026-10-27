#import "apk_installer.h"

#import <AppKit/AppKit.h>
#import <os/log.h>
#include <stdlib.h>
#include <string.h>
#import "device_support.h"
#import "device_ui.h"
#import "localization.h"
#import "settings.h"

static NSPasteboardName const SCAPKInstallPasteboardName =
    @"io.github.laobie.anmir.install-request";
static NSPasteboardType const SCAPKInstallPasteboardType =
    @"io.github.laobie.anmir.install-request";
static const CGFloat SCAPKInstallerWindowWidth = 600.0;
static const CGFloat SCAPKInstallerDetailWidth = 544.0;
static const CGFloat SCAPKInstallerProgressHeight = 200.0;
static const CGFloat SCAPKInstallerResultMinimumHeight = 160.0;

@interface SCAPKInstallerController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSImageView *icon;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) SCDeviceButton *button;
@property(nonatomic, strong) SCDeviceCommand *command;
@property(nonatomic) int result;
@end

@implementation SCAPKInstallerController

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *label = SCDeviceLabel(text, size, weight, NO);
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
        forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (void)setStatusSymbol:(NSString *)symbol color:(NSColor *)color {
    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:27
            weight:NSFontWeightRegular];
    self.icon.image = [SCDeviceSymbol(symbol)
        imageWithSymbolConfiguration:configuration];
    self.icon.contentTintColor = color;
}

- (void)resizeForDetailText:(NSString *)text {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: self.detailLabel.font,
    };
    NSRect textBounds = [text boundingRectWithSize:
        NSMakeSize(SCAPKInstallerDetailWidth, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:attributes];
    CGFloat desiredHeight = MAX(SCAPKInstallerResultMinimumHeight,
        ceil(textBounds.size.height) + 145.0);
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    CGFloat maximumHeight = screen
        ? MAX(SCAPKInstallerResultMinimumHeight,
            screen.visibleFrame.size.height - 80.0)
        : 700.0;
    CGFloat contentHeight = MIN(desiredHeight, maximumHeight);
    if (desiredHeight > maximumHeight) {
        CGFloat lineHeight = self.detailLabel.font.ascender
            - self.detailLabel.font.descender + self.detailLabel.font.leading;
        self.detailLabel.maximumNumberOfLines = MAX(3,
            (NSInteger)floor((maximumHeight - 145.0) / lineHeight));
        self.detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    } else {
        self.detailLabel.maximumNumberOfLines = 0;
        self.detailLabel.lineBreakMode = NSLineBreakByCharWrapping;
    }
    CGFloat currentHeight = self.window.contentView.bounds.size.height;
    if (fabs(contentHeight - currentHeight) > 0.5) {
        NSRect oldFrame = self.window.frame;
        NSRect newFrame = [self.window frameRectForContentRect:
            NSMakeRect(0, 0, SCAPKInstallerWindowWidth, contentHeight)];
        // Anchor the title bar while the same window contracts for a result
        // or expands for a long error. This reads as an in-place transition.
        newFrame.origin.x = oldFrame.origin.x;
        newFrame.origin.y = NSMaxY(oldFrame) - newFrame.size.height;
        if (screen) {
            newFrame.origin.y = MAX(NSMinY(screen.visibleFrame),
                newFrame.origin.y);
        }
        [self.window setFrame:newFrame display:YES animate:YES];
    }
}

- (instancetype)initWithAPK:(NSString *)apk serial:(NSString *)serial
        deviceName:(NSString *)deviceName {
    self = [super init];
    if (!self) {
        return nil;
    }
    _result = 1;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
        SCAPKInstallerWindowWidth, SCAPKInstallerProgressHeight)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    _window.contentMinSize = NSMakeSize(SCAPKInstallerWindowWidth,
        SCAPKInstallerResultMinimumHeight);
    _window.contentMaxSize = NSMakeSize(SCAPKInstallerWindowWidth, CGFLOAT_MAX);
    _window.title = @"Anmir";
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.titlebarAppearsTransparent = YES;
    _window.backgroundColor = SCDeviceBackground();
    _window.contentView = [[SCDeviceSurface alloc]
        initWithFrame:_window.contentView.bounds];

    NSView *content = _window.contentView;
    _icon = [[NSImageView alloc] init];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    [self setStatusSymbol:@"iphone.and.arrow.forward" color:SCDeviceBlue()];
    _titleLabel = [self label:SCLocalized(@"Installing APK…") size:17
        weight:NSFontWeightSemibold];
    _detailLabel = [self label:[NSString stringWithFormat:@"%@\n%@",
        apk.lastPathComponent, deviceName] size:12 weight:NSFontWeightRegular];
    _detailLabel.textColor = NSColor.secondaryLabelColor;
    _detailLabel.lineBreakMode = NSLineBreakByCharWrapping;
    _detailLabel.selectable = YES;
    _progress = [[NSProgressIndicator alloc] init];
    _progress.style = NSProgressIndicatorStyleBar;
    _progress.indeterminate = YES;
    _progress.translatesAutoresizingMaskIntoConstraints = NO;
    [_progress startAnimation:nil];
    _button = [SCDeviceButton buttonWithTitle:@"Cancel" target:self
        action:@selector(buttonPressed:)];
    _button.primary = NO;
    _button.bezelStyle = NSBezelStyleRounded;
    _button.font = [NSFont systemFontOfSize:12];
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in @[_icon, _titleLabel, _detailLabel, _progress,
            _button]) {
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:26],
        [_icon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [_icon.widthAnchor constraintEqualToConstant:32],
        [_icon.heightAnchor constraintEqualToConstant:32],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:12],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-28],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
        [_detailLabel.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:18],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28],
        [_detailLabel.widthAnchor constraintEqualToConstant:SCAPKInstallerDetailWidth],
        [_progress.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:16],
        [_progress.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [_progress.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28],
        [_button.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [_button.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [_button.widthAnchor constraintGreaterThanOrEqualToConstant:84],
        [_button.heightAnchor constraintEqualToConstant:32],
    ]];
    [_window center];

    NSString *adb = [[NSBundle.mainBundle.executableURL URLByDeletingLastPathComponent].path
        stringByAppendingPathComponent:@"adb"];
    __weak SCAPKInstallerController *weakSelf = self;
    _command = [SCDeviceCommand run:adb
        arguments:@[@"-s", serial, @"install", @"-r", apk]
        input:nil timeout:600 completion:^(NSString *output, int status) {
            SCAPKInstallerController *controller = weakSelf;
            if (!controller) {
                return;
            }
            [controller.progress stopAnimation:nil];
            controller.progress.hidden = YES;
            controller.result = status == 0 ? 0 : 1;
            os_log(OS_LOG_DEFAULT,
                "Anmir APK installation completed with status %d", status);
            NSString *message = [output stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (status == 0) {
                controller.titleLabel.stringValue = SCLocalized(@"APK installed");
                controller.detailLabel.stringValue = [NSString stringWithFormat:
                    SCLocalized(@"Installed “%@” on %@."),
                    apk.lastPathComponent, deviceName];
                [controller setStatusSymbol:@"checkmark.circle.fill"
                    color:SCDeviceBlue()];
                controller.button.title = SCLocalized(@"OK");
                controller.button.primary = YES;
            } else {
                controller.titleLabel.stringValue =
                    SCLocalized(@"APK installation failed");
                controller.detailLabel.stringValue = message.length
                    ? message : SCLocalized(@"ADB did not return an error message.");
                [controller setStatusSymbol:@"exclamationmark.triangle.fill"
                    color:NSColor.systemRedColor];
                controller.button.title = SCLocalized(@"Close");
                controller.button.primary = NO;
            }
            controller.button.hidden = NO;
            [controller resizeForDetailText:controller.detailLabel.stringValue];
            [NSApp activateIgnoringOtherApps:YES];
            [controller.window makeKeyAndOrderFront:nil];
            [controller.window orderFrontRegardless];
        }];
    return self;
}

- (void)show {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

- (void)buttonPressed:(id)sender {
    (void)sender;
    if (self.command.running) {
        [self.command cancel];
        self.button.enabled = NO;
        self.titleLabel.stringValue = SCLocalized(@"Cancelling…");
    } else {
        [self.window close];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (self.command.running) {
        [self.command cancel];
    }
    [NSApp stop:nil];
}

@end

static BOOL SCAPKArguments(int argc, char *argv[], NSString **apk,
                           NSString **serial, NSString **deviceName) {
    *apk = nil;
    *serial = nil;
    *deviceName = nil;
    // LaunchServices may append system arguments such as -AppleLanguages.
    // Find the private installer arguments instead of requiring an exact argc
    // and position, while still requiring both markers before handling the
    // invocation as an APK installation.
    for (int i = 1; i + 1 < argc; ++i) {
        if (!strcmp(argv[i], "--anmir-install-apk")) {
            *apk = [NSString stringWithUTF8String:argv[++i]];
        } else if (!strcmp(argv[i], "--serial")) {
            *serial = [NSString stringWithUTF8String:argv[++i]];
        } else if (!strcmp(argv[i], "--device-name")) {
            *deviceName = [NSString stringWithUTF8String:argv[++i]];
        }
    }
    // NSWorkspaceOpenConfiguration ignores command-line arguments from a
    // sandboxed caller. The Finder extension passes the same request through
    // the launch environment as a supported fallback.
    if (!(*apk).length) {
        const char *value = getenv("ANMIR_INSTALL_APK");
        if (value) {
            *apk = [NSString stringWithUTF8String:value];
        }
    }
    if (!(*serial).length) {
        const char *value = getenv("ANMIR_INSTALL_SERIAL");
        if (value) {
            *serial = [NSString stringWithUTF8String:value];
        }
    }
    if (!(*deviceName).length) {
        const char *value = getenv("ANMIR_INSTALL_DEVICE");
        if (value) {
            *deviceName = [NSString stringWithUTF8String:value];
        }
    }
    if (!(*apk).length || !(*serial).length || !(*deviceName).length) {
        NSPasteboard *handoff =
            [NSPasteboard pasteboardWithName:SCAPKInstallPasteboardName];
        id value = [handoff propertyListForType:SCAPKInstallPasteboardType];
        if ([value isKindOfClass:NSDictionary.class]) {
            NSDictionary *request = value;
            NSString *requestAPK = request[@"apk"];
            NSString *requestSerial = request[@"serial"];
            NSString *requestDeviceName = request[@"deviceName"];
            NSNumber *created = request[@"created"];
            if ([requestAPK isKindOfClass:NSString.class]
                    && [requestSerial isKindOfClass:NSString.class]
                    && [created isKindOfClass:NSNumber.class]) {
                NSTimeInterval age = [NSDate date].timeIntervalSince1970
                    - created.doubleValue;
                if (age >= -5.0 && age <= 30.0) {
                    if (!(*apk).length) {
                        *apk = requestAPK;
                    }
                    if (!(*serial).length) {
                        *serial = requestSerial;
                    }
                    if (!(*deviceName).length
                            && [requestDeviceName isKindOfClass:NSString.class]) {
                        *deviceName = requestDeviceName;
                    }
                }
            }
        }
        // Consume both valid and stale requests. A normal app launch must
        // never reuse an old Finder action.
        [handoff clearContents];
    }
    if (!(*deviceName).length) {
        *deviceName = *serial;
    }
    return (*apk).length && (*serial).length;
}

int sc_apk_installer_try_run(int argc, char *argv[], bool *handled) {
    @autoreleasepool {
        NSString *apk = nil;
        NSString *serial = nil;
        NSString *deviceName = nil;
        *handled = SCAPKArguments(argc, argv, &apk, &serial, &deviceName);
        if (!*handled) {
            return 0;
        }
        os_log(OS_LOG_DEFAULT,
            "Anmir APK installer started for %{public}@ on %{public}@",
            apk.lastPathComponent, serial);
        BOOL directory = NO;
        BOOL exists = apk.length && [NSFileManager.defaultManager
            fileExistsAtPath:apk isDirectory:&directory];
        if (!exists || directory || !serial.length
                || [apk.pathExtension caseInsensitiveCompare:@"apk"] != NSOrderedSame) {
            return 1;
        }
        [NSApplication sharedApplication];
        SCLocalizationInitialize(NSBundle.mainBundle, SCSettingsLanguage());
        NSString *theme = SCSettingsTheme();
        if ([theme isEqualToString:@"light"]) {
            NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        } else if ([theme isEqualToString:@"dark"]) {
            NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        } else {
            NSApp.appearance = nil;
        }
        SCAPKInstallerController *controller = [[SCAPKInstallerController alloc]
            initWithAPK:apk serial:serial deviceName:deviceName];
        [controller show];
        [NSApp run];
        return controller.result;
    }
}
