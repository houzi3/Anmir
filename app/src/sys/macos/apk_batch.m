#import "apk_batch.h"

#import <AppKit/AppKit.h>
#import "apk_devices.h"
#import "device_support.h"
#import "device_ui.h"
#import "localization.h"
#import "settings.h"

static const CGFloat SCAPKBatchWindowWidth = 510;
static const CGFloat SCAPKBatchInset = 24;
static const CGFloat SCAPKBatchRowHeight = 52;
static const CGFloat SCAPKBatchRowSpacing = 8;

typedef NS_ENUM(NSUInteger, SCAPKBatchStatus) {
    SCAPKBatchQueued,
    SCAPKBatchInstalling,
    SCAPKBatchInstalled,
    SCAPKBatchFailed,
    SCAPKBatchCancelled,
};

@interface SCAPKBatchRow : NSBox
@property(nonatomic, strong) SCAPKTarget *originalTarget;
@property(nonatomic, strong) SCAPKTarget *target;
@property(nonatomic) SCAPKBatchStatus status;
@property(nonatomic, copy) NSString *failureKey;
@property(nonatomic, copy) NSString *failureOutput;
@property(nonatomic, strong) NSTextField *name;
@property(nonatomic, strong) NSTextField *transport;
@property(nonatomic, strong) NSTextField *result;
@property(nonatomic, strong) NSImageView *statusIcon;
@property(nonatomic, strong) SCDeviceIconButton *details;
- (instancetype)initWithTarget:(SCAPKTarget *)target index:(NSUInteger)index
    frame:(NSRect)frame owner:(id)owner action:(SEL)action;
- (void)refresh;
@end

