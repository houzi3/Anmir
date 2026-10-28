#import "apk_installer.h"

#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <os/log.h>
#include <stdlib.h>
#include <string.h>
#import "device_support.h"
#import "device_ui.h"
#import "finder_device_menu.h"
#import "localization.h"
#import "settings.h"

static NSPasteboardName const SCAPKInstallPasteboardName =
    @"io.github.laobie.anmir.install-request";
static NSPasteboardType const SCAPKInstallPasteboardType =
    @"io.github.laobie.anmir.install-request";
static const CGFloat SCAPKInstallerWindowWidth = 300.0;
static const CGFloat SCAPKInstallerDetailWidth = 244.0;
static const CGFloat SCAPKInstallerProgressHeight = 180.0;
static const CGFloat SCAPKInstallerResultMinimumHeight = 160.0;
static NSString *const SCAPKContentType = @"com.android.package-archive";

static NSMutableSet *SCAPKActiveControllers(void) {
    static NSMutableSet *controllers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controllers = [NSMutableSet set];
    });
    return controllers;
}

bool sc_apk_installer_busy(void) {
    return SCAPKActiveControllers().count > 0;
}

static NSString *SCAPKADBExecutable(void) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"ADB"];
    if (configured.length) {
        return SCDeviceExecutable(configured.UTF8String);
    }
    return [[NSBundle.mainBundle.executableURL URLByDeletingLastPathComponent].path
        stringByAppendingPathComponent:@"adb"];
}

@interface SCAPKInstallerController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSImageView *icon;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) SCDeviceButton *button;
@property(nonatomic, strong) SCDeviceCommand *command;
@property(nonatomic) int result;
@property(nonatomic) BOOL exitWhenClosed;
@property(nonatomic, copy) void (^completion)(void);
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
    CGFloat chromeHeight = self.progress.hidden ? 145.0 : 165.0;
    CGFloat desiredHeight = MAX(SCAPKInstallerResultMinimumHeight,
        ceil(textBounds.size.height) + chromeHeight);
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
            (NSInteger)floor((maximumHeight - chromeHeight) / lineHeight));
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
        deviceName:(NSString *)deviceName exitWhenClosed:(BOOL)exitWhenClosed
        completion:(void (^)(void))completion {
    self = [super init];
    if (!self) {
        return nil;
    }
    _result = 1;
    _exitWhenClosed = exitWhenClosed;
    _completion = [completion copy];
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
    [self resizeForDetailText:_detailLabel.stringValue];
    [_window center];

    NSString *adb = SCAPKADBExecutable();
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
            controller.button.enabled = YES;
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
    if (self.exitWhenClosed) {
        [NSApp stop:nil];
    }
    if (self.completion) {
        self.completion();
        self.completion = nil;
    }
}

@end

@interface SCAPKOpenController : NSObject <NSWindowDelegate>
@property(nonatomic, copy) NSString *apk;
@property(nonatomic, copy) void (^showDevices)(void);
@property(nonatomic, strong) SCDeviceCommand *command;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSPopUpButton *devicePicker;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *devices;
@property(nonatomic) BOOL transitioning;
- (instancetype)initWithAPK:(NSString *)apk
        showDevices:(void (^)(void))showDevices;
- (void)begin;
@end

@implementation SCAPKOpenController

- (instancetype)initWithAPK:(NSString *)apk
        showDevices:(void (^)(void))showDevices {
    self = [super init];
    if (self) {
        _apk = [apk copy];
        _showDevices = [showDevices copy];
    }
    return self;
}

- (NSString *)displayNameForDevice:(NSDictionary<NSString *, NSString *> *)device {
    NSString *transport = device[SCFinderDeviceTransportKey];
    if (![transport isEqualToString:@"Wi-Fi"]) {
        transport = SCLocalized(transport);
    }
    return [NSString stringWithFormat:@"%@ · %@",
        device[SCFinderDeviceModelKey], transport];
}

- (void)finish {
    [SCAPKActiveControllers() removeObject:self];
}

- (void)installOnDevice:(NSDictionary<NSString *, NSString *> *)device {
    NSString *serial = device[SCFinderDeviceSerialKey];
    if (!serial.length) {
        return;
    }
    self.transitioning = YES;
    [self.window close];
    self.window = nil;

    NSString *deviceName = [self displayNameForDevice:device];
    SCAPKInstallerController *installer = [[SCAPKInstallerController alloc]
        initWithAPK:self.apk serial:serial deviceName:deviceName
        exitWhenClosed:NO completion:nil];
    __weak SCAPKInstallerController *weakInstaller = installer;
    installer.completion = ^{
        [SCAPKActiveControllers() removeObject:weakInstaller];
    };
    [SCAPKActiveControllers() addObject:installer];
    [installer show];
    [self finish];
}

