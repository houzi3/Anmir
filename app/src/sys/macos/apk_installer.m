#import "apk_installer.h"
#import "apk_batch.h"
#import "apk_devices.h"

#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <os/log.h>
#include <stdlib.h>
#include <string.h>
#import "device_support.h"
#import "device_ui.h"
#import "localization.h"
#import "mirror_session.h"
#import "settings.h"

static NSPasteboardName const SCAPKInstallPasteboardName =
    @"io.github.laobie.anmir.install-request";
static NSPasteboardType const SCAPKInstallPasteboardType =
    @"io.github.laobie.anmir.install-request";
static const CGFloat SCAPKInstallerWindowWidth = 440.0;
static const CGFloat SCAPKInstallerDetailWidth = 364.0;
static const CGFloat SCAPKInstallerProgressHeight = 236.0;
static const CGFloat SCAPKInstallerResultMinimumHeight = 210.0;
static const CGFloat SCAPKChooserWindowWidth = 460.0;
static const CGFloat SCAPKChooserInset = 24.0;
static const CGFloat SCAPKChooserRowHeight = 54.0;
static const CGFloat SCAPKChooserRowSpacing = 8.0;
static NSString *const SCAPKContentType = @"com.android.package-archive";

static NSImage *SCAPKFileIcon(void) {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"anmir-apk"
        withExtension:@"icns"];
    NSImage *image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    return image ?: SCDeviceSymbol(@"doc");
}

static NSString *SCAPKDeviceModel(SCAPKTarget *device) {
    return [device.model isEqualToString:@"Android device"]
        ? SCLocalized(@"Android device") : device.model;
}

@interface SCAPKPanel : NSView
@end

@implementation SCAPKPanel
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:
        NSInsetRect(self.bounds, .5, .5) xRadius:10 yRadius:10];
    [[NSColor.labelColor colorWithAlphaComponent:.035] setFill];
    [shape fill];
    [[NSColor.labelColor colorWithAlphaComponent:.10] setStroke];
    shape.lineWidth = 1;
    [shape stroke];
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

@interface SCAPKDeviceOption : NSButton
@property(nonatomic, strong) SCAPKTarget *device;
@property(nonatomic, strong) NSTextField *nameLabel;
@property(nonatomic, strong) NSTextField *connectionLabel;
@property(nonatomic, strong) NSImageView *deviceIcon;
@property(nonatomic, strong) NSImageView *checkmark;
- (instancetype)initWithDevice:(SCAPKTarget *)device;
- (void)updateSelectionAppearance;
@end

@implementation SCAPKDeviceOption
+ (Class)cellClass { return SCDeviceCardCell.class; }
- (instancetype)initWithDevice:(SCAPKTarget *)device {
    self = [super initWithFrame:NSZeroRect];
    if (!self) { return nil; }
    _device = device;
    [self setButtonType:NSButtonTypeSwitch];
    self.bordered = NO;
    self.title = @"";
    self.focusRingType = NSFocusRingTypeExterior;

    _deviceIcon = [NSImageView imageViewWithImage:SCDeviceSymbol(@"smartphone")];
    _deviceIcon.contentTintColor = NSColor.secondaryLabelColor;
    _nameLabel = SCDeviceLabel(@"", 13, NSFontWeightMedium, NO);
    _connectionLabel = SCDeviceLabel(@"", 11, NSFontWeightRegular, YES);
    _checkmark = [[NSImageView alloc] init];
    for (NSView *view in @[_deviceIcon, _nameLabel, _connectionLabel, _checkmark]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_deviceIcon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_deviceIcon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_deviceIcon.widthAnchor constraintEqualToConstant:20],
        [_deviceIcon.heightAnchor constraintEqualToConstant:20],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_deviceIcon.trailingAnchor constant:12],
        [_nameLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkmark.leadingAnchor constant:-12],
        [_connectionLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_connectionLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
        [_connectionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkmark.leadingAnchor constant:-12],
        [_checkmark.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_checkmark.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_checkmark.widthAnchor constraintEqualToConstant:18],
        [_checkmark.heightAnchor constraintEqualToConstant:18],
    ]];
    [self updateDeviceLabels];
    [self updateSelectionAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged:)
        name:SCLanguageChangedNotification object:nil];
    return self;
}
- (void)updateDeviceLabels {
    NSString *model = SCAPKDeviceModel(self.device);
    NSString *nickname = SCSettingsDeviceNickname(self.device.identity);
    NSString *transport = SCLocalized(self.device.transport);
    NSString *name = nickname ?: model;
    NSString *detail = nickname
        ? [NSString stringWithFormat:@"%@ · %@", model, transport] : transport;
    self.nameLabel.stringValue = name;
    self.connectionLabel.stringValue = detail;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, detail];
}
- (void)languageChanged:(NSNotification *)notification {
    (void)notification;
    [self updateDeviceLabels];
}
- (NSView *)hitTest:(NSPoint)point {
    return self.enabled && [super hitTest:point] ? self : nil;
}
- (void)updateSelectionAppearance {
    BOOL selected = self.state == NSControlStateValueOn;
    self.checkmark.image = SCDeviceSymbol(selected ? @"checkmark.square.fill" : @"square");
    self.checkmark.contentTintColor = selected ? SCDeviceBlue() : NSColor.secondaryLabelColor;
    self.deviceIcon.contentTintColor = selected
        ? SCDeviceBlue() : NSColor.secondaryLabelColor;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    BOOL selected = self.state == NSControlStateValueOn;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:
        NSInsetRect(self.bounds, .5, .5) xRadius:9 yRadius:9];
    NSColor *fill = selected
        ? [SCDeviceBlue() colorWithAlphaComponent:self.highlighted ? .14 : .075]
        : [NSColor.labelColor colorWithAlphaComponent:self.highlighted ? .065 : .025];
    [fill setFill];
    [shape fill];
    [(selected ? [SCDeviceBlue() colorWithAlphaComponent:.65]
               : [NSColor.labelColor colorWithAlphaComponent:.11]) setStroke];
    shape.lineWidth = 1;
    [shape stroke];
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

