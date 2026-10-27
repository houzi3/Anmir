#import "device_wifi.h"
#import "localization.h"
#import "device_support.h"
#import "device_ui.h"
#import "device_pairing.h"
#import "device_connection.h"
#import "device_relay.h"
#import "device_reconnect.h"
#include "config.h"

static NSString * const SCCompanionDownloadPage =
    @"https://github.com/houzi3/Anmir/releases/tag/v" SCRCPY_VERSION;

typedef NS_ENUM(NSUInteger, SCDeviceWiFiMode) {
    SCDeviceWiFiQRCode, SCDeviceWiFiPairingCode, SCDeviceWiFiManual,
};

@interface SCDeviceQRImageView : NSImageView
@end
@implementation SCDeviceQRImageView
- (void)drawRect:(NSRect)dirtyRect {
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationNone;
    [super drawRect:dirtyRect];
}
@end

// Both prerequisites share one hierarchy. Keep icons aligned to the first
// text line when a localized navigation path wraps.
static NSView *SCDeviceQRGuideRow(NSString *symbol, NSString *key, NSString *identifier) {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSImageView *icon = [NSImageView imageViewWithImage:SCDeviceSymbol(symbol)];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.accessibilityElement = NO;
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.identifier = identifier;
    label.font = [NSFont systemFontOfSize:11.5];
    label.textColor = NSColor.secondaryLabelColor;
    label.maximumNumberOfLines = 0;
    label.preferredMaxLayoutWidth = 448;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    SCBind(label, @"stringValue", key);
    [row addSubview:icon];
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [icon.topAnchor constraintEqualToAnchor:row.topAnchor],
        [icon.widthAnchor constraintEqualToConstant:16],
        [icon.heightAnchor constraintEqualToConstant:16],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:1],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:16],
    ]];
    return row;
}

// A single rounded surface groups the two recovery choices and the compact
// company-network instructions without adding extra borders between rows.
@interface SCWiFiPanel : NSView
@end
@implementation SCWiFiPanel
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5)
        xRadius:8 yRadius:8];
    [[NSColor.controlBackgroundColor blendedColorWithFraction:.035 ofColor:NSColor.labelColor] setFill];
    [shape fill];
    [NSColor.separatorColor setStroke];
    shape.lineWidth = 1;
    [shape stroke];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

// Keep the complete row clickable even when its labels or glyphs are hit.
@interface SCWiFiActionButton : NSButton
@end
@implementation SCWiFiActionButton
+ (Class)cellClass { return SCDeviceCardCell.class; }
- (NSView *)hitTest:(NSPoint)point {
    return [super hitTest:point] ? self : nil;
}
- (void)drawRect:(NSRect)dirtyRect {
    if (self.enabled && self.cell.highlighted) {
        [[NSColor.labelColor colorWithAlphaComponent:.07] setFill];
        NSRectFill(self.bounds);
    }
    [super drawRect:dirtyRect];
}
@end

static NSTextField *SCWiFiWrappingLabel(NSString *key, NSString *identifier, CGFloat size,
                                     NSFontWeight weight, BOOL secondary) {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.identifier = identifier;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
    label.maximumNumberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    SCBind(label, @"stringValue", key);
    return label;
}

static NSView *SCWiFiStep(NSUInteger number, NSString *key, NSString *identifier, NSButton *trailing) {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSImageView *icon = [NSImageView imageViewWithImage:SCDeviceSymbol(
        [NSString stringWithFormat:@"%lu.circle", (unsigned long) number])];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.accessibilityElement = NO;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *label = SCWiFiWrappingLabel(key, identifier, 11.5, NSFontWeightMedium, NO);
    [row addSubview:icon]; [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:28],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:16], [icon.heightAnchor constraintEqualToConstant:16],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:3],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-3],
    ]];
    if (trailing) {
        [row addSubview:trailing];
        [NSLayoutConstraint activateConstraints:@[
            [trailing.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [trailing.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:trailing.leadingAnchor constant:-8],
        ]];
    } else {
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    }
    return row;
}

@interface SCDeviceWiFiController () <NSWindowDelegate, NSTextFieldDelegate>
@property(nonatomic, copy) NSString *executable;
@property(nonatomic, copy) BOOL (^mirror)(NSString *, NSDictionary<NSString *, NSString *> *);
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) SCDeviceCommand *scan;
@property(nonatomic, strong) SCDeviceConnection *connection;
@property(nonatomic, copy) NSArray<SCDeviceService *> *services;
@property(nonatomic, copy) NSArray<SCDeviceService *> *choices;
@property(nonatomic, strong) SCDeviceService *selected;
@property(nonatomic, strong) NSStackView *body;
@property(nonatomic, strong) NSTextField *message;
@property(nonatomic, strong) SCDeviceInput *code;
@property(nonatomic, strong) SCDeviceInput *address;
@property(nonatomic, strong) SCDeviceInput *port;
@property(nonatomic, strong) NSButton *modeButton;
@property(nonatomic, strong) NSButton *companyControl, *companyDownload;
@property(nonatomic, strong) SCWiFiActionButton *companyHelp, *repairHelp;
@property(nonatomic, strong) SCDeviceButton *connectButton;
@property(nonatomic, strong) SCDeviceButton *qrRefreshButton;
@property(nonatomic, strong) SCDeviceQRPairing *qrPairing;
@property(nonatomic, strong) SCDeviceRelay *relay;
@property(nonatomic, copy) NSArray<SCDeviceService *> *relayServices;
@property(nonatomic, copy) NSString *relayHost;
@property(nonatomic) BOOL companionMode;
@property(nonatomic, strong) NSDate *qrDeadline;
@property(nonatomic, strong) NSDate *helpDeadline;
@property(nonatomic, strong) SCDeviceRecovery *recovery;
@property(nonatomic, strong) NSAlert *repairAlert;
@property(nonatomic) SCDeviceWiFiMode mode;
@property(nonatomic, readonly) BOOL qrMode, manual, paired, busy;
@property(nonatomic) BOOL qrFailed;
@property(nonatomic) BOOL addressRequired;
@property(nonatomic) BOOL helpShown, repairing, repairFailed;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger scanCount;
@property(nonatomic, copy) NSString *targetHost;
@end