- (void)showChooser {
    CGFloat height = 190.0;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Anmir";
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    self.window.titlebarAppearsTransparent = YES;
    self.window.backgroundColor = SCDeviceBackground();
    self.window.contentView = [[SCDeviceSurface alloc]
        initWithFrame:self.window.contentView.bounds];

    NSView *content = self.window.contentView;
    NSImageView *icon = [NSImageView imageViewWithImage:
        SCDeviceSymbol(@"iphone.and.arrow.forward")];
    icon.contentTintColor = SCDeviceBlue();
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *heading = SCDeviceLocalizedLabel(@"Choose a device", 17,
        NSFontWeightSemibold, NO);
    NSTextField *detail = SCDeviceLabel([NSString stringWithFormat:
        SCLocalized(@"Install “%@” on:"), self.apk.lastPathComponent], 12,
        NSFontWeightRegular, YES);
    detail.lineBreakMode = NSLineBreakByTruncatingMiddle;
    detail.toolTip = self.apk.lastPathComponent;

    self.devicePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
        pullsDown:NO];
    self.devicePicker.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSDictionary<NSString *, NSString *> *device in self.devices) {
        [self.devicePicker addItemWithTitle:[self displayNameForDevice:device]];
    }
    self.devicePicker.toolTip = SCLocalized(@"Choose a device");

    SCDeviceButton *cancel = [SCDeviceButton buttonWithTitle:@"Cancel"
        target:self action:@selector(cancel:)];
    cancel.primary = NO;
    cancel.font = [NSFont systemFontOfSize:12];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    SCDeviceButton *install = [SCDeviceButton buttonWithTitle:@"Install"
        target:self action:@selector(install:)];
    install.primary = YES;
    install.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    install.keyEquivalent = @"\r";
    install.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *view in @[icon, heading, detail, self.devicePicker,
            cancel, install]) {
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:26],
        [icon.widthAnchor constraintEqualToConstant:32],
        [icon.heightAnchor constraintEqualToConstant:32],
        [heading.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [heading.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-28],
        [detail.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [detail.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28],
        [detail.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:18],
        [self.devicePicker.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [self.devicePicker.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28],
        [self.devicePicker.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:10],
        [install.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [install.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [install.widthAnchor constraintEqualToConstant:84],
        [install.heightAnchor constraintEqualToConstant:32],
        [cancel.trailingAnchor constraintEqualToAnchor:install.leadingAnchor constant:-10],
        [cancel.centerYAnchor constraintEqualToAnchor:install.centerYAnchor],
        [cancel.widthAnchor constraintEqualToConstant:84],
        [cancel.heightAnchor constraintEqualToConstant:32],
    ]];
    [self.window center];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

- (void)begin {
    NSString *adb = SCAPKADBExecutable();
    __weak SCAPKOpenController *weakSelf = self;
    self.command = [SCDeviceCommand run:adb arguments:@[@"devices", @"-l"]
        input:nil timeout:5 completion:^(NSString *output, int status) {
            SCAPKOpenController *controller = weakSelf;
            if (!controller) {
                return;
            }
            controller.command = nil;
            controller.devices = status == 0
                ? SCFinderParseADBDevices(output) : @[];
            os_log(OS_LOG_DEFAULT,
                "Anmir APK open found %lu available device(s), ADB status %d",
                (unsigned long)controller.devices.count, status);
            if (!controller.devices.count) {
                void (^showDevices)(void) = controller.showDevices;
                [controller finish];
                if (showDevices) {
                    showDevices();
                }
            } else if (controller.devices.count == 1) {
                [controller installOnDevice:controller.devices.firstObject];
            } else {
                [controller showChooser];
            }
        }];
}

- (void)install:(id)sender {
    (void)sender;
    NSInteger index = self.devicePicker.indexOfSelectedItem;
    if (index >= 0 && (NSUInteger)index < self.devices.count) {
        [self installOnDevice:self.devices[(NSUInteger)index]];
    }
}

- (void)cancel:(id)sender {
    (void)sender;
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (!self.transitioning) {
        [self.command cancel];
        [self finish];
    }
}

@end

bool sc_apk_installer_open_file(NSString *path,
                                void (^show_devices)(void)) {
    NSString *apk = path.stringByStandardizingPath;
    BOOL directory = NO;
    BOOL valid = apk.length
        && [apk.pathExtension caseInsensitiveCompare:@"apk"] == NSOrderedSame
        && [NSFileManager.defaultManager fileExistsAtPath:apk
                                              isDirectory:&directory]
        && !directory;
    if (!valid) {
        return false;
    }
    os_log(OS_LOG_DEFAULT, "Anmir opened APK %{public}@",
        apk.lastPathComponent);
    SCAPKOpenController *controller = [[SCAPKOpenController alloc]
        initWithAPK:apk showDevices:show_devices];
    [SCAPKActiveControllers() addObject:controller];
    [controller begin];
    return true;
}

void sc_apk_installer_register_file_association(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    if (!bundle.bundleURL || !bundle.bundleIdentifier.length
            || ![[bundle objectForInfoDictionaryKey:@"CFBundlePackageType"]
                isEqualToString:@"APPL"]) {
        return;
    }
    NSString *version = [bundle objectForInfoDictionaryKey:
        @"CFBundleShortVersionString"] ?: @"unknown";
    NSString *preference = [@"AnmirAPKDefaultHandler." stringByAppendingString:version];
    if ([NSUserDefaults.standardUserDefaults boolForKey:preference]) {
        return;
    }
    void (^complete)(NSError *) = ^(NSError *error) {
        if (error) {
            os_log_error(OS_LOG_DEFAULT,
                "Could not make Anmir the default APK handler: %{public}@",
                error.localizedDescription);
            return;
        }
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:preference];
        os_log(OS_LOG_DEFAULT, "Anmir is the default APK handler");
    };
    if (@available(macOS 12.0, *)) {
        UTType *type = [UTType typeWithIdentifier:SCAPKContentType];
        [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:bundle.bundleURL
            toOpenContentType:type completionHandler:complete];
    } else {
        OSStatus status = LSSetDefaultRoleHandlerForContentType(
            (__bridge CFStringRef)SCAPKContentType, kLSRolesAll,
            (__bridge CFStringRef)bundle.bundleIdentifier);
        complete(status == noErr ? nil : [NSError errorWithDomain:NSOSStatusErrorDomain
            code:status userInfo:nil]);
    }
}

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
            initWithAPK:apk serial:serial deviceName:deviceName
            exitWhenClosed:YES completion:nil];
        [controller show];
        [NSApp run];
        return controller.result;
    }
}