@interface SCAPKChooserList : NSView
@end

@implementation SCAPKChooserList
- (BOOL)isFlipped { return YES; }
@end

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
        [NSImageSymbolConfiguration configurationWithPointSize:32
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
    CGFloat chromeHeight = self.progress.hidden ? 176.0 : 204.0;
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
    _icon.image = SCAPKFileIcon();
    _titleLabel = [self label:SCLocalized(@"Installing APK…") size:18
        weight:NSFontWeightSemibold];
    _detailLabel = [self label:[NSString stringWithFormat:@"%@\n%@",
        apk.lastPathComponent, deviceName] size:12 weight:NSFontWeightRegular];
    _detailLabel.textColor = NSColor.secondaryLabelColor;
    _detailLabel.lineBreakMode = NSLineBreakByCharWrapping;
    _detailLabel.selectable = YES;
    _progress = [[NSProgressIndicator alloc] init];
    _progress.style = NSProgressIndicatorStyleBar;
    _progress.indeterminate = YES;
    _progress.controlSize = NSControlSizeSmall;
    _progress.translatesAutoresizingMaskIntoConstraints = NO;
    [_progress startAnimation:nil];
    _button = [SCDeviceButton buttonWithTitle:@"Cancel" target:self
        action:@selector(buttonPressed:)];
    _button.primary = NO;
    _button.bezelStyle = NSBezelStyleRounded;
    _button.font = [NSFont systemFontOfSize:12];
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    SCAPKPanel *status = [[SCAPKPanel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *statusStack = SCDeviceStack(@[_detailLabel, _progress], YES, 14);
    statusStack.alignment = NSLayoutAttributeLeading;
    [status addSubview:statusStack];
    for (NSView *view in @[_icon, _titleLabel, status, _button]) {
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:26],
        [_icon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [_icon.widthAnchor constraintEqualToConstant:40],
        [_icon.heightAnchor constraintEqualToConstant:40],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:14],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-24],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
        [status.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:18],
        [status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [status.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [status.bottomAnchor constraintEqualToAnchor:_button.topAnchor constant:-18],
        [statusStack.topAnchor constraintEqualToAnchor:status.topAnchor constant:14],
        [statusStack.leadingAnchor constraintEqualToAnchor:status.leadingAnchor constant:14],
        [statusStack.trailingAnchor constraintEqualToAnchor:status.trailingAnchor constant:-14],
        [statusStack.bottomAnchor constraintEqualToAnchor:status.bottomAnchor constant:-14],
        [_detailLabel.widthAnchor constraintEqualToConstant:SCAPKInstallerDetailWidth],
        [_progress.widthAnchor constraintEqualToAnchor:_detailLabel.widthAnchor],
        [_button.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [_button.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [_button.widthAnchor constraintGreaterThanOrEqualToConstant:88],
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
@property(nonatomic, strong) SCAPKDeviceDiscovery *discovery;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) SCDeviceButton *installButton;
@property(nonatomic, copy) NSArray<SCAPKDeviceOption *> *deviceButtons;
@property(nonatomic, copy) NSArray<SCAPKTarget *> *devices;
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

- (void)finish {
    [SCAPKActiveControllers() removeObject:self];
}

- (void)installOnDevices:(NSArray<SCAPKTarget *> *)devices {
    if (!devices.count) {
        return;
    }
    self.transitioning = YES;
    [self.window close];
    self.window = nil;

    if (devices.count > 1) {
        __block __weak SCAPKBatchController *weakBatch;
        SCAPKBatchController *batch = [[SCAPKBatchController alloc]
            initWithAPK:self.apk adb:SCAPKADBExecutable() targets:devices completion:^{
                SCAPKBatchController *controller = weakBatch;
                if (controller) { [SCAPKActiveControllers() removeObject:controller]; }
            }];
        weakBatch = batch;
        [SCAPKActiveControllers() addObject:batch];
        [batch show];
        [self finish];
        return;
    }

    SCAPKTarget *device = devices.firstObject;
    NSString *name = SCSettingsDeviceNickname(device.identity) ?: SCAPKDeviceModel(device);
    NSString *deviceName = [NSString stringWithFormat:@"%@ · %@",
        name, SCLocalized(device.transport)];
    SCAPKInstallerController *installer = [[SCAPKInstallerController alloc]
        initWithAPK:self.apk serial:device.serial deviceName:deviceName
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
    NSUInteger visibleRows = MIN(self.devices.count, 4);
    CGFloat rowStride = SCAPKChooserRowHeight + SCAPKChooserRowSpacing;
    CGFloat listHeight = visibleRows * rowStride - SCAPKChooserRowSpacing;
    CGFloat height = 154.0 + listHeight;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
        SCAPKChooserWindowWidth, height)
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
    NSImageView *icon = [NSImageView imageViewWithImage:SCAPKFileIcon()];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *heading = SCDeviceLocalizedLabel(@"Choose one or more devices", 18,
        NSFontWeightSemibold, NO);
    NSTextField *detail = SCDeviceLabel(@"", 12, NSFontWeightRegular, YES);
    SCBindFormat(detail, @"stringValue", @"Install “%@” on:", @[_apk.lastPathComponent]);
    detail.lineBreakMode = NSLineBreakByTruncatingMiddle;
    detail.toolTip = self.apk.lastPathComponent;

    CGFloat listWidth = SCAPKChooserWindowWidth - 2 * SCAPKChooserInset;
    NSScrollView *deviceList = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 0, listWidth, listHeight)];
    deviceList.translatesAutoresizingMaskIntoConstraints = NO;
    deviceList.borderType = NSNoBorder;
    deviceList.drawsBackground = NO;
    deviceList.hasVerticalScroller = self.devices.count > visibleRows;
    deviceList.autohidesScrollers = YES;
    CGFloat optionsWidth = deviceList.contentSize.width;
    CGFloat optionsHeight = self.devices.count * rowStride - SCAPKChooserRowSpacing;
    NSView *options = [[SCAPKChooserList alloc] initWithFrame:
        NSMakeRect(0, 0, optionsWidth, optionsHeight)];
    options.autoresizingMask = NSViewWidthSizable;
    NSMutableArray<SCAPKDeviceOption *> *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < self.devices.count; ++index) {
        SCAPKDeviceOption *option = [[SCAPKDeviceOption alloc]
            initWithDevice:self.devices[index]];
        option.frame = NSMakeRect(0, index * rowStride, optionsWidth, SCAPKChooserRowHeight);
        option.autoresizingMask = NSViewWidthSizable;
        option.tag = (NSInteger)index;
        option.target = self;
        option.action = @selector(selectDevice:);
        option.identifier = [NSString stringWithFormat:@"APKChooser.Device.%lu",
            (unsigned long)index];
        [options addSubview:option];
        [buttons addObject:option];
    }
    self.deviceButtons = buttons;
    deviceList.documentView = options;

    SCDeviceButton *cancel = [SCDeviceButton buttonWithTitle:@"Cancel"
        target:self action:@selector(cancel:)];
    cancel.primary = NO;
    cancel.font = [NSFont systemFontOfSize:12];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    SCDeviceButton *install = [SCDeviceButton buttonWithTitle:@"Install"
        target:self action:@selector(install:)];
    install.primary = YES;
    install.enabled = NO;
    install.identifier = @"APKChooser.Install";
    install.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    install.keyEquivalent = @"\r";
    install.translatesAutoresizingMaskIntoConstraints = NO;
    self.installButton = install;

    for (NSView *view in @[icon, heading, detail, deviceList,
            cancel, install]) {
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:SCAPKChooserInset],
        [icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:26],
        [icon.widthAnchor constraintEqualToConstant:40],
        [icon.heightAnchor constraintEqualToConstant:40],
        [heading.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [heading.topAnchor constraintEqualToAnchor:icon.topAnchor constant:1],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-SCAPKChooserInset],
        [detail.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-SCAPKChooserInset],
        [detail.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:4],
        [deviceList.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:SCAPKChooserInset],
        [deviceList.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-SCAPKChooserInset],
        [deviceList.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:20],
        [deviceList.heightAnchor constraintEqualToConstant:listHeight],
        [install.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-SCAPKChooserInset],
        [install.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [install.widthAnchor constraintGreaterThanOrEqualToConstant:88],
        [install.heightAnchor constraintEqualToConstant:32],
        [cancel.trailingAnchor constraintEqualToAnchor:install.leadingAnchor constant:-10],
        [cancel.centerYAnchor constraintEqualToAnchor:install.centerYAnchor],
        [cancel.widthAnchor constraintEqualToConstant:88],
        [cancel.heightAnchor constraintEqualToConstant:32],
    ]];
    [self.window center];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}

- (void)selectDevice:(SCAPKDeviceOption *)sender {
    [sender updateSelectionAppearance];
    NSUInteger count = self.selectedDevices.count;
    self.installButton.enabled = count > 0;
    if (count > 1) {
        SCBindFormat(self.installButton, @"title", @"Install (%@)", @[@(count).stringValue]);
    } else {
        SCBind(self.installButton, @"title", @"Install");
    }
}

- (NSArray<SCAPKTarget *> *)selectedDevices {
    NSMutableArray<SCAPKTarget *> *selected = [NSMutableArray array];
    for (SCAPKDeviceOption *option in self.deviceButtons) {
        if (option.state == NSControlStateValueOn) {
            [selected addObject:self.devices[(NSUInteger)option.tag]];
        }
    }
    return selected;
}

- (void)begin {
    self.discovery = [[SCAPKDeviceDiscovery alloc] initWithADB:SCAPKADBExecutable()];
    __weak SCAPKOpenController *weakSelf = self;
    [self.discovery startWithCompletion:^(NSArray<SCAPKTarget *> *devices, int status) {
        SCAPKOpenController *controller = weakSelf;
        if (!controller) {
            return;
        }
        controller.discovery = nil;
        controller.devices = devices;
        os_log(OS_LOG_DEFAULT,
            "Anmir APK open found %lu available device(s), ADB status %d",
            (unsigned long)devices.count, status);
        if (!devices.count) {
            void (^showDevices)(void) = controller.showDevices;
            [controller finish];
            if (showDevices) {
                showDevices();
            }
        } else if (devices.count == 1) {
            [controller installOnDevices:devices];
        } else {
            [controller showChooser];
        }
    }];
}

- (void)install:(id)sender {
    (void)sender;
    [self installOnDevices:self.selectedDevices];
}

- (void)cancel:(id)sender {
    (void)sender;
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (!self.transitioning) {
        [self.discovery cancel];
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
    // Per-device mirroring windows run from disposable app bundles. They carry
    // the host identifier in their Info.plist, but must never become document
    // handlers themselves.
    if (![SCMirrorHostBundleIdentifier()
            isEqualToString:bundle.bundleIdentifier]) {
        return;
    }
    NSString *version = [bundle objectForInfoDictionaryKey:
        @"CFBundleShortVersionString"] ?: @"unknown";
    NSString *preference = [@"AnmirAPKDefaultHandler." stringByAppendingString:version];
    BOOL registered = [NSUserDefaults.standardUserDefaults boolForKey:preference];
    CFStringRef copiedHandler = LSCopyDefaultRoleHandlerForContentType(
        (__bridge CFStringRef)SCAPKContentType, kLSRolesAll);
    NSString *handler = CFBridgingRelease(copiedHandler);
    BOOL isHost = [handler isEqualToString:bundle.bundleIdentifier];
    BOOL isStaleMirror = [handler hasPrefix:
        [bundle.bundleIdentifier stringByAppendingString:@".mirror."]];
    if (registered && isHost) {
        return;
    }
    // Respect a handler the user selected deliberately. The missing-handler
    // and mirror cases are ours to repair, even if this version registered
    // successfully before the disposable helper stole the association.
    if (registered && handler.length && !isStaleMirror) {
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
        if (type) {
            [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:bundle.bundleURL
                toOpenContentType:type completionHandler:complete];
            return;
        }
    }
    // The imported APK type may not be visible to UniformTypeIdentifiers yet
    // on the app's first launch. The Launch Services API also covers macOS 11.
    OSStatus status = LSSetDefaultRoleHandlerForContentType(
        (__bridge CFStringRef)SCAPKContentType, kLSRolesAll,
        (__bridge CFStringRef)bundle.bundleIdentifier);
    complete(status == noErr ? nil : [NSError errorWithDomain:NSOSStatusErrorDomain
        code:status userInfo:nil]);
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