@implementation SCDeviceWiFiController
- (BOOL)qrMode { return self.mode == SCDeviceWiFiQRCode; }
- (BOOL)manual { return self.mode == SCDeviceWiFiManual; }
- (BOOL)paired { return self.connection.paired; }
- (BOOL)busy { return self.connection.busy || self.repairing; }
- (void)dismissRepairConfirmation {
    if (!self.repairAlert) { return; }
    [self.window endSheet:self.repairAlert.window returnCode:NSAlertSecondButtonReturn];
    self.repairAlert = nil;
}
- (void)connectionChanged {
    if (!self.window.visible) { return; }
    if (self.repairAlert && self.connection.phase != SCDeviceConnectionIdle) {
        [self dismissRepairConfirmation];
    }
    if (self.connection.phase == SCDeviceConnectionNeedsAddress) {
        [self connectionFallback:self.connection.message];
    } else if (self.connection.phase == SCDeviceConnectionReady) {
        if (self.mirror(self.connection.serial, self.connection.properties)) {
            if (self.companionMode && self.relay && [self.reconnect rememberRelay:self.relay
                    guid:self.connection.pairedGUID serial:self.connection.serial properties:self.connection.properties]) {
                self.relay = nil; // The reconnect owner keeps the route alive after this window closes.
            }
            [self close];
        } else {
            [self updateEnabled];
            [self setMessage:@"Could not open mirroring. Try again." error:YES];
        }
    } else {
        if (self.connection.paired) {
            self.code.stringValue = @"";
            self.qrPairing = nil;
        }
        if (self.qrMode && self.connection.error && !self.paired) { self.qrFailed = YES; }
        [self updateEnabled];
        [self setMessage:self.connection.message error:self.connection.error];
    }
}

- (instancetype)initWithExecutable:(NSString *)executable mirror:(BOOL (^)(NSString *, NSDictionary<NSString *, NSString *> *))mirror {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 290)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        _executable = [executable copy];
        _mirror = [mirror copy];
        _services = @[];
        _choices = @[];
        _mode = SCDeviceWiFiQRCode;
        _connection = [[SCDeviceConnection alloc] initWithExecutable:executable];
        __weak SCDeviceWiFiController *weakSelf = self;
        _connection.changed = ^{ [weakSelf connectionChanged]; };
        _qrPairing = [[SCDeviceQRPairing alloc] init];
        _qrDeadline = [NSDate dateWithTimeIntervalSinceNow:120];
        _helpDeadline = [NSDate dateWithTimeIntervalSinceNow:15];
        SCBind(window, @"title", @"Wi-Fi connection");
        window.releasedWhenClosed = NO;
        window.backgroundColor = SCDeviceBackground();
        window.titlebarAppearsTransparent = YES;
        window.delegate = self;
        window.contentView = [[SCDeviceSurface alloc] initWithFrame:window.contentView.bounds];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged:)
            name:SCLanguageChangedNotification object:nil];
        [self build];
    }
    return self;
}

- (void)languageChanged:(NSNotification *)notification {
    (void)notification;
    if (self.qrMode && !self.paired && self.body) {
        [self.window setContentSize:NSMakeSize(520, self.window.contentView.fittingSize.height)];
    }
}

- (SCDeviceButton *)button:(NSString *)title action:(SEL)action primary:(BOOL)primary {
    SCDeviceButton *button = [SCDeviceButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.primary = primary;
    button.font = [NSFont systemFontOfSize:12];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:primary ? 102 : 84].active = YES;
    [button.heightAnchor constraintEqualToConstant:32].active = YES;
    return button;
}

- (NSButton *)link:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    SCBind(button, @"title", title);
    button.bordered = NO;
    button.contentTintColor = NSColor.linkColor;
    button.font = [NSFont systemFontOfSize:12];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (SCDeviceInput *)field:(NSString *)placeholder identifier:(NSString *)identifier {
    SCDeviceInput *field = [[SCDeviceInput alloc] initWithPlaceholder:placeholder identifier:identifier];
    field.textField.delegate = self;
    return field;
}

