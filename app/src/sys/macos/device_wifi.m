#import "device_wifi.h"
#import "localization.h"
#import "device_support.h"
#import "device_ui.h"
#import "device_pairing.h"
#import "device_connection.h"

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
@property(nonatomic, strong) SCDeviceButton *connectButton;
@property(nonatomic, strong) SCDeviceButton *qrRefreshButton;
@property(nonatomic, strong) SCDeviceQRPairing *qrPairing;
@property(nonatomic, strong) NSDate *qrDeadline;
@property(nonatomic) SCDeviceWiFiMode mode;
@property(nonatomic, readonly) BOOL qrMode, manual, paired, busy;
@property(nonatomic) BOOL qrFailed;
@property(nonatomic) BOOL addressRequired;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger scanCount;
@property(nonatomic, copy) NSString *targetHost;
@end

@implementation SCDeviceWiFiController
- (BOOL)qrMode { return self.mode == SCDeviceWiFiQRCode; }
- (BOOL)manual { return self.mode == SCDeviceWiFiManual; }
- (BOOL)paired { return self.connection.paired; }
- (BOOL)busy { return self.connection.busy; }
- (void)connectionChanged {
    if (!self.window.visible) { return; }
    if (self.connection.phase == SCDeviceConnectionNeedsAddress) {
        [self connectionFallback:self.connection.message];
    } else if (self.connection.phase == SCDeviceConnectionReady) {
        if (self.mirror(self.connection.serial, self.connection.properties)) {
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
        SCBind(window, @"title", @"Wi-Fi connection");
        window.releasedWhenClosed = NO;
        window.backgroundColor = SCDeviceBackground();
        window.titlebarAppearsTransparent = YES;
        window.delegate = self;
        window.contentView = [[SCDeviceSurface alloc] initWithFrame:window.contentView.bounds];
        [self build];
    }
    return self;
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
        [self.body.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:28],
        [self.body.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-28],
        [self.body.topAnchor constraintEqualToAnchor:content.topAnchor constant:26],
    ]];
    self.qrRefreshButton = nil;
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

- (void)buildQRCode {
    NSView *content = self.window.contentView;
    [self.body addArrangedSubview:SCDeviceLocalizedLabel(@"Pair with QR code", 15, NSFontWeightSemibold, NO)];
    NSTextField *path = SCDeviceLocalizedLabel(
        @"Settings › Developer options › Wireless debugging", 11, NSFontWeightRegular, YES);
    NSTextField *help = SCDeviceLocalizedLabel(
        @"Tap “Pair device with QR code” to scan.", 12, NSFontWeightRegular, NO);
    NSStackView *instructions = SCDeviceStack(@[path, help], YES, 4);
    [self.body addArrangedSubview:instructions];
    [instructions.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;

    SCDeviceQRImageView *code = [[SCDeviceQRImageView alloc] init];
    code.image = self.qrPairing.image;
    code.imageScaling = NSImageScaleProportionallyUpOrDown;
    code.translatesAutoresizingMaskIntoConstraints = NO;
    SCBind(code, @"accessibilityLabel", @"Scan with Android Wireless debugging");
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:code];
    [self.body addArrangedSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.widthAnchor constraintEqualToAnchor:self.body.widthAnchor],
        [row.heightAnchor constraintEqualToConstant:240],
        [code.widthAnchor constraintEqualToConstant:224],
        [code.heightAnchor constraintEqualToConstant:224],
        [code.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
        [code.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    self.message = [NSTextField wrappingLabelWithString:@""];
    self.message.font = [NSFont systemFontOfSize:11];
    self.message.maximumNumberOfLines = 3;
    self.message.translatesAutoresizingMaskIntoConstraints = NO;
    [self.body addArrangedSubview:self.message];
    [self.message.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;
    [self setMessage:self.qrPairing.image ? @"Same Wi-Fi network. Waiting for your phone…"
        : @"Could not create a QR code. Use pairing code instead." error:!self.qrPairing.image];

    self.modeButton = [self link:@"Use pairing code" action:@selector(usePairingCode:)];
    self.qrRefreshButton = [self button:@"New QR code" action:@selector(useQRCode:) primary:YES];
    self.qrRefreshButton.primary = NO;
    SCDeviceButton *cancel = [self button:@"Cancel" action:@selector(cancel:) primary:NO];
    cancel.keyEquivalent = @"\033";
    for (NSView *view in @[self.modeButton, self.qrRefreshButton, cancel]) { [content addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.modeButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [self.modeButton.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
        [cancel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [cancel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-22],
        [self.qrRefreshButton.trailingAnchor constraintEqualToAnchor:cancel.leadingAnchor constant:-10],
        [self.qrRefreshButton.centerYAnchor constraintEqualToAnchor:cancel.centerYAnchor],
    ]];
    [self.window setContentSize:NSMakeSize(500, 450)];
    [self updateEnabled];
}

- (void)useQRCode:(id)sender {
    (void)sender;
    if (self.busy) { return; }
    ++self.generation;
    [self.scan cancel];
    self.mode = SCDeviceWiFiQRCode;
    self.qrFailed = self.addressRequired = NO;
    [self.connection cancel];
    self.scanCount = 0;
    self.targetHost = nil;
    self.qrPairing = [[SCDeviceQRPairing alloc] init];
    self.qrDeadline = [NSDate dateWithTimeIntervalSinceNow:120];
    self.services = @[];
    [self build];
    [self discover];
}

- (void)usePairingCode:(id)sender {
    (void)sender;
    if (self.busy) { return; }
    ++self.generation;
    [self.scan cancel];
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
    if (!self.qrMode || self.qrFailed || self.paired) { [self useQRCode:nil]; }
    [self presentFrom:parent];
}

- (void)presentFrom:(NSWindow *)parent {
    if (self.window.visible) { [self.window makeKeyAndOrderFront:nil]; return; }
    if (self.qrMode && !self.paired && !self.qrPairing) { [self useQRCode:nil]; }
    ++self.generation;
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
    SCBind(self.message, @"stringValue", message);
    self.message.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    SCBind(self.message, @"accessibilityValue", message);
}

- (void)discover {
    if (!self.window.visible || self.scan.running) { return; }
    if (self.qrMode && !self.busy && !self.paired) {
        if (self.qrFailed) { return; }
        if (self.qrDeadline.timeIntervalSinceNow <= 0) {
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
        [controller.connection updateServices:controller.services];
        if (!controller.window.visible) { return; }
        if (controller.busy || controller.manual || controller.paired) { return; }
        if (controller.qrMode) {
            if (controller.qrDeadline.timeIntervalSinceNow <= 0) { return; }
            SCDeviceService *service = [controller.qrPairing serviceIn:controller.services];
            if (service) {
                [controller pairEndpoint:service.endpoint code:controller.qrPairing.password name:nil];
            } else if (status || controller.scanCount >= 10) {
                [controller setMessage:@"Not connecting? Check Wi-Fi or use pairing code. Automatic discovery needs mDNS." error:NO];
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
    [self.connection updateServices:self.services];
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
    [self.timer invalidate];
    self.timer = nil;
    [self.scan cancel];
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