@implementation SCAPKBatchRow
- (instancetype)initWithTarget:(SCAPKTarget *)target index:(NSUInteger)index
    frame:(NSRect)frame owner:(id)owner action:(SEL)action {
    self = [super initWithFrame:frame];
    if (!self) { return nil; }
    _originalTarget = target;
    _target = target;
    self.boxType = NSBoxCustom;
    self.titlePosition = NSNoTitle;
    self.contentViewMargins = NSZeroSize;
    self.borderColor = NSColor.separatorColor;
    self.borderWidth = 1;
    self.cornerRadius = 9;
    self.autoresizingMask = NSViewWidthSizable;

    NSView *content = self.contentView;
    _name = SCDeviceLabel(@"", 13, NSFontWeightMedium, NO);
    _transport = SCDeviceLabel(@"", 11, NSFontWeightRegular, YES);
    _result = SCDeviceLabel(@"", 11, NSFontWeightMedium, YES);
    _result.identifier = [NSString stringWithFormat:@"APKBatch.Status.%lu", (unsigned long)index];
    _statusIcon = [[NSImageView alloc] init];
    _statusIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _details = [SCDeviceIconButton buttonWithImage:SCDeviceSymbol(@"info.circle")
        target:owner action:action];
    _details.translatesAutoresizingMaskIntoConstraints = NO;
    _details.identifier = [NSString stringWithFormat:@"APKBatch.Details.%lu", (unsigned long)index];
    _details.tag = (NSInteger)index;
    SCBind(_details, @"toolTip", @"Installation details");

    NSStackView *device = SCDeviceStack(@[_name, _transport], YES, 3);
    NSStackView *outcome = SCDeviceStack(@[_statusIcon, _result, _details], NO, 7);
    for (NSTextField *label in @[_name, _transport]) {
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
            forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    for (NSView *view in @[device, outcome]) { [content addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [device.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [device.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [device.trailingAnchor constraintLessThanOrEqualToAnchor:outcome.leadingAnchor constant:-10],
        [outcome.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [outcome.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [_statusIcon.widthAnchor constraintEqualToConstant:14],
        [_statusIcon.heightAnchor constraintEqualToConstant:14],
        [_details.widthAnchor constraintEqualToConstant:24],
        [_details.heightAnchor constraintEqualToConstant:24],
    ]];
    [self refresh];
    return self;
}

- (void)refresh {
    NSString *model = [self.target.model isEqualToString:@"Android device"]
        ? SCLocalized(@"Android device") : self.target.model;
    NSString *nickname = SCSettingsDeviceNickname(self.target.identity);
    NSString *transport = SCLocalized(self.target.transport);
    self.name.stringValue = nickname ?: model;
    self.transport.stringValue = nickname
        ? [NSString stringWithFormat:@"%@ · %@", model, transport] : transport;
    self.name.toolTip = self.name.stringValue;
    self.transport.toolTip = self.transport.stringValue;

    NSString *label = nil;
    NSString *symbol = nil;
    NSColor *tint = NSColor.secondaryLabelColor;
    switch (self.status) {
        case SCAPKBatchQueued:
            label = @"Queued";
            symbol = @"clock";
            break;
        case SCAPKBatchInstalling:
            label = @"Installing…";
            symbol = @"arrow.down.circle";
            tint = SCDeviceBlue();
            break;
        case SCAPKBatchInstalled:
            label = @"Installed";
            symbol = @"checkmark.circle.fill";
            tint = NSColor.systemGreenColor;
            break;
        case SCAPKBatchFailed:
            label = @"Failed";
            symbol = @"exclamationmark.circle.fill";
            tint = NSColor.systemRedColor;
            break;
        case SCAPKBatchCancelled:
            label = @"Cancelled";
            symbol = @"minus.circle";
            break;
    }
    SCBind(self.result, @"stringValue", label);
    self.statusIcon.image = SCDeviceSymbol(symbol);
    self.statusIcon.contentTintColor = tint;
    self.details.hidden = self.status != SCAPKBatchFailed;
    self.result.toolTip = self.failureKey ? SCLocalized(self.failureKey) : self.failureOutput;
    SCBindFormat(self.details, @"accessibilityLabel", @"Details for %@", @[self.name.stringValue]);
}
@end

@interface SCAPKBatchList : NSView
@end

@implementation SCAPKBatchList
- (BOOL)isFlipped { return YES; }
@end

@interface SCAPKBatchController () <NSWindowDelegate>
@property(nonatomic, copy) NSString *apk;
@property(nonatomic, copy) NSString *adb;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, copy) NSArray<SCAPKBatchRow *> *rows;
@property(nonatomic, strong) NSTextField *summary;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) SCDeviceButton *cancelOrClose;
@property(nonatomic, strong) SCDeviceButton *retry;
@property(nonatomic, strong) NSAlert *detailsAlert;
@property(nonatomic, strong) SCAPKBatchRow *detailsRow;
@property(nonatomic, strong) SCDeviceCommand *command;
@property(nonatomic, strong) SCAPKDeviceDiscovery *discovery;
@property(nonatomic, copy) void (^completion)(void);
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL stopping;
@property(nonatomic) BOOL closed;
@end

@implementation SCAPKBatchController
- (instancetype)initWithAPK:(NSString *)apk adb:(NSString *)adb
    targets:(NSArray<SCAPKTarget *> *)targets completion:(void (^)(void))completion {
    self = [super init];
    if (!self) { return nil; }
    _apk = [apk copy];
    _adb = [adb copy];
    _completion = [completion copy];

    NSUInteger visibleRows = MIN(targets.count, 5);
    CGFloat rowStride = SCAPKBatchRowHeight + SCAPKBatchRowSpacing;
    CGFloat listWidth = SCAPKBatchWindowWidth - 2 * SCAPKBatchInset;
    CGFloat listHeight = MAX(0, visibleRows * rowStride - SCAPKBatchRowSpacing);
    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, SCAPKBatchWindowWidth, 182 + listHeight)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"Anmir";
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.titlebarAppearsTransparent = YES;
    _window.backgroundColor = SCDeviceBackground();
    _window.contentView = [[SCDeviceSurface alloc] initWithFrame:_window.contentView.bounds];
    NSView *content = _window.contentView;

    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"anmir-apk" withExtension:@"icns"];
    NSImage *fileIcon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
    NSImageView *icon = [NSImageView imageViewWithImage:fileIcon ?: SCDeviceSymbol(@"doc")];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *title = SCDeviceLocalizedLabel(@"Batch APK installation", 18,
        NSFontWeightSemibold, NO);
    NSTextField *filename = SCDeviceLabel(apk.lastPathComponent, 12, NSFontWeightRegular, YES);
    filename.toolTip = apk.lastPathComponent;
    _summary = SCDeviceLabel(@"", 12, NSFontWeightMedium, NO);
    _summary.identifier = @"APKBatch.Summary";
    _progress = [[NSProgressIndicator alloc] init];
    _progress.translatesAutoresizingMaskIntoConstraints = NO;
    _progress.style = NSProgressIndicatorStyleBar;
    _progress.indeterminate = NO;
    _progress.controlSize = NSControlSizeSmall;
    _progress.maxValue = targets.count;

    NSScrollView *scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 0, listWidth, listHeight)];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasVerticalScroller = targets.count > visibleRows;
    scroll.autohidesScrollers = YES;
    CGFloat documentWidth = scroll.contentSize.width;
    SCAPKBatchList *list = [[SCAPKBatchList alloc] initWithFrame:
        NSMakeRect(0, 0, documentWidth, MAX(0, targets.count * rowStride - SCAPKBatchRowSpacing))];
    list.autoresizingMask = NSViewWidthSizable;
    NSMutableArray<SCAPKBatchRow *> *rows = [NSMutableArray arrayWithCapacity:targets.count];
    for (NSUInteger index = 0; index < targets.count; ++index) {
        SCAPKBatchRow *row = [[SCAPKBatchRow alloc] initWithTarget:targets[index]
            index:index frame:NSMakeRect(0, index * rowStride, documentWidth, SCAPKBatchRowHeight)
            owner:self action:@selector(showDetails:)];
        [list addSubview:row];
        [rows addObject:row];
    }
    _rows = [rows copy];
    scroll.documentView = list;

    _cancelOrClose = [SCDeviceButton buttonWithTitle:@"Cancel"
        target:self action:@selector(cancelOrClose:)];
    _cancelOrClose.identifier = @"APKBatch.CancelOrClose";
    _cancelOrClose.keyEquivalent = @"\e";
    _retry = [SCDeviceButton buttonWithTitle:@"Retry failed" target:self action:@selector(retryFailed:)];
    _retry.identifier = @"APKBatch.RetryFailed";
    _retry.primary = YES;
    for (NSButton *button in @[_cancelOrClose, _retry]) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    }
    NSStackView *buttons = SCDeviceStack(@[_cancelOrClose, _retry], NO, 8);

    for (NSView *view in @[icon, title, filename, _summary, _progress, scroll, buttons]) {
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:SCAPKBatchInset],
        [icon.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [icon.widthAnchor constraintEqualToConstant:40],
        [icon.heightAnchor constraintEqualToConstant:40],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-SCAPKBatchInset],
        [title.topAnchor constraintEqualToAnchor:icon.topAnchor],
        [filename.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [filename.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [filename.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3],
        [_summary.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [_summary.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [_summary.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [_progress.leadingAnchor constraintEqualToAnchor:_summary.leadingAnchor],
        [_progress.trailingAnchor constraintEqualToAnchor:_summary.trailingAnchor],
        [_progress.topAnchor constraintEqualToAnchor:_summary.bottomAnchor constant:7],
        [_progress.heightAnchor constraintEqualToConstant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:_summary.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_summary.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_progress.bottomAnchor constant:12],
        [scroll.heightAnchor constraintEqualToConstant:listHeight],
        [buttons.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [_cancelOrClose.heightAnchor constraintEqualToConstant:32],
        [_cancelOrClose.widthAnchor constraintGreaterThanOrEqualToConstant:84],
        [_retry.heightAnchor constraintEqualToConstant:32],
        [_retry.widthAnchor constraintGreaterThanOrEqualToConstant:112],
    ]];
    [self refreshSummary];
    [_window center];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged:)
        name:SCLanguageChangedNotification object:nil];
    return self;
}

- (void)languageChanged:(NSNotification *)notification {
    (void)notification;
    for (SCAPKBatchRow *row in self.rows) { [row refresh]; }
    if (self.detailsAlert) {
        SCBindFormat(self.detailsAlert, @"messageText", @"Details for %@",
            @[self.detailsRow.name.stringValue]);
        [self.detailsAlert layout];
    }
}

- (void)show {
    if (self.closed) { return; }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    if (!self.started) {
        self.started = YES;
        [self installNext];
    }
}

- (void)refreshSummary {
    NSUInteger installed = 0, failed = 0, cancelled = 0;
    for (SCAPKBatchRow *row in self.rows) {
        if (row.status == SCAPKBatchInstalled) { ++installed; }
        else if (row.status == SCAPKBatchFailed) { ++failed; }
        else if (row.status == SCAPKBatchCancelled) { ++cancelled; }
    }
    NSUInteger completed = installed + failed + cancelled;
    BOOL busy = self.command || self.discovery;
    self.progress.doubleValue = completed;
    self.retry.hidden = busy || !failed;
    self.cancelOrClose.enabled = !self.stopping;
    SCBind(self.cancelOrClose, @"title", busy ? @"Cancel" : @"Close");
    self.cancelOrClose.primary = !busy && !failed;

    if (self.stopping) {
        SCBind(self.summary, @"stringValue", @"Cancelling…");
    } else if (self.discovery) {
        SCBind(self.summary, @"stringValue", @"Finding devices…");
    } else if (completed < self.rows.count) {
        SCBindFormat(self.summary, @"stringValue", @"%@ of %@ completed",
            @[@(completed).stringValue, @(self.rows.count).stringValue]);
    } else if (cancelled) {
        SCBindFormat(self.summary, @"stringValue", @"%@ installed · %@ failed · %@ cancelled",
            @[@(installed).stringValue, @(failed).stringValue, @(cancelled).stringValue]);
    } else {
        SCBindFormat(self.summary, @"stringValue", @"%@ installed · %@ failed",
            @[@(installed).stringValue, @(failed).stringValue]);
    }
}

- (void)installNext {
    for (SCAPKBatchRow *row in self.rows) {
        if (row.status != SCAPKBatchQueued) { continue; }
        SCAPKTarget *target = row.target;
        // Without an identity or transport ID, a wireless endpoint or emulator
        // slot could now belong to a different device.
        if (!target.identity.length && !target.transportID.length
                && ![target.transport isEqualToString:@"USB"]) {
            row.status = SCAPKBatchFailed;
            row.failureKey = @"Could not verify this device. Reconnect it and try again.";
            [row refresh];
            continue;
        }
        row.status = SCAPKBatchInstalling;
        [row refresh];
        [row scrollRectToVisible:row.bounds];
        [self verifyAndInstall:row];
        break;
    }
    [self refreshSummary];
}

- (void)verifyAndInstall:(SCAPKBatchRow *)row {
    SCAPKTarget *target = row.target;
    NSArray<NSString *> *selector = [target selectionArguments];
    NSArray<NSString *> *verification = target.identity.length
        ? @[@"shell", @"getprop"] : @[@"get-serialno"];
    __weak SCAPKBatchController *weakSelf = self;
    self.command = [SCDeviceCommand run:self.adb
        arguments:[selector arrayByAddingObjectsFromArray:verification] input:nil timeout:5
        completion:^(NSString *output, int status) {
            SCAPKBatchController *controller = weakSelf;
            if (!controller || controller.closed) { return; }
            controller.command = nil;
            if (controller.stopping) {
                [controller finishCancellation];
                return;
            }
            NSString *actual = target.identity.length
                ? SCDevicePhysicalIdentity(SCDeviceProperties(output))
                : [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSString *expected = target.identity ?: target.serial;
            if (status || ![expected isEqualToString:actual]) {
                row.status = SCAPKBatchFailed;
                row.failureKey = @"Could not verify this device. Reconnect it and try again.";
                [row refresh];
                [controller installNext];
                return;
            }
            [controller installRow:row selector:selector];
        }];
}

- (void)installRow:(SCAPKBatchRow *)row selector:(NSArray<NSString *> *)selector {
    NSArray<NSString *> *arguments = [selector arrayByAddingObjectsFromArray:
        @[@"install", @"-r", self.apk]];
    __weak SCAPKBatchController *weakSelf = self;
    self.command = [SCDeviceCommand run:self.adb arguments:arguments input:nil timeout:600
        completion:^(NSString *output, int status) {
            SCAPKBatchController *controller = weakSelf;
            if (!controller || controller.closed) { return; }
            controller.command = nil;
            if (controller.stopping) {
                [controller finishCancellation];
                return;
            }
            row.status = status ? SCAPKBatchFailed : SCAPKBatchInstalled;
            if (status) {
                NSString *message = [output stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
                row.failureOutput = message.length ? message : nil;
                row.failureKey = message.length ? nil : @"ADB did not return an error message.";
            }
            [row refresh];
            [controller installNext];
        }];
}

- (SCAPKTarget *)retryTargetFor:(SCAPKTarget *)original
    inTargets:(NSArray<SCAPKTarget *> *)targets {
    for (SCAPKTarget *candidate in targets) {
        if (original.identity.length) {
            if ([original.identity isEqualToString:candidate.identity]) { return candidate; }
            continue;
        }
        if (![original.serial isEqualToString:candidate.serial]
                || ![original.transport isEqualToString:candidate.transport]) {
            continue;
        }
        if ([original.transport isEqualToString:@"USB"]
                || (original.transportID.length
                    && [original.transportID isEqualToString:candidate.transportID])) {
            return candidate;
        }
    }
    return nil;
}

- (void)retryFailed:(id)sender {
    (void)sender;
    if (self.closed || self.command || self.discovery) { return; }
    SCAPKDeviceDiscovery *discovery = [[SCAPKDeviceDiscovery alloc] initWithADB:self.adb];
    self.discovery = discovery;
    __weak SCAPKDeviceDiscovery *weakDiscovery = discovery;
    __weak SCAPKBatchController *weakSelf = self;
    [discovery startWithCompletion:^(NSArray<SCAPKTarget *> *targets, int status) {
        SCAPKBatchController *controller = weakSelf;
        if (!controller || controller.closed || !controller.discovery
                || controller.discovery != weakDiscovery) { return; }
        controller.discovery = nil;
        for (SCAPKBatchRow *row in controller.rows) {
            if (row.status != SCAPKBatchFailed) { continue; }
            SCAPKTarget *target = status ? nil
                : [controller retryTargetFor:row.originalTarget inTargets:targets];
            row.failureOutput = nil;
            if (target) {
                row.target = target;
                row.status = SCAPKBatchQueued;
                row.failureKey = nil;
            } else {
                row.failureKey = @"This device is unavailable. Reconnect it and try again.";
            }
            [row refresh];
        }
        [controller installNext];
    }];
    [self refreshSummary];
}

- (void)finishCancellation {
    self.stopping = NO;
    for (SCAPKBatchRow *row in self.rows) {
        if (row.status == SCAPKBatchQueued || row.status == SCAPKBatchInstalling) {
            row.status = SCAPKBatchCancelled;
            [row refresh];
        }
    }
    [self refreshSummary];
}

- (void)cancelOrClose:(id)sender {
    (void)sender;
    if (self.discovery) {
        SCAPKDeviceDiscovery *discovery = self.discovery;
        self.discovery = nil;
        [discovery cancel];
        [self refreshSummary];
    } else if (self.command) {
        if (self.stopping) { return; }
        self.stopping = YES;
        [self.command cancel];
        [self refreshSummary];
    } else {
        [self.window close];
    }
}

- (void)showDetails:(NSButton *)sender {
    if (self.window.attachedSheet || sender.tag < 0
            || (NSUInteger)sender.tag >= self.rows.count) { return; }
    SCAPKBatchRow *row = self.rows[(NSUInteger)sender.tag];
    if (row.status != SCAPKBatchFailed) { return; }
    NSAlert *alert = [[NSAlert alloc] init];
    SCBindFormat(alert, @"messageText", @"Details for %@", @[row.name.stringValue]);
    if (row.failureOutput) {
        alert.informativeText = row.failureOutput;
    } else {
        SCBind(alert, @"informativeText", row.failureKey ?: @"ADB did not return an error message.");
    }
    NSButton *close = [alert addButtonWithTitle:SCLocalized(@"Close")];
    SCBind(close, @"title", @"Close");
    self.detailsAlert = alert;
    self.detailsRow = row;
    __weak SCAPKBatchController *weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        (void)response;
        weakSelf.detailsAlert = nil;
        weakSelf.detailsRow = nil;
    }];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    self.closed = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self name:SCLanguageChangedNotification object:nil];
    [self.discovery cancel];
    self.discovery = nil;
    [self.command cancel];
    self.command = nil;
    void (^completion)(void) = self.completion;
    self.completion = nil;
    if (completion) { completion(); }
}
@end