- (void)build {
    NSTextField *editingField = self.code.textField.currentEditor ? self.code.textField
        : self.address.textField.currentEditor ? self.address.textField
        : self.port.textField.currentEditor ? self.port.textField : nil;
    NSString *editingID = editingField.identifier;
    NSRange selection = editingField ? editingField.currentEditor.selectedRange : NSMakeRange(0, 0);
    NSString *savedCode = self.code.stringValue;
    NSView *content = self.window.contentView;
    for (NSView *view in content.subviews.copy) { [view removeFromSuperview]; }
    self.body = SCDeviceStack(@[], YES, 10);
    [content addSubview:self.body];
    [NSLayoutConstraint activateConstraints:@[
        [self.body.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:self.qrMode ? 24 : 28],
        [self.body.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:self.qrMode ? -24 : -28],
        [self.body.topAnchor constraintEqualToAnchor:content.topAnchor constant:self.qrMode ? 20 : 26],
    ]];
    self.qrRefreshButton = nil;
    self.companyControl = self.companyDownload = nil;
    self.companyHelp = self.repairHelp = nil;
    if (self.qrMode && !self.manual && !self.paired) {
        self.code = self.address = self.port = nil;
        self.connectButton = nil;
        [self buildQRCode];
        return;
    }
    if (self.manual) {
        NSButton *back = [self link:@"← Back" action:@selector(back:)];
        back.enabled = !self.busy;
        [self.body addArrangedSubview:back];
        [self.body setCustomSpacing:16 afterView:back];
    } else if (!self.paired) {
        NSButton *back = [self link:@"← QR code" action:@selector(useQRCode:)];
        back.enabled = !self.busy;
        [self.body addArrangedSubview:back];
    }
    NSString *instruction = self.manual ? @"For paired devices."
        : self.paired ? @"Paired. Enter the connection address."
        : @"Wireless debugging → Pairing code.";
    [self.body addArrangedSubview:SCDeviceLocalizedLabel(instruction, 12, NSFontWeightRegular, self.manual || self.paired)];
    self.code = nil;
    if (!self.manual && !self.paired) {
        [self buildDeviceChoice];
    }
    if (self.manual || self.addressRequired || self.paired) {
        [self buildAddressFields];
    } else {
        self.address = nil;
        self.port = nil;
    }
    if (!self.manual && !self.paired) {
        [self.body addArrangedSubview:SCDeviceLocalizedLabel(@"Pairing code", 12, NSFontWeightRegular, NO)];
        self.code = [self field:@"6-digit code" identifier:@"Pairing code"];
        [self.code usePairingCodeStyle];
        self.code.enabled = !self.busy;
        [self.body addArrangedSubview:self.code];
        [self.code.widthAnchor constraintEqualToConstant:160].active = YES;
    }
    NSString *helper = self.manual || self.paired ? @"Use the connection port."
        : self.addressRequired ? @"Use the address in the pairing-code dialog."
        : @"Mirroring opens automatically.";
    [self.body addArrangedSubview:SCDeviceLocalizedLabel(helper, 11, NSFontWeightRegular, YES)];
    self.message = [NSTextField wrappingLabelWithString:@""];
    self.message.font = [NSFont systemFontOfSize:11];
    self.message.textColor = NSColor.secondaryLabelColor;
    self.message.maximumNumberOfLines = 2;
    self.message.translatesAutoresizingMaskIntoConstraints = NO;
    [self.body addArrangedSubview:self.message];
    [self.message.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;

    self.connectButton = [self button:@"Connect" action:@selector(connect:) primary:YES];
    self.connectButton.keyEquivalent = @"\r";
    SCBind(self.connectButton, @"accessibilityLabel", @"Connect over Wi-Fi");
    SCDeviceButton *cancel = [self button:@"Cancel" action:@selector(cancel:) primary:NO];
    cancel.keyEquivalent = @"\033";
    [content addSubview:self.connectButton];
    [content addSubview:cancel];
    [NSLayoutConstraint activateConstraints:@[
        [self.connectButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [self.connectButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-22],
        [cancel.trailingAnchor constraintEqualToAnchor:self.connectButton.leadingAnchor constant:-10],
        [cancel.centerYAnchor constraintEqualToAnchor:self.connectButton.centerYAnchor],
    ]];
    self.modeButton = nil;
    if (!self.manual && !self.paired) {
        self.modeButton = [self link:@"Manual connection" action:@selector(manual:)];
        self.modeButton.enabled = !self.busy;
        [content addSubview:self.modeButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.modeButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
            [self.modeButton.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
        ]];
    }
    CGFloat height = self.manual ? 278 : self.paired ? 274 : self.addressRequired ? 420 : 326;
    [self.window setContentSize:NSMakeSize(500, height)];
    self.code.stringValue = savedCode ?: @"";
    [self updateEnabled];
    NSTextField *restored = [editingID isEqualToString:self.code.textField.identifier] ? self.code.textField
        : [editingID isEqualToString:self.address.textField.identifier] ? self.address.textField
        : [editingID isEqualToString:self.port.textField.identifier] ? self.port.textField : nil;
    if (restored) {
        [self.window makeFirstResponder:restored];
        NSUInteger start = MIN(selection.location, restored.stringValue.length);
        [restored.currentEditor setSelectedRange:NSMakeRange(start,
            MIN(selection.length, restored.stringValue.length - start))];
    }
}

- (SCWiFiActionButton *)helpChoice:(NSString *)title detail:(NSString *)detail
                          identifier:(NSString *)identifier action:(SEL)action {
    SCWiFiActionButton *button = [[SCWiFiActionButton alloc] init];
    button.identifier = identifier;
    button.target = self;
    button.action = action;
    button.title = @"";
    button.bordered = NO;
    button.enabled = !self.busy;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    SCBind(button, @"accessibilityLabel", title);
    SCBind(button, @"accessibilityHelp", detail);
    NSImageView *icon = [NSImageView imageViewWithImage:SCDeviceSymbol(@"exclamationmark.circle.fill")];
    icon.contentTintColor = NSColor.systemYellowColor;
    icon.accessibilityElement = NO;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *label = SCWiFiWrappingLabel(title, nil, 12.5, NSFontWeightSemibold, NO);
    NSTextField *subtitle = SCWiFiWrappingLabel(detail, nil, 11, NSFontWeightRegular, YES);
    label.accessibilityElement = NO;
    subtitle.accessibilityElement = NO;
    NSStackView *labels = SCDeviceStack(@[label, subtitle], YES, 2);
    NSImageView *arrow = [NSImageView imageViewWithImage:SCDeviceSymbol(@"chevron.right")];
    arrow.contentTintColor = NSColor.tertiaryLabelColor;
    arrow.accessibilityElement = NO;
    arrow.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:icon]; [button addSubview:labels]; [button addSubview:arrow];
    [NSLayoutConstraint activateConstraints:@[
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:46],
        [icon.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:16], [icon.heightAnchor constraintEqualToConstant:16],
        [labels.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [labels.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [labels.topAnchor constraintGreaterThanOrEqualToAnchor:button.topAnchor constant:5],
        [labels.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-5],
        [arrow.leadingAnchor constraintGreaterThanOrEqualToAnchor:labels.trailingAnchor constant:8],
        [arrow.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-12],
        [arrow.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [arrow.widthAnchor constraintEqualToConstant:10], [arrow.heightAnchor constraintEqualToConstant:12],
    ]];
    return button;
}

- (void)buildHelp {
    NSTextField *question = SCDeviceLocalizedLabel(@"Still not connected after scanning?", 11.5,
        NSFontWeightMedium, YES);
    [self.body addArrangedSubview:question];
    [self.body setCustomSpacing:8 afterView:question];
    SCWiFiActionButton *company = [self helpChoice:@"Company network connection"
        detail:@"For company or guest networks; use the phone helper"
        identifier:@"WiFi.companyNetwork" action:@selector(useCompanyNetwork:)];
    SCWiFiActionButton *repair = [self helpChoice:self.repairFailed ? @"Retry" : @"Fix connection"
        detail:@"Restart the Mac connection service and scan again"
        identifier:@"WiFi.repair" action:@selector(confirmRepair:)];
    self.companyHelp = company;
    self.repairHelp = repair;
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *stack = SCDeviceStack(@[company, separator, repair], YES, 0);
    SCWiFiPanel *panel = [[SCWiFiPanel alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    [self.body addArrangedSubview:panel];
    [NSLayoutConstraint activateConstraints:@[
        [panel.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
        [company.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [repair.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
}

- (void)buildQRCode {
    NSView *content = self.window.contentView;
    if (self.companionMode) {
        SCDeviceIconButton *back = [SCDeviceIconButton buttonWithImage:SCDeviceSymbol(@"chevron.left")
            target:self action:@selector(useCompanyNetwork:)];
        back.glyphSize = 20;
        back.identifier = @"WiFi.companyNetwork";
        self.companyControl = back;
        back.enabled = !self.busy;
        back.translatesAutoresizingMaskIntoConstraints = NO;
        SCBind(back, @"accessibilityLabel", @"Back to QR code");
        [NSLayoutConstraint activateConstraints:@[
            [back.widthAnchor constraintEqualToConstant:22],
            [back.heightAnchor constraintEqualToConstant:28],
        ]];
        NSTextField *title = SCDeviceLocalizedLabel(@"Company network connection", 17, NSFontWeightSemibold, NO);
        NSStackView *heading = SCDeviceStack(@[back, title], NO, 11);
        [self.body addArrangedSubview:heading];
        NSView *network = SCDeviceQRGuideRow(@"wifi",
            @"For company networks where mDNS is restricted; phone and Mac must be reachable.", @"WiFi.network");
        NSView *networkRow = [[NSView alloc] init];
        networkRow.translatesAutoresizingMaskIntoConstraints = NO;
        [networkRow addSubview:network];
        [self.body addArrangedSubview:networkRow];
        [NSLayoutConstraint activateConstraints:@[
            [networkRow.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
            [network.leadingAnchor constraintEqualToAnchor:networkRow.leadingAnchor constant:33],
            [network.trailingAnchor constraintEqualToAnchor:networkRow.trailingAnchor],
            [network.topAnchor constraintEqualToAnchor:networkRow.topAnchor],
            [network.bottomAnchor constraintEqualToAnchor:networkRow.bottomAnchor],
        ]];

        SCDeviceButton *download = [SCDeviceButton buttonWithTitle:@"Open download page"
            target:self action:@selector(downloadCompanion:)];
        download.identifier = @"WiFi.companionInstaller";
        self.companyDownload = download;
        download.toolTip = SCCompanionDownloadPage;
        download.enabled = !self.busy;
        download.font = [NSFont systemFontOfSize:12];
        download.translatesAutoresizingMaskIntoConstraints = NO;
        [download.heightAnchor constraintEqualToConstant:28].active = YES;
        [download.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
        NSView *install = SCWiFiStep(1, @"Install Anmir Connect App; skip if installed",
            @"WiFi.companionInstall", download);
        NSView *helper = SCWiFiStep(2, @"On your phone, open the app and tap Start helper",
            @"WiFi.companionGuide", nil);
        NSView *phone = SCWiFiStep(3, @"Wireless debugging › Pair device with QR code",
            @"WiFi.phonePath", nil);
        NSStackView *steps = SCDeviceStack(@[install, helper, phone], YES, 3);
        SCWiFiPanel *panel = [[SCWiFiPanel alloc] init];
        panel.identifier = @"WiFi.companySteps";
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        [panel addSubview:steps];
        [self.body addArrangedSubview:panel];
        [NSLayoutConstraint activateConstraints:@[
            [panel.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
            [steps.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
            [steps.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
            [steps.topAnchor constraintEqualToAnchor:panel.topAnchor constant:10],
            [steps.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-10],
            [install.widthAnchor constraintEqualToAnchor:steps.widthAnchor],
            [helper.widthAnchor constraintEqualToAnchor:steps.widthAnchor],
            [phone.widthAnchor constraintEqualToAnchor:steps.widthAnchor],
        ]];
        NSArray *addresses = SCDeviceRelayAddresses();
        if (addresses.count > 1) {
            NSPopUpButton *interfaces = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            [interfaces addItemsWithTitles:addresses];
            [interfaces selectItemWithTitle:self.relayHost];
            interfaces.target = self;
            interfaces.action = @selector(selectRelayHost:);
            interfaces.enabled = !self.busy;
            SCBind(interfaces, @"accessibilityLabel", @"Mac network address");
            [self.body addArrangedSubview:interfaces];
        }
        [self.body setCustomSpacing:16 afterView:panel];
    } else {
        NSTextField *title = SCDeviceLocalizedLabel(@"Pair with QR code", 17, NSFontWeightSemibold, NO);
        if (self.helpShown) {
            [self.body addArrangedSubview:title];
        } else {
            NSButton *networkMode = [self link:@"Pairing stuck on a company network? Try this option"
                action:@selector(useCompanyNetwork:)];
            networkMode.identifier = @"WiFi.companyNetwork";
            self.companyControl = networkMode;
            networkMode.enabled = !self.busy;
            [self.body addArrangedSubview:SCDeviceStack(@[title, networkMode], NO, 18)];
        }
        NSView *network = SCDeviceQRGuideRow(@"wifi",
            @"Phone and Mac: same Wi-Fi, or a reachable company LAN.", @"WiFi.network");
        NSView *phone = SCDeviceQRGuideRow(@"iphone",
            @"On your phone: Settings › Developer options › Wireless debugging › Pair device with QR code",
            @"WiFi.phonePath");
        [self.body addArrangedSubview:network];
        [self.body addArrangedSubview:phone];
        [NSLayoutConstraint activateConstraints:@[
            [network.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
            [phone.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
        ]];
        [self.body setCustomSpacing:16 afterView:phone];
    }

    SCDeviceQRImageView *code = [[SCDeviceQRImageView alloc] init];
    code.identifier = @"WiFi.qrCode";
    code.image = self.qrPairing.image;
    code.alphaValue = self.repairing || self.repairFailed ? .15 : 1;
    code.imageScaling = NSImageScaleProportionallyUpOrDown;
    code.translatesAutoresizingMaskIntoConstraints = NO;
    SCBind(code, @"accessibilityLabel", @"Scan with Android Wireless debugging");
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSBox *qrFrame = [[NSBox alloc] init];
    qrFrame.boxType = NSBoxCustom;
    qrFrame.transparent = NO;
    qrFrame.borderWidth = 1;
    qrFrame.borderColor = NSColor.separatorColor;
    qrFrame.fillColor = NSColor.whiteColor;
    qrFrame.cornerRadius = 8;
    qrFrame.contentViewMargins = NSZeroSize;
    qrFrame.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:qrFrame];
    [qrFrame.contentView addSubview:code];
    [self.body addArrangedSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
        [row.heightAnchor constraintEqualToConstant:184],
        [qrFrame.widthAnchor constraintEqualToConstant:184],
        [qrFrame.heightAnchor constraintEqualToConstant:184],
        [qrFrame.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
        [qrFrame.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [code.widthAnchor constraintEqualToConstant:180],
        [code.heightAnchor constraintEqualToConstant:180],
        [code.centerXAnchor constraintEqualToAnchor:qrFrame.centerXAnchor],
        [code.centerYAnchor constraintEqualToAnchor:qrFrame.centerYAnchor],
    ]];
    self.message = [NSTextField wrappingLabelWithString:@""];
    self.message.identifier = @"WiFi.qrStatus";
    self.message.font = [NSFont systemFontOfSize:11.5];
    self.message.alignment = NSTextAlignmentCenter;
    self.message.maximumNumberOfLines = 2;
    self.message.translatesAutoresizingMaskIntoConstraints = NO;
    [self.body addArrangedSubview:self.message];
    [self.message.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;
    NSString *status = self.repairing ? @"Restarting connection service…"
        : self.repairFailed ? @"Could not restart connection service. Try again."
        : !self.qrPairing.image ? @"Could not create a QR code. Use pairing code instead."
        : self.companionMode ? @"Scan with your phone's system scanner and keep this window open."
        : self.helpShown ? @"" : @"Use the phone’s system pairing scanner, not Camera or other scanners.";
    [self setMessage:status error:self.repairFailed || (!self.qrPairing.image && !self.repairing)];
    if (!self.companionMode && self.helpShown) { [self buildHelp]; }

    self.modeButton = [self link:@"Use pairing code" action:@selector(usePairingCode:)];
    self.qrRefreshButton = [SCDeviceButton buttonWithTitle:@"Refresh QR code" target:self action:@selector(useQRCode:)];
    self.qrRefreshButton.identifier = @"WiFi.refreshQR";
    SCDeviceButton *cancel = [SCDeviceButton buttonWithTitle:self.repairing ? @"Close" : @"Cancel"
        target:self action:@selector(cancel:)];
    for (SCDeviceButton *button in @[self.qrRefreshButton, cancel]) {
        button.font = [NSFont systemFontOfSize:12];
        button.bezelStyle = NSBezelStyleRounded;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button.heightAnchor constraintEqualToConstant:28].active = YES;
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
    }
    cancel.keyEquivalent = @"\033";
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:separator];
    for (NSView *view in @[self.modeButton, self.qrRefreshButton, cancel]) { [content addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.modeButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [self.modeButton.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [cancel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [self.qrRefreshButton.trailingAnchor constraintEqualToAnchor:cancel.leadingAnchor constant:-10],
        [self.qrRefreshButton.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [separator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [separator.bottomAnchor constraintEqualToAnchor:cancel.topAnchor constant:-12],
        [self.body.bottomAnchor constraintEqualToAnchor:separator.topAnchor constant:-16],
        [self.modeButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.qrRefreshButton.leadingAnchor constant:-16],
    ]];
    // Let wrapped instructions and optional interfaces determine the height.
    // Equal bottom spacing avoids a large empty area above the footer.
    [self.window setContentSize:NSMakeSize(520, content.fittingSize.height)];
    [self updateEnabled];
}

- (void)useQRCode:(id)sender {
    (void)sender;
    if (self.busy) { return; }
    [self dismissRepairConfirmation];
    ++self.generation;
    [self.scan cancel];
    [self.relay stop];
    self.relay = nil;
    self.relayServices = @[];
    self.mode = SCDeviceWiFiQRCode;
    self.qrFailed = self.addressRequired = NO;
    self.helpShown = self.repairFailed = NO;
    self.helpDeadline = [NSDate dateWithTimeIntervalSinceNow:15];
    [self.connection cancel];
    self.scanCount = 0;
    self.targetHost = nil;
    self.qrPairing = [[SCDeviceQRPairing alloc] init];
    if (self.companionMode) {
        self.relayHost = self.relayHost ?: SCDeviceRelayAddresses().firstObject;
        self.relay = [SCDeviceRelay listenOnHost:self.relayHost error:nil];
        if (self.relay) {
            self.qrPairing = [[SCDeviceQRPairing alloc] initWithServiceName:self.relay.serviceName];
            NSUInteger generation = self.generation;
            __weak SCDeviceWiFiController *weakSelf = self;
            self.relay.received = ^(NSArray<SCDeviceService *> *services) {
                SCDeviceWiFiController *controller = weakSelf;
                if (!controller.window.visible || controller.generation != generation || controller.qrFailed) { return; }
                NSString *host = services.firstObject.host;
                if (controller.targetHost.length && ![host isEqualToString:controller.targetHost]) { return; }
                controller.relayServices = services;
                [controller.connection updateServices:[services arrayByAddingObjectsFromArray:controller.services]];
                if (!controller.window.visible || controller.busy || controller.paired) { return; }
                SCDeviceService *pairing = [controller.qrPairing serviceIn:services];
                if (pairing) {
                    [controller pairEndpoint:pairing.endpoint code:controller.qrPairing.password name:nil];
                }
            };
        } else {
            self.qrPairing = nil;
            self.qrFailed = YES;
        }
    }
    self.qrDeadline = [NSDate dateWithTimeIntervalSinceNow:self.companionMode ? SCDeviceRelayLifetime : 120];
    self.services = @[];
    [self build];
    if (self.companionMode && !self.relay) {
        [self setMessage:@"Could not start the phone callback. Check the Mac network connection." error:YES];
    }
    [self discover];
}

- (void)confirmRepair:(id)sender {
    (void)sender;
    if (!self.window.visible || self.busy || self.repairAlert) { return; }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = SCLocalized(@"Restart connection service?");
    alert.informativeText = SCLocalized(@"This will restart the ADB service on your Mac. Other mirroring and debugging sessions, including Android Studio, may be interrupted.");
    [alert addButtonWithTitle:SCLocalized(@"Restart and fix")];
    [alert addButtonWithTitle:SCLocalized(@"Cancel")];
    self.repairAlert = alert;
    NSUInteger generation = self.generation;
    __weak NSAlert *weakAlert = alert;
    __weak SCDeviceWiFiController *weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        SCDeviceWiFiController *controller = weakSelf;
        if (!controller || controller.repairAlert != weakAlert) { return; }
        controller.repairAlert = nil;
        if (response == NSAlertFirstButtonReturn && controller.window.visible
                && controller.generation == generation && !controller.busy) {
            [controller performRepair];
        }
    }];
}

- (void)performRepair {
    if (!self.window.visible || self.busy) { return; }
    SCDeviceRecovery *recovery = [[SCDeviceRecovery alloc] initWithExecutable:self.executable];
    NSUInteger generation = self.generation + 1;
    __weak SCDeviceWiFiController *weakSelf = self;
    BOOL started = [recovery start:^(SCDeviceRecoveryResult result) {
        SCDeviceWiFiController *controller = weakSelf;
        if (!controller) { return; }
        controller.recovery = nil;
        controller.repairing = NO;
        if (!controller.window.visible) { return; }
        if (controller.generation != generation) {
            // The window was closed and reopened while the shared service was
            // restarting. A successful recovery gets a fresh QR; a failure
            // must remain visible instead of implying that service recovered.
            if (controller.qrMode && !controller.paired && !controller.connection.busy) {
                if (result == SCDeviceRecoverySuccess) {
                    [controller useQRCode:nil];
                    [controller setMessage:@"Connection service restarted. Scan the new QR code." error:NO];
                } else {
                    controller.repairFailed = controller.qrFailed = controller.helpShown = YES;
                    [controller build];
                }
            }
            return;
        }
        if (result == SCDeviceRecoverySuccess) {
            [controller useQRCode:nil];
            [controller setMessage:@"Connection service restarted. Scan the new QR code." error:NO];
        } else {
            controller.repairFailed = controller.qrFailed = controller.helpShown = YES;
            [controller build];
        }
    }];
    if (!started) {
        [self setMessage:@"Another connection repair is already in progress." error:YES];
        return;
    }
    self.recovery = recovery;
    self.repairing = self.helpShown = YES;
    self.repairFailed = NO;
    ++self.generation;
    [self.scan cancel]; self.scan = nil;
    [self.connection cancel];
    [self.relay stop]; self.relay = nil;
    self.relayServices = @[];
    [self build];
}

- (void)useCompanyNetwork:(id)sender {
    (void)sender;
    if (self.busy) { return; }
    self.companionMode = !self.companionMode;
    [self useQRCode:nil];
}

- (void)selectRelayHost:(NSPopUpButton *)sender {
    if (self.busy) { return; }
    self.relayHost = sender.titleOfSelectedItem;
    [self useQRCode:nil];
}

- (void)downloadCompanion:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:SCCompanionDownloadPage]];
}

- (void)usePairingCode:(id)sender {
    (void)sender;
    if (self.busy) { return; }
    [self dismissRepairConfirmation];
    ++self.generation;
    [self.scan cancel];
    [self.relay stop];
    self.relay = nil;
    self.relayServices = @[];
    self.companionMode = NO;
    self.mode = SCDeviceWiFiPairingCode;
    [self.connection cancel];
    self.qrPairing = nil;
    self.scanCount = 0;
    self.choices = @[];
    self.selected = nil;
    self.addressRequired = NO;
    [self build];
    [self.window makeFirstResponder:self.code.textField];
    [self discover];
}

- (void)buildDeviceChoice {
    if (self.choices.count > 1) {
        NSPopUpButton *picker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        for (SCDeviceService *service in self.choices) {
            [picker addItemWithTitle:@""];
            SCBindFormat(picker.lastItem, @"title", service.pairing ? @"%@ · Pairing" : @"%@ · Paired", @[service.host]);
        }
        [picker selectItemAtIndex:MAX(0, (NSInteger)[self.choices indexOfObjectIdenticalTo:self.selected])];
        picker.target = self;
        picker.action = @selector(selectDevice:);
        picker.enabled = !self.busy;
        SCBind(picker, @"accessibilityLabel", @"Wi-Fi device");
        [self.body addArrangedSubview:picker];
        return;
    }
    NSImageView *icon = [NSImageView imageViewWithImage:SCDeviceSymbol(@"iphone")];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.contentTintColor = NSColor.secondaryLabelColor;
    [icon.widthAnchor constraintEqualToConstant:24].active = YES;
    [icon.heightAnchor constraintEqualToConstant:32].active = YES;
    NSString *title = self.selected ? @"Android device" : @"Looking for devices";
    NSString *subtitle = self.selected ? self.selected.host : @"Open Pairing code on your device.";
    NSStackView *labels = SCDeviceStack(@[
        SCDeviceLocalizedLabel(title, 13, NSFontWeightMedium, NO),
        self.selected ? SCDeviceLabel(subtitle, 12, NSFontWeightRegular, YES) : SCDeviceLocalizedLabel(subtitle, 12, NSFontWeightRegular, YES)], YES, 4);
    [self.body addArrangedSubview:SCDeviceStack(@[icon, labels], NO, 14)];
}

- (void)buildAddressFields {
    NSString *oldAddress = self.address.stringValue ?: self.targetHost ?: @"";
    NSString *oldPort = self.port.stringValue ?: @"";
    self.address = [self field:@"192.168.1.42" identifier:@"IP address"];
    self.port = [self field:@"37123" identifier:@"Port"];
    self.address.stringValue = oldAddress;
    self.port.stringValue = oldPort;
    self.address.enabled = self.port.enabled = !self.busy;
    NSStackView *left = SCDeviceStack(@[SCDeviceLocalizedLabel(@"IP address", 12, NSFontWeightRegular, NO), self.address], YES, 5);
    NSStackView *right = SCDeviceStack(@[SCDeviceLocalizedLabel(@"Port", 12, NSFontWeightRegular, NO), self.port], YES, 5);
    NSStackView *row = SCDeviceStack(@[left, right], NO, 12);
    [self.body addArrangedSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
        [left.widthAnchor constraintEqualToAnchor:row.widthAnchor constant:-110],
        [right.widthAnchor constraintEqualToConstant:98],
        [self.address.widthAnchor constraintEqualToAnchor:left.widthAnchor],
        [self.port.widthAnchor constraintEqualToAnchor:right.widthAnchor],
    ]];
}

- (void)presentQRCodeFrom:(NSWindow *)parent {
    if ((!self.qrMode || self.qrFailed || self.paired) && !self.repairing) {
        if (self.window.visible) {
            [self useQRCode:nil];
        } else {
            // Create the relay only after presentFrom advances the session
            // generation, so its callback remains valid in the new window.
            self.mode = SCDeviceWiFiQRCode;
            self.qrPairing = nil;
            [self.connection cancel];
        }
    }
    [self presentFrom:parent];
}

- (void)presentFrom:(NSWindow *)parent {
    if (self.window.visible) { [self.window makeKeyAndOrderFront:nil]; return; }
    ++self.generation;
    if (self.qrMode && !self.paired && !self.repairing) {
        if (!self.qrPairing || self.qrDeadline.timeIntervalSinceNow <= 0) {
            [self useQRCode:nil];
        } else if (!self.helpShown) {
            self.helpDeadline = [NSDate dateWithTimeIntervalSinceNow:15];
        }
    }
    NSRect frame = parent.frame;
    [self.window setFrameOrigin:NSMakePoint(NSMidX(frame) - self.window.frame.size.width / 2,
        NSMidY(frame) - self.window.frame.size.height / 2)];
    [parent addChildWindow:self.window ordered:NSWindowAbove];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.code.textField];
    __weak SCDeviceWiFiController *weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
        (void)timer; [weakSelf discover];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self discover];
}

- (void)setMessage:(NSString *)message error:(BOOL)error {
    self.message.hidden = !message.length;
    SCBind(self.message, @"stringValue", message);
    self.message.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    SCBind(self.message, @"accessibilityValue", message);
    if (self.qrMode && self.qrRefreshButton.superview) {
        [self.window setContentSize:NSMakeSize(520, self.window.contentView.fittingSize.height)];
    }
}

- (void)discover {
    if (!self.window.visible || self.repairing) { return; }
    if (self.qrMode && !self.companionMode && !self.helpShown && !self.busy && !self.paired
            && !self.qrFailed && self.qrDeadline.timeIntervalSinceNow > 0
            && self.helpDeadline.timeIntervalSinceNow <= 0) {
        self.helpShown = YES;
        [self build];
    }
    if (self.scan.running) { return; }
    if (self.qrMode && !self.busy && !self.paired) {
        if (self.qrFailed) { return; }
        if (self.qrDeadline.timeIntervalSinceNow <= 0) {
            [self.relay stop];
            [self setMessage:@"QR code expired. Choose New QR code to try again." error:NO];
            return;
        }
    }
    NSUInteger generation = self.generation;
    __weak SCDeviceWiFiController *weakSelf = self;
    self.scan = [SCDeviceCommand run:self.executable arguments:@[@"mdns", @"services"] input:nil timeout:3
        completion:^(NSString *output, int status) {
        SCDeviceWiFiController *controller = weakSelf;
        if (!controller.window.visible || generation != controller.generation) { return; }
        controller.services = status ? @[] : [SCDeviceService parse:output];
        ++controller.scanCount;
        [controller.connection updateServices:[(controller.relayServices ?: @[])
            arrayByAddingObjectsFromArray:controller.services]];
        if (!controller.window.visible) { return; }
        if (controller.busy || controller.manual || controller.paired) { return; }
        if (controller.qrMode) {
            if (controller.qrDeadline.timeIntervalSinceNow <= 0) { return; }
            SCDeviceService *service = [controller.qrPairing serviceIn:controller.services];
            if (service) {
                [controller pairEndpoint:service.endpoint code:controller.qrPairing.password name:nil];
            } else if (status) {
                [controller setMessage:@"Phone not connecting? Check the network or use pairing code." error:NO];
            }
            return;
        }
        // This is explicitly the pairing-code flow. A connect advertisement
        // must not turn it into a different form or remove a code being typed.
        NSMutableArray *available = [NSMutableArray array];
        NSMutableSet *endpoints = [NSMutableSet set];
        for (SCDeviceService *service in controller.services) {
            if (service.pairing && ![endpoints containsObject:service.endpoint]) {
                [available addObject:service];
                [endpoints addObject:service.endpoint];
            }
        }
        NSArray *choices = [available sortedArrayUsingComparator:^NSComparisonResult(SCDeviceService *a, SCDeviceService *b) {
            if (a.pairing != b.pairing) { return a.pairing ? NSOrderedAscending : NSOrderedDescending; }
            return [a.endpoint compare:b.endpoint];
        }];
        NSString *oldEndpoint = controller.selected.endpoint;
        SCDeviceService *selected = nil;
        for (SCDeviceService *service in choices) {
            if ([service.endpoint isEqualToString:oldEndpoint]) { selected = service; break; }
        }
        selected = selected ?: choices.firstObject;
        BOOL changed = ![selected.endpoint ?: @"" isEqualToString:oldEndpoint ?: @""]
            || choices.count != controller.choices.count;
        controller.choices = choices;
        controller.selected = selected;
        BOOL fallback = !choices.count && controller.scanCount >= 2;
        if (changed || (fallback && !controller.addressRequired)) {
            NSString *code = controller.code.stringValue;
            BOOL enteringAddress = controller.address.stringValue.length || controller.port.stringValue.length
                || controller.address.textField.currentEditor || controller.port.textField.currentEditor;
            controller.addressRequired = fallback || (controller.addressRequired && enteringAddress);
            [controller build];
            controller.code.stringValue = code ?: @"";
            [controller updateEnabled];
            if (fallback) { [controller setMessage:@"Discovery unavailable. Enter the pairing address." error:NO]; }
        }
    }];
}

- (void)selectDevice:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem < (NSInteger)self.choices.count) {
        NSString *code = self.code.stringValue;
        self.selected = self.choices[sender.indexOfSelectedItem];
        [self build];
        self.code.stringValue = code ?: @"";
        [self updateEnabled];
    }
}

- (void)updateEnabled {
    BOOL endpoint = self.manual || self.addressRequired || self.paired
        ? SCDeviceEndpoint(self.address.stringValue, self.port.stringValue) != nil : self.selected != nil;
    BOOL needsCode = !self.manual && !self.paired && (!self.selected || self.selected.pairing);
    self.connectButton.enabled = !self.busy && endpoint && (!needsCode || SCDevicePairingCodeValid(self.code.stringValue));
    SCBind(self.connectButton, @"title", self.busy ? @"Connecting…" : @"Connect");
    self.code.enabled = self.address.enabled = self.port.enabled = !self.busy;
    self.modeButton.enabled = !self.busy;
    self.qrRefreshButton.enabled = !self.busy;
    self.companyControl.enabled = self.companyDownload.enabled = !self.busy;
    self.companyHelp.enabled = self.repairHelp.enabled = !self.busy;
    self.companyHelp.alphaValue = self.repairHelp.alphaValue = self.busy ? .45 : 1;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    [self setMessage:@"" error:NO];
    [self updateEnabled];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    NSString *value = field.stringValue;
    if (!value.length || self.busy) { return; }
    if (field == self.code.textField && !SCDevicePairingCodeValid(value)) {
        [self setMessage:@"Enter the 6-digit pairing code." error:YES];
    } else if (field == self.port.textField && !SCDeviceEndpoint(@"127.0.0.1", value)) {
        [self setMessage:@"Use a port from 1 to 65535." error:YES];
    } else if (field == self.address.textField && !SCDeviceEndpoint(value, @"1")) {
        [self setMessage:@"Enter a valid IP address." error:YES];
    }
}

- (void)manual:(id)sender {
    (void)sender;
    self.mode = SCDeviceWiFiManual;
    [self.connection cancel];
    self.code.stringValue = @"";
    [self build];
    [self.window makeFirstResponder:self.address.textField];
}

- (void)back:(id)sender {
    (void)sender;
    self.mode = SCDeviceWiFiPairingCode;
    self.address = self.port = nil;
    [self build];
    [self.window makeFirstResponder:self.code.textField];
}

- (void)connect:(id)sender {
    (void)sender;
    if (!self.connectButton.enabled) { return; }
    NSString *endpoint = self.manual || self.addressRequired || self.paired
        ? SCDeviceEndpoint(self.address.stringValue, self.port.stringValue) : self.selected.endpoint;
    if (self.manual || self.paired || (!self.selected.pairing && !self.addressRequired)) {
        [self.connection connectEndpoint:endpoint];
        return;
    }
    [self pairEndpoint:endpoint code:self.code.stringValue name:self.selected.name];
}

- (void)pairEndpoint:(NSString *)endpoint code:(NSString *)code name:(NSString *)name {
    self.targetHost = SCDeviceHost(endpoint);
    [self.connection updateServices:[(self.relayServices ?: @[]) arrayByAddingObjectsFromArray:self.services]];
    [self.connection pairEndpoint:endpoint secret:code serviceName:name requireGUID:self.qrMode];
}

- (void)connectionFallback:(NSString *)message {
    self.addressRequired = YES;
    self.address = self.port = nil;
    [self build];
    [self setMessage:message error:NO];
    [self.window makeFirstResponder:self.port.textField];
}

- (void)cancel:(id)sender { (void)sender; [self close]; }

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    ++self.generation;
    [self dismissRepairConfirmation];
    [self.timer invalidate];
    self.timer = nil;
    [self.scan cancel];
    [self.relay stop];
    self.relay = nil;
    self.relayServices = @[];
    [self.connection cancel];
    self.code.stringValue = @"";
    self.qrPairing = nil;
    NSWindow *parent = self.window.parentWindow;
    [parent removeChildWindow:self.window];
    // Closing a child window may leave the active app without a key window.
    // Restore the manager only after close completes, and never take focus
    // from a mirror (or another app) that became active in the meantime.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (parent.visible && NSApp.active && !NSApp.keyWindow) {
            [parent makeKeyWindow];
        }
    });
}
@end
