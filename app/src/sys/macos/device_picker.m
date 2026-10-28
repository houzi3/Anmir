#include "device_picker.h"

#import <AppKit/AppKit.h>
#import "localization.h"
#import "settings_ui.h"
#import "updater.h"
#import "device_picker_ui.h"
#import "device_support.h"
#import "device_ui.h"
#import "device_wifi.h"
#import "device_reconnect.h"
#import "mirror_session.h"
#import "application_lifecycle.h"
#import "apk_installer.h"

#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL.h>
#include "adb/adb.h"
#include "adb/adb_parser.h"
#include "options.h"
#include "scrcpy.h"
#include "theme.h"
#include "device_info.h"
#include "util/log.h"

static NSString *currentDeviceSerial;
static __weak NSWindow *mirrorWindow;
static BOOL mirrorPresented;

static NSString *SCMirrorShownNotification(void) {
    return [SCMirrorHostBundleIdentifier() stringByAppendingString:@".MirrorShown"];
}

@interface SCDeviceHeaderView : NSTableHeaderView
@end
@implementation SCDeviceHeaderView
- (void)drawRect:(NSRect)dirtyRect {
    [SCDeviceBackground() setFill]; NSRectFill(dirtyRect);
    [[NSColor.labelColor colorWithAlphaComponent:0.035] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:7 yRadius:7] fill];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
    };
    for (NSUInteger i = 0; i < self.tableView.tableColumns.count; ++i) {
        NSRect rect = [self headerRectOfColumn:i];
        NSString *title = self.tableView.tableColumns[i].title;
        NSSize size = [title sizeWithAttributes:attributes];
        [title drawInRect:NSMakeRect(rect.origin.x + 14, (rect.size.height-size.height)/2,
            MAX(0, rect.size.width - 24), size.height) withAttributes:attributes];
    }
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface SCDeviceTableView : NSTableView
@end
@implementation SCDeviceTableView
- (void)drawGridInClipRect:(NSRect)clipRect {
    [[NSColor.labelColor colorWithAlphaComponent:0.075] setFill];
    CGFloat line = 1 / (self.window.backingScaleFactor ?: 1);
    for (NSInteger row = 0; row < self.numberOfRows; ++row) {
        NSRect divider = NSMakeRect(0, (row + 1) * self.rowHeight - line, self.bounds.size.width, line);
        if (NSIntersectsRect(divider, clipRect)) { NSRectFill(divider); }
    }
}
@end

@interface SCDeviceDetailCopyButton : SCDeviceIconButton
@property(nonatomic, weak) NSTextField *valueLabel;
@end
@implementation SCDeviceDetailCopyButton
- (void)copyValue:(id)sender {
    (void)sender;
    if (!self.enabled || !self.valueLabel.stringValue.length) { return; }
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.valueLabel.stringValue forType:NSPasteboardTypeString];
    NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey:SCLocalized(@"Copied"),
            NSAccessibilityPriorityKey:@(NSAccessibilityPriorityMedium)});
}
@end

static NSString *sc_device_picker_string(const char *value) {
    return value ? ([NSString stringWithUTF8String:value] ?: @"Unknown") : @"Unknown";
}

@interface SCDeviceEntry : NSObject
@property(nonatomic, copy) NSString *serial, *name, *state, *system;
@property(nonatomic) enum sc_adb_device_type transportType;
@property(nonatomic, readonly) NSString *transport;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic) BOOL fallbackName;
@property(nonatomic, readonly) NSString *displayName;
@end
@implementation SCDeviceEntry
- (NSString *)displayName { return self.fallbackName ? SCLocalized(@"Android device") : self.name; }
- (BOOL)ready { return [self.state isEqualToString:@"device"]; }
- (NSString *)transport {
    switch (self.transportType) {
        case SC_ADB_DEVICE_TYPE_USB: return @"USB";
        case SC_ADB_DEVICE_TYPE_TCPIP: return @"Wi-Fi";
        case SC_ADB_DEVICE_TYPE_EMULATOR: return SCLocalized(@"Emulator");
    }
    return SCLocalized(@"Unknown");
}
@end

static NSArray<SCDeviceEntry *> *sc_device_picker_entries(const struct sc_vec_adb_devices *devices) {
    NSMutableArray *entries = [NSMutableArray array];
    for (size_t i = 0; i < devices->size; ++i) {
        const struct sc_adb_device *device = &devices->data[i];
        SCDeviceEntry *entry = [[SCDeviceEntry alloc] init];
        entry.serial = sc_device_picker_string(device->serial);
        entry.state = sc_device_picker_string(device->state);
        entry.transportType = sc_adb_device_get_type(device->serial);
        entry.fallbackName = !device->model;
        entry.name = device->model ? [sc_device_picker_string(device->model)
            stringByReplacingOccurrencesOfString:@"_" withString:@" "] : @"Android device";
        entry.system = @"—";
        [entries addObject:entry];
    }
    return entries;
}

@interface SCDeviceManager : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSToolbarDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTableView *table;
@property(nonatomic, strong) NSButton *scanButton;
@property(nonatomic, strong) NSScrollView *scroll;
@property(nonatomic, strong) NSStackView *emptyView, *steps;
@property(nonatomic, strong) NSSegmentedControl *method;
@property(nonatomic, strong) NSTextField *emptyTitle, *emptyHelp, *footer;
@property(nonatomic, strong) NSImageView *footerDot;
@property(nonatomic, copy) NSArray<SCDeviceEntry *> *devices;
@property(nonatomic, copy) NSArray<SCDeviceEntry *> *transports;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTask *> *sessions;
@property(nonatomic, strong) NSMutableDictionary<NSString *, SCMirrorPreparation *> *preparations;
@property(nonatomic, strong) NSMutableSet<NSString *> *shownSessions;
@property(nonatomic, copy) NSArray<SCMirrorSession *> *runningMirrors;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *failures;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *metadata;
@property(nonatomic, strong) NSMutableDictionary<NSString *, SCDeviceCommand *> *queries;
@property(nonatomic, copy) NSString *executable;
@property(nonatomic, strong) SCDeviceWatcher *watcher;
@property(nonatomic, strong) SCDeviceCommand *snapshot, *detailQuery;
@property(nonatomic, strong) NSTimer *fallbackTimer;
@property(nonatomic, strong) SCDeviceWiFiController *wifi;
@property(nonatomic, strong) SCDeviceReconnect *reconnect;
@property(nonatomic, strong) NSPopover *details;
@property(nonatomic) BOOL listed, refreshPending, scheduled;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger pendingPreparations;
- (void)refresh:(id)sender;
- (void)show;
- (void)updateSummary:(BOOL)listed;
@end

@implementation SCDeviceManager
- (instancetype)init {
    self = [super init];
    if (self) {
        _devices = @[];
        _transports = @[];
        _sessions = [NSMutableDictionary dictionary];
        _preparations = [NSMutableDictionary dictionary];
        _shownSessions = [NSMutableSet set];
        [NSDistributedNotificationCenter.defaultCenter addObserver:self
            selector:@selector(mirrorShown:) name:SCMirrorShownNotification() object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
            selector:@selector(mirrorExited:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
        _failures = [NSMutableDictionary dictionary];
        _metadata = [NSMutableDictionary dictionary];
        _queries = [NSMutableDictionary dictionary];
        _executable = SCDeviceExecutable(sc_adb_get_executable());
        _watcher = [[SCDeviceWatcher alloc] initWithExecutable:_executable];
        __weak SCDeviceManager *weakSelf = self;
        _reconnect = [[SCDeviceReconnect alloc] initWithExecutable:_executable defaults:NSUserDefaults.standardUserDefaults];
        _reconnect.restoreMirror = ^BOOL(NSString *serial, NSDictionary *properties) {
            SCDeviceManager *manager = weakSelf;
            if (!manager) { return NO; }
            manager.metadata[serial] = properties;
            // Let a disconnected mirror finish shutting down before preparing its replacement.
            for (NSString *alias in [manager aliasesForSerial:serial]) {
                if (manager.sessions[alias] || manager.preparations[alias]) { return NO; }
            }
            return [manager mirrorSerial:serial];
        };
        _watcher.changed = ^{ [weakSelf scheduleRefresh]; };
        _watcher.availabilityChanged = ^{ [weakSelf updateFooter]; };
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged:)
            name:SCLanguageChangedNotification object:nil];
    }
    return self;
}

- (void)languageChanged:(NSNotification *)notification {
    (void)notification;
    // Localized bindings update static controls in place. Reload presentation
    // rows only; never restart discovery, metadata queries or mirror sessions.
    NSPoint origin = self.scroll.contentView.bounds.origin;
    [self updateSummary:self.listed];
    [self.table.headerView setNeedsDisplay:YES];
    [self.scroll.contentView scrollToPoint:origin];
    [self.scroll reflectScrolledClipView:self.scroll.contentView];
}

- (NSArray<NSString *> *)aliasesForSerial:(NSString *)serial {
    NSString *identity = SCDevicePhysicalIdentity(self.metadata[serial]);
    if (!identity.length || [serial hasPrefix:@"emulator-"]) { return @[serial]; }
    NSMutableArray *aliases = [NSMutableArray arrayWithObject:serial];
    for (NSString *candidate in self.metadata) {
        if (![candidate isEqualToString:serial] && ![candidate hasPrefix:@"emulator-"]
                && [SCDevicePhysicalIdentity(self.metadata[candidate]) isEqualToString:identity]) {
            [aliases addObject:candidate];
        }
    }
    return aliases;
}

- (BOOL)isRunning:(NSString *)serial {
    for (NSString *alias in [self aliasesForSerial:serial]) {
        if (([alias isEqualToString:currentDeviceSerial] && mirrorWindow.visible)
                || (self.sessions[alias].running && [self.shownSessions containsObject:alias])) { return YES; }
    }
    for (SCMirrorSession *session in self.runningMirrors) {
        if (session.ready && !session.application.terminated
                && [[self aliasesForSerial:serial] containsObject:session.serial]) { return YES; }
    }
    return NO;
}

- (BOOL)isStarting:(NSString *)serial {
    for (NSString *alias in [self aliasesForSerial:serial]) {
        if (self.preparations[alias] ||
                (self.sessions[alias].running && ![self.shownSessions containsObject:alias])) { return YES; }
    }
    for (SCMirrorSession *session in self.runningMirrors) {
        if (!session.ready && !session.application.terminated
                && [[self aliasesForSerial:serial] containsObject:session.serial]) { return YES; }
    }
    return NO;
}

- (void)rebuildDevices {
    self.runningMirrors = SCMirrorRunningSessions();
    NSMutableArray *serials = [NSMutableArray array];
    NSMutableDictionary *identities = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, SCDeviceEntry *> *entries = [NSMutableDictionary dictionary];
    NSMutableSet *identifying = [NSMutableSet setWithArray:self.queries.allKeys];
    // Failed identity lookups may be retried. Keep an existing row visible
    // during a retry, but never publish a new alias before its first result.
    for (SCDeviceEntry *previous in self.devices) {
        [identifying removeObject:previous.serial];
    }
    for (SCDeviceEntry *entry in self.transports) {
        [serials addObject:entry.serial];
        entries[entry.serial] = entry;
        if (entry.transportType != SC_ADB_DEVICE_TYPE_EMULATOR) {
            NSString *identity = SCDevicePhysicalIdentity(self.metadata[entry.serial]);
            if (identity) { identities[entry.serial] = identity; }
        }
    }
    NSMutableArray *devices = [NSMutableArray array];
    for (NSArray<NSString *> *group in SCDeviceTransportGroups(serials, identities, identifying)) {
        SCDeviceEntry *selected = nil;
        // Preserve the previous usable selection when transports are reordered.
        for (SCDeviceEntry *previous in self.devices) {
            if ([group containsObject:previous.serial] && entries[previous.serial].ready) {
                selected = entries[previous.serial]; break;
            }
        }
        if (!selected) {
            for (NSString *serial in group) {
                SCDeviceEntry *entry = entries[serial];
                if (entry.ready && (!selected || entry.transportType == SC_ADB_DEVICE_TYPE_USB)) {
                    selected = entry;
                }
            }
        }
        selected = selected ?: entries[group.firstObject];
        [self applyMetadata:selected];
        [devices addObject:selected];
    }
    self.devices = devices;
}

- (void)mirrorShown:(NSNotification *)notification {
    NSString *serial = notification.userInfo[@"serial"];
    if (![serial isKindOfClass:NSString.class] || !serial.length) { return; }
    NSTask *task = self.sessions[serial];
    self.runningMirrors = SCMirrorRunningSessions();
    if (task.running && task.processIdentifier == [notification.userInfo[@"pid"] intValue]) {
        [self.shownSessions addObject:serial];
        [self.table reloadData];
        NSRunningApplication *app = [NSRunningApplication
            runningApplicationWithProcessIdentifier:task.processIdentifier];
        [app activateWithOptions:NSApplicationActivateAllWindows
            | NSApplicationActivateIgnoringOtherApps];
    }
    [self.table reloadData];
}

- (void)mirrorExited:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    for (SCMirrorSession *session in self.runningMirrors) {
        if (session.application.processIdentifier == app.processIdentifier) {
            [self rebuildDevices];
            [self.table reloadData];
            break;
        }
    }
}

- (NSString *)status:(SCDeviceEntry *)entry {
    if ([self isRunning:entry.serial]) { return @"Mirroring"; }
    if ([self isStarting:entry.serial]) { return @"Starting mirroring…"; }
    if ([entry.state isEqualToString:@"unauthorized"]) { return @"Allow debugging on your device."; }
    if (!entry.ready) { return [entry.state isEqualToString:@"offline"] ? @"Offline" : @"Unknown"; }
    return self.failures[entry.serial] ?: @"Connected";
}

- (void)updateFooter {
    self.scanButton.enabled = !self.snapshot.running;
    SCBind(self.footer, @"stringValue", self.listed ? @"Auto-detecting" : self.snapshot.running ? @"Finding devices…" : @"Discovery unavailable · Retrying");
    self.footerDot.contentTintColor = self.listed ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
    SCBind(self.footer, @"toolTip", self.watcher.connected ? @"Listening for device changes."
        : @"Checking devices periodically while the ADB listener reconnects.");
}

- (void)updateSummary:(BOOL)listed {
    self.listed = listed;
    BOOL empty = !self.devices.count;
    self.emptyView.hidden = !empty;
    self.scroll.hidden = empty;
    BOOL identifying = empty && self.queries.count;
    self.method.hidden = self.steps.hidden = identifying;
    SCBind(self.emptyTitle, @"stringValue", listed && !identifying ? @"Connect a device" : @"Looking for devices");
    SCBind(self.emptyHelp, @"stringValue", identifying ? @"Identifying connected devices…"
        : listed ? @"USB or Wi-Fi" : @"Check ADB. Discovery will retry automatically.");
    [self updateFooter];
    [self.table reloadData];
}

- (void)scheduleRefresh {
    if (self.scheduled || !self.window.visible) { return; }
    self.scheduled = YES;
    NSUInteger generation = self.generation;
    __weak SCDeviceManager *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 150), dispatch_get_main_queue(), ^{
        SCDeviceManager *manager = weakSelf;
        if (generation == manager.generation) {
            manager.scheduled = NO;
            [manager refresh:nil];
        }
    });
}

- (void)applyMetadata:(SCDeviceEntry *)entry {
    NSDictionary *properties = self.metadata[entry.serial];
    NSString *model = properties[@"ro.product.model"];
    if (!model.length) { model = entry.name; }
    NSString *brand = properties[@"ro.product.manufacturer"];
    if (!brand.length) { brand = properties[@"ro.product.brand"]; }
    struct sc_device_info info = {.manufacturer = (char *)brand.UTF8String, .model = (char *)model.UTF8String};
    char *name = sc_device_info_build_name(&info, entry.name.UTF8String);
    if (name) { model = [NSString stringWithUTF8String:name]; free(name); }
    entry.fallbackName = entry.fallbackName && ![properties[@"ro.product.model"] length] && !brand.length;
    entry.name = model;
    NSString *version = properties[@"ro.build.version.release"];
    entry.system = version.length ? [@"Android " stringByAppendingString:version] : @"—";
}

- (void)loadMetadata:(SCDeviceEntry *)entry {
    if (!entry.ready || self.metadata[entry.serial] || self.queries[entry.serial]) { return; }
    NSString *serial = entry.serial;
    NSUInteger generation = self.generation;
    __weak SCDeviceManager *weakSelf = self;
    self.queries[serial] = [SCDeviceCommand run:self.executable arguments:@[@"-s", serial, @"shell", @"getprop"]
        input:nil timeout:5 completion:^(NSString *output, int status) {
        SCDeviceManager *manager = weakSelf;
        if (generation != manager.generation || !manager.window.visible) { return; }
        if (status == -2) { return; }
        [manager.queries removeObjectForKey:serial];
        if (!status) {
            NSDictionary *properties = SCDeviceProperties(output);
            if (properties.count) { manager.metadata[serial] = properties; }
        }
        [manager rebuildDevices];
        [manager updateSummary:manager.listed];
    }];
}

- (void)refresh:(id)sender {
    (void)sender;
    if (!self.window.visible) { return; }
    if (self.snapshot.running) { self.refreshPending = YES; return; }
    NSUInteger generation = self.generation;
    __weak SCDeviceManager *weakSelf = self;
    self.snapshot = [SCDeviceCommand run:self.executable arguments:@[@"devices", @"-l"] input:nil timeout:5
        completion:^(NSString *output, int status) {
        SCDeviceManager *manager = weakSelf;
        if (generation != manager.generation || !manager.window.visible) { return; }
        struct sc_vec_adb_devices devices = SC_VECTOR_INITIALIZER;
        char *buffer = strdup(output.UTF8String);
        BOOL listed = !status && buffer && sc_adb_parse_devices(buffer, &devices);
        if (listed) {
            NSArray<SCDeviceEntry *> *entries = sc_device_picker_entries(&devices);
            // Keep existing rows stable when ADB changes its enumeration order.
            NSMutableArray *ordered = [NSMutableArray array];
            NSMutableArray *remaining = [entries mutableCopy];
            for (SCDeviceEntry *previous in manager.transports) {
                for (SCDeviceEntry *entry in entries) {
                    if ([entry.serial isEqualToString:previous.serial]) {
                        [ordered addObject:entry]; [remaining removeObject:entry]; break;
                    }
                }
            }
            [ordered addObjectsFromArray:remaining];
            manager.transports = ordered;
            NSMutableSet *present = [NSMutableSet set];
            for (SCDeviceEntry *entry in manager.transports) {
                [present addObject:entry.serial];
                [manager applyMetadata:entry];
                [manager loadMetadata:entry];
            }
            for (NSString *serial in manager.metadata.allKeys) {
                if (![present containsObject:serial] && !manager.sessions[serial].running
                        && ![serial isEqualToString:currentDeviceSerial]) {
                    [manager.metadata removeObjectForKey:serial];
                }
            }
            for (NSString *serial in manager.queries.allKeys) {
                if (![present containsObject:serial]) { [manager.queries[serial] cancel]; [manager.queries removeObjectForKey:serial]; }
            }
            [manager rebuildDevices];
        } else {
            // Do not leave stale Mirror controls enabled after discovery fails.
            manager.devices = @[];
            manager.transports = @[];
        }
        free(buffer);
        sc_adb_devices_destroy(&devices);
        [manager updateSummary:listed];
        if (manager.refreshPending) { manager.refreshPending = NO; [manager scheduleRefresh]; }
    }];
    [self updateFooter];
}

- (BOOL)mirrorSerial:(NSString *)serial {
    return [self mirrorSerial:serial displayName:nil];
}

- (BOOL)mirrorSerial:(NSString *)serial displayName:(NSString *)displayName {
    self.runningMirrors = SCMirrorRunningSessions();
    NSArray *aliases = [self aliasesForSerial:serial];
    for (NSString *alias in aliases) {
        if (self.preparations[alias]) { return YES; }
    }
    for (SCMirrorSession *session in self.runningMirrors) {
        if (!session.application.terminated && [aliases containsObject:session.serial]) {
            [session.application activateWithOptions:NSApplicationActivateAllWindows
                | NSApplicationActivateIgnoringOtherApps];
            return YES;
        }
    }
    // A phone may have USB, mDNS and IP transports. Reuse its active mirror.
    for (NSString *alias in [self aliasesForSerial:serial]) {
        if (([alias isEqualToString:currentDeviceSerial] && mirrorWindow.visible)
                || self.sessions[alias].running) { serial = alias; break; }
    }
    if ([serial isEqualToString:currentDeviceSerial]) {
        [mirrorWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; return YES;
    }
    NSTask *existing = self.sessions[serial];
    if (existing.running) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:existing.processIdentifier];
        [app activateWithOptions:NSApplicationActivateAllWindows
            | NSApplicationActivateIgnoringOtherApps]; return YES;
    }
    if (!displayName.length) {
        SCDeviceEntry *selected = nil;
        for (SCDeviceEntry *entry in self.devices) {
            if ([entry.serial isEqualToString:serial]) { selected = entry; break; }
        }
        if (!selected) {
            selected = [[SCDeviceEntry alloc] init];
            selected.serial = serial;
            selected.name = @"Android device"; selected.fallbackName = YES;
        }
        [self applyMetadata:selected];
        displayName = selected.name;
    }
    NSUInteger generation = self.generation;
    __weak SCDeviceManager *weakSelf = self;
    ++self.pendingPreparations;
    self.preparations[serial] = [SCMirrorLaunch prepareWithName:displayName ?: @"Android device"
        serial:serial hostBundle:SCMirrorHostBundle() completion:^(SCMirrorLaunch *launch, NSError *error) {
        SCDeviceManager *manager = weakSelf;
        if (manager) { --manager.pendingPreparations; }
        if (!manager || generation != manager.generation) { [launch cleanup]; return; }
        [manager.preparations removeObjectForKey:serial];
        if (!launch) {
            manager.failures[serial] = @"Could not open mirroring. Try again.";
            LOGE("Could not prepare device window: %s", error.localizedDescription.UTF8String);
            [manager.table reloadData];
        } else {
            [manager launchPreparedMirror:launch serial:serial];
        }
    }];
    [self.failures removeObjectForKey:serial];
    [self.table reloadData];
    return YES;
}

- (BOOL)launchPreparedMirror:(SCMirrorLaunch *)launch serial:(NSString *)serial {
    NSError *error = nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = launch.executableURL;
    task.environment = launch.environment;
    task.arguments = SCMirrorArguments(NSProcessInfo.processInfo.arguments, serial);
    __weak SCDeviceManager *weakSelf = self;
    task.terminationHandler = ^(NSTask *completed) {
        int status = completed.terminationStatus;
        [launch cleanup];
        dispatch_async(dispatch_get_main_queue(), ^{
            SCDeviceManager *manager = weakSelf;
            if (manager.sessions[serial] != completed) { return; }
            [manager.reconnect mirrorEnded:serial properties:manager.metadata[serial] ?: @{}
                unexpected:status == SCRCPY_EXIT_DISCONNECTED];
            [manager.sessions removeObjectForKey:serial];
            [manager.shownSessions removeObject:serial];
            if (status) { manager.failures[serial] = @"Mirroring stopped. Try again."; }
            [manager.table reloadData];
        });
    };
    BOOL launched = [task launchAndReturnError:&error];
    if (launched) {
        self.sessions[serial] = task;
        [self.reconnect mirroringSerial:serial properties:self.metadata[serial] ?: @{}];
        [self.failures removeObjectForKey:serial];
    } else {
        [launch cleanup];
        self.failures[serial] = @"Could not open mirroring. Try again.";
        LOGE("Could not open device: %s", error.localizedDescription.UTF8String);
    }
    [self.table reloadData];
    [self scheduleRefresh];
    return launched;
}

- (void)startMirror:(NSButton *)button { [self mirrorSerial:button.identifier]; }

- (void)openWiFi:(id)sender {
    (void)sender;
    if (!self.wifi.window.visible) {
        __weak SCDeviceManager *weakSelf = self;
        self.wifi = [[SCDeviceWiFiController alloc] initWithExecutable:self.executable mirror:^BOOL(NSString *serial, NSDictionary *properties) {
            SCDeviceManager *manager = weakSelf;
            manager.metadata[serial] = properties;
            return [manager mirrorSerial:serial];
        }];
        self.wifi.reconnect = self.reconnect;
    }
    [self.wifi presentFrom:self.window];
}

- (void)openQRCode:(id)sender {
    [self openWiFi:sender];
    [self.wifi presentQRCodeFrom:self.window];
}

- (NSTextField *)detailValue:(NSString *)value {
    NSTextField *label = SCDeviceLabel(value.length ? value : @"—", 11.5, NSFontWeightRegular, NO);
    label.selectable = YES;
    label.lineBreakMode = NSLineBreakByCharWrapping;
    label.maximumNumberOfLines = 3;
    return label;
}

- (SCDeviceDetailCopyButton *)copyButtonFor:(NSTextField *)value key:(NSString *)key {
    SCDeviceDetailCopyButton *copy = [SCDeviceDetailCopyButton buttonWithImage:SCDeviceSymbol(@"doc.on.doc") target:nil action:@selector(copyValue:)];
    copy.target = copy;
    copy.valueLabel = value;
    copy.translatesAutoresizingMaskIntoConstraints = NO;
    SCBind(copy, @"toolTip", key);
    SCBind(copy, @"accessibilityLabel", key);
    [copy.widthAnchor constraintEqualToConstant:24].active = YES;
    [copy.heightAnchor constraintEqualToConstant:24].active = YES;
    return copy;
}

- (void)showDetails:(NSButton *)button {
    [self.details close];
    [self.detailQuery cancel];
    SCDeviceEntry *entry = nil;
    for (SCDeviceEntry *candidate in self.devices) {
        if ([candidate.serial isEqualToString:button.identifier]) { entry = candidate; break; }
    }
    if (!entry) { return; }
    NSDictionary *properties = self.metadata[entry.serial];
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = [[SCDeviceSurface alloc] initWithFrame:NSMakeRect(0, 0, 320, 178)];
    NSString *serial = properties[@"ro.serialno"] ?: properties[@"ro.boot.serialno"] ?: entry.serial;
    NSString *host = SCDeviceHost(entry.serial);
    NSTextField *ip = [self detailValue:host ?: (entry.ready ? @"Checking…" : @"Unavailable")];
    if (!host) { SCBind(ip, @"stringValue", entry.ready ? @"Checking…" : @"Unavailable"); }
    NSImageView *phone = [NSImageView imageViewWithImage:SCDeviceSymbol(@"iphone")];
    phone.contentTintColor = NSColor.secondaryLabelColor;
    [phone.widthAnchor constraintEqualToConstant:24].active = YES;
    [phone.heightAnchor constraintEqualToConstant:32].active = YES;
    NSTextField *name = entry.fallbackName ? SCDeviceLocalizedLabel(@"Android device", 13, NSFontWeightSemibold, NO)
        : SCDeviceLabel(entry.name, 13, NSFontWeightSemibold, NO);
    if (!entry.fallbackName) { name.toolTip = entry.name; }
    NSTextField *transport = SCDeviceLocalizedLabel(entry.transportType == SC_ADB_DEVICE_TYPE_EMULATOR
        ? @"Emulator" : entry.transport, 11, NSFontWeightRegular, YES);
    NSTextField *status = SCDeviceLocalizedLabel([self status:entry], 11, NSFontWeightRegular, YES);
    NSImageView *dot = [NSImageView imageViewWithImage:SCDeviceSymbol(@"circle.fill")];
    dot.contentTintColor = entry.ready ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
    [dot.widthAnchor constraintEqualToConstant:5].active = YES;
    [dot.heightAnchor constraintEqualToConstant:5].active = YES;
    NSStackView *subtitle = SCDeviceStack(@[transport, dot, status], NO, 7);
    [subtitle setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *heading = SCDeviceStack(@[phone, SCDeviceStack(@[name, subtitle], YES, 3)], NO, 10);
    NSBox *divider = [[NSBox alloc] init];
    divider.boxType = NSBoxSeparator;
    NSStackView *stack = SCDeviceStack(@[heading, divider], YES, 8);
    [stack setCustomSpacing:12 afterView:heading];
    [divider.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [heading.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [name.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor constant:-34].active = YES;
    NSString *api = properties[@"ro.build.version.sdk"];
    NSString *system = api.length ? [NSString stringWithFormat:@"%@ · API %@", entry.system, api] : entry.system;
    NSArray *labels = @[@"Serial number", @"IP address", @"System"];
    NSArray<NSTextField *> *values = @[[self detailValue:serial], ip, [self detailValue:system]];
    SCDeviceDetailCopyButton *copyIP = nil;
    for (NSUInteger i = 0; i < labels.count; ++i) {
        NSTextField *label = SCDeviceLocalizedLabel(labels[i], 11, NSFontWeightRegular, YES);
        [label.widthAnchor constraintEqualToConstant:76].active = YES;
        if (i < 2) { values[i].font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; }
        NSStackView *row = SCDeviceStack(@[label, values[i]], NO, 10);
        if (i < 2) {
            SCDeviceDetailCopyButton *copy = [self copyButtonFor:values[i]
                key:i == 0 ? @"Copy serial number" : @"Copy IP address"];
            copy.enabled = i == 0 ? serial.length > 0 : host.length > 0;
            if (i == 1) { copyIP = copy; }
            [row addArrangedSubview:copy];
        } else {
            NSView *spacer = [[NSView alloc] init];
            [spacer.widthAnchor constraintEqualToConstant:24].active = YES;
            [row addArrangedSubview:spacer];
        }
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:24].active = YES;
        values[i].preferredMaxLayoutWidth = 168;
        [values[i].widthAnchor constraintEqualToConstant:168].active = YES;
    }
    [controller.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:controller.view.topAnchor constant:16],
    ]];
    [controller.view layoutSubtreeIfNeeded];
    [controller.view setFrameSize:NSMakeSize(320, ceil(stack.fittingSize.height) + 32)];
    self.details = [[NSPopover alloc] init];
    self.details.behavior = NSPopoverBehaviorTransient;
    self.details.contentViewController = controller;
    [self.details showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinX];
    if (!host && entry.ready) {
        __weak NSTextField *weakIP = ip;
        __weak SCDeviceDetailCopyButton *weakCopy = copyIP;
        self.detailQuery = [SCDeviceCommand run:self.executable arguments:@[@"-s", entry.serial, @"shell", @"ip", @"-o", @"addr", @"show", @"dev", @"wlan0"] input:nil timeout:4
            completion:^(NSString *output, int status) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"inet ([0-9.]+)/" options:0 error:nil];
            NSTextCheckingResult *match = status ? nil : [regex firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
            if (match) {
                NSString *address = [output substringWithRange:[match rangeAtIndex:1]];
                SCBind(weakIP, @"stringValue", address);
                weakCopy.enabled = YES;
            } else { SCBind(weakIP, @"stringValue", @"Unavailable"); }
        }];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { (void)table; return self.devices.count; }
- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row { (void)table; (void)row; return NO; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    (void)table;
    SCDeviceEntry *entry = self.devices[row];
    BOOL running = [self isRunning:entry.serial];
    BOOL starting = [self isStarting:entry.serial];
    NSView *cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, column.width, 64)];
    if ([column.identifier isEqualToString:@"action"]) {
        NSString *action = running ? @"Show" : starting ? @"Starting…" : !entry.ready ? ([entry.state isEqualToString:@"unauthorized"] ? @"Authorize" : @"Offline") : self.failures[entry.serial] ? @"Retry" : @"Mirror";
        SCDeviceButton *button = [SCDeviceButton buttonWithTitle:action target:self action:@selector(startMirror:)];
        button.bezelStyle = NSBezelStyleRounded;
        button.primary = !running && entry.ready;
        button.enabled = !starting && (entry.ready || running);
        button.identifier = entry.serial;
        button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        SCBind(button, @"toolTip", [self status:entry]);
        SCBindFormat(button, @"accessibilityLabel", [action stringByAppendingString:@" %@"], @[entry.displayName]);
        button.translatesAutoresizingMaskIntoConstraints = NO;
        if (running) {
            NSImage *dot = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                [NSColor.systemGreenColor setFill]; [[NSBezierPath bezierPathWithOvalInRect:rect] fill]; return YES;
            }];
            button.image = dot; button.imagePosition = NSImageLeft;
        }
        NSButton *info = [NSButton buttonWithImage:SCDeviceSymbol(@"info.circle") target:self action:@selector(showDetails:)];
        info.bordered = NO;
        info.contentTintColor = NSColor.secondaryLabelColor;
        info.identifier = entry.serial;
        SCBind(info, @"toolTip", @"Device details");
        SCBindFormat(info, @"accessibilityLabel", @"Details for %@", @[entry.displayName]);
        info.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:button]; [cell addSubview:info];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:info.leadingAnchor constant:-18],
            [button.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [button.widthAnchor constraintEqualToConstant:96], [button.heightAnchor constraintEqualToConstant:30],
            [info.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [info.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [info.widthAnchor constraintEqualToConstant:24], [info.heightAnchor constraintEqualToConstant:28],
        ]];
    } else {
        BOOL device = [column.identifier isEqualToString:@"device"];
        NSTextField *label = SCDeviceLabel(device ? entry.displayName : [column.identifier isEqualToString:@"system"] ? entry.system : entry.transport,
            device ? 13 : 12, device ? NSFontWeightMedium : NSFontWeightRegular, !device);
        label.toolTip = label.stringValue;
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:device ? 52 : 14],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        if (device) {
            NSImageView *icon = [NSImageView imageViewWithImage:SCDeviceSymbol(@"iphone")];
            icon.contentTintColor = NSColor.secondaryLabelColor;
            icon.imageScaling = NSImageScaleProportionallyUpOrDown;
            icon.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:icon];
            [NSLayoutConstraint activateConstraints:@[
                [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:14],
                [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [icon.widthAnchor constraintEqualToConstant:17], [icon.heightAnchor constraintEqualToConstant:25],
            ]];
        }
    }
    return cell;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    return @[@"Anmir.Title", NSToolbarFlexibleSpaceItemIdentifier, @"Anmir.Actions"];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return [self toolbarDefaultItemIdentifiers:toolbar]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar; (void)inserted;
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.autovalidates = NO;
    item.enabled = YES;
    if ([identifier isEqualToString:@"Anmir.Title"]) {
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
        NSTextField *title = SCDeviceLabel(@"Anmir", 14, NSFontWeightMedium, NO);
        [container addSubview:title];
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [title.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-1.5],
        ]];
        item.view = container;
        item.bordered = NO;
        item.minSize = NSMakeSize(100, 28); item.maxSize = NSMakeSize(160, 28);
    } else {
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 90, 28)];
        self.scanButton = [SCDeviceIconButton buttonWithImage:SCDeviceSymbol(@"arrow.clockwise") target:self action:@selector(refresh:)];
        SCBind(self.scanButton, @"accessibilityLabel", @"Scan devices");
        SCBind(self.scanButton, @"toolTip", @"Device not showing up? Scan again.");
        NSButton *wifi = [SCDeviceIconButton buttonWithImage:SCDeviceWiFiSymbol() target:self action:@selector(openWiFi:)];
        SCBind(wifi, @"accessibilityLabel", @"Connect via Wi-Fi");
        SCBind(wifi, @"toolTip", @"Connect via Wi-Fi");
        NSArray<NSButton *> *buttons = @[self.scanButton, wifi, SCSettingsButton()];
        for (NSUInteger i = 0; i < buttons.count; ++i) {
            buttons[i].frame = NSMakeRect(i * 30, 0, 28, 28);
            [container addSubview:buttons[i]];
        }
        item.view = container;
        item.bordered = NO;
        item.minSize = item.maxSize = NSMakeSize(90, 28);
        SCBind(item, @"label", @"Device actions");
    }
    return item;
}

- (void)methodChanged:(id)sender {
    (void)sender;
    for (NSView *view in self.steps.arrangedSubviews.copy) { [self.steps removeArrangedSubview:view]; [view removeFromSuperview]; }
    BOOL wifi = self.method.selectedSegment == 1;
    NSArray *steps = wifi ? @[@"Same Wi-Fi network", @"Wireless debugging", @"Scan QR code"]
        : @[@"Connect USB", @"Enable USB debugging", @"Allow this Mac"];
    for (NSUInteger i = 0; i < 3; ++i) {
        SCDeviceStepBadge *number = [[SCDeviceStepBadge alloc] initWithNumber:i + 1];
        NSView *caption = [[NSView alloc] init];
        caption.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *label;
        if (wifi && i == 2) {
            NSButton *link = [NSButton buttonWithTitle:@"Scan QR code →"
                target:self action:@selector(openQRCode:)];
            SCBind(link, @"title", @"Scan QR code →");
            link.bordered = NO;
            link.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
            link.contentTintColor = NSColor.linkColor;
            SCBind(link, @"toolTip", @"Open Wi-Fi pairing");
            SCBind(link, @"accessibilityLabel", @"Scan QR code to connect via Wi-Fi");
            link.translatesAutoresizingMaskIntoConstraints = NO;
            [link.heightAnchor constraintEqualToConstant:28].active = YES;
            label = link;
        } else {
            label = SCDeviceLocalizedLabel(steps[i], 12, NSFontWeightRegular, NO);
        }
        [caption addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [caption.widthAnchor constraintEqualToConstant:210],
            [caption.heightAnchor constraintEqualToConstant:28],
            [label.centerXAnchor constraintEqualToAnchor:caption.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:caption.centerYAnchor],
        ]];
        NSStackView *step = SCDeviceStack(@[number, caption], YES, 8);
        step.alignment = NSLayoutAttributeCenterX;
        [step.widthAnchor constraintEqualToConstant:210].active = YES;
        [self.steps addArrangedSubview:step];
        if (i < 2) {
            NSBox *divider = [[NSBox alloc] init]; divider.boxType = NSBoxSeparator;
            [divider.widthAnchor constraintEqualToConstant:1].active = YES;
            [divider.heightAnchor constraintEqualToConstant:58].active = YES;
            [self.steps addArrangedSubview:divider];
        }
    }
}

- (void)createWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 440)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Anmir";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.releasedWhenClosed = NO;
    self.window.backgroundColor = SCDeviceBackground();
    self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(760, 420);
    self.window.delegate = self;
    self.window.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
    self.window.contentView = [[SCDeviceSurface alloc] initWithFrame:self.window.contentView.bounds];
    NSView *content = self.window.contentView;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"Anmir.Devices.Toolbar"];
    toolbar.delegate = self; toolbar.allowsUserCustomization = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly; toolbar.showsBaselineSeparator = YES;
    self.window.toolbar = toolbar;
    self.table = [[SCDeviceTableView alloc] initWithFrame:NSMakeRect(0, 0, 712, 64 * self.devices.count)];
    self.table.style = NSTableViewStylePlain;
    NSArray *columns = @[@[@"device", @"Device", @268], @[@"system", @"System", @140], @[@"connection", @"Connection", @120], @[@"action", @"", @184]];
    for (NSArray *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        SCBind(column, @"title", spec[1]); column.width = [spec[2] doubleValue];
        BOOL device = [spec[0] isEqualToString:@"device"];
        column.minWidth = device ? 200 : column.width;
        column.resizingMask = device ? NSTableColumnAutoresizingMask : NSTableColumnNoResizing;
        [self.table addTableColumn:column];
    }
    self.table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.table.headerView = [[SCDeviceHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 712, 32)];
    self.table.allowsColumnReordering = self.table.allowsColumnResizing = NO;
    self.table.rowHeight = 64; self.table.usesAutomaticRowHeights = NO;
    self.table.intercellSpacing = NSMakeSize(0, 0);
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    self.table.gridColor = [NSColor.separatorColor colorWithAlphaComponent:0.15];
    self.table.backgroundColor = SCDeviceBackground();
    self.table.allowsEmptySelection = YES;
    self.table.dataSource = self; self.table.delegate = self;
    self.scroll = [[NSScrollView alloc] init];
    self.scroll.borderType = NSNoBorder;
    self.scroll.hasVerticalScroller = YES; self.scroll.autohidesScrollers = YES;
    self.scroll.automaticallyAdjustsContentInsets = NO;
    self.scroll.documentView = self.table;
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.scroll];

    self.emptyTitle = SCDeviceLocalizedLabel(@"Connect a device", 20, NSFontWeightSemibold, NO);
    self.emptyHelp = SCDeviceLocalizedLabel(@"USB or Wi-Fi", 12, NSFontWeightRegular, YES);
    self.method = [NSSegmentedControl segmentedControlWithLabels:@[@"USB", @"Wi-Fi"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(methodChanged:)];
    self.method.selectedSegment = 0;
    self.method.segmentStyle = NSSegmentStyleRounded;
    [self.method setWidth:108 forSegment:0]; [self.method setWidth:108 forSegment:1];
    SCBind(self.method, @"accessibilityLabel", @"Connection guide");
    self.steps = SCDeviceStack(@[], NO, 16);
    [self methodChanged:nil];
    self.emptyView = SCDeviceStack(@[self.emptyTitle, self.emptyHelp, self.method, self.steps], YES, 12);
    self.emptyView.alignment = NSLayoutAttributeCenterX;
    [self.emptyView setCustomSpacing:22 afterView:self.emptyHelp];
    [self.emptyView setCustomSpacing:32 afterView:self.method];
    [content addSubview:self.emptyView];
    self.footer = SCDeviceLocalizedLabel(@"Auto-detecting", 11, NSFontWeightRegular, YES);
    self.footerDot = [NSImageView imageViewWithImage:SCDeviceSymbol(@"circle.fill")];
    self.footerDot.contentTintColor = NSColor.systemGreenColor;
    [self.footerDot.widthAnchor constraintEqualToConstant:8].active = YES;
    [self.footerDot.heightAnchor constraintEqualToConstant:8].active = YES;
    NSStackView *footer = SCDeviceStack(@[self.footerDot, self.footer], NO, 8);
    [content addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [self.scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [self.scroll.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [self.scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-16],
        [self.emptyView.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [self.emptyView.centerYAnchor constraintEqualToAnchor:content.centerYAnchor constant:-12],
        [footer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [footer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18],
    ]];
    NSRect frame = self.window.frame;
    frame.size = NSMakeSize(760, 500);
    [self.window setFrame:frame display:NO];
    [self.window center];
    [self updateSummary:YES];
}

- (void)show {
    if (!self.window) { [self createWindow]; }
    BOOL wasVisible = self.window.visible || self.window.miniaturized;
    if (self.window.miniaturized) { [self.window deminiaturize:nil]; }
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    if (!wasVisible) {
        ++self.generation;
        // An IP/port can belong to another phone while the manager is closed.
        // Retain identities needed by active mirrors, and re-query the rest.
        self.runningMirrors = SCMirrorRunningSessions();
        NSMutableSet *active = [NSMutableSet set];
        for (NSString *serial in self.sessions) {
            if (self.sessions[serial].running) { [active addObject:serial]; }
        }
        for (SCMirrorSession *session in self.runningMirrors) { [active addObject:session.serial]; }
        if (currentDeviceSerial && mirrorWindow.visible) { [active addObject:currentDeviceSerial]; }
        for (NSString *serial in self.metadata.allKeys) {
            if (![active containsObject:serial]) { [self.metadata removeObjectForKey:serial]; }
        }
        [self.watcher start];
        __weak SCDeviceManager *weakSelf = self;
        self.fallbackTimer = [NSTimer timerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            SCDeviceManager *manager = weakSelf;
            if (!manager.watcher.connected || !manager.listed) { [manager refresh:nil]; }
            for (SCDeviceEntry *entry in manager.transports) { [manager loadMetadata:entry]; }
        }];
        [NSRunLoop.mainRunLoop addTimer:self.fallbackTimer forMode:NSRunLoopCommonModes];
        [self refresh:nil];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    ++self.generation;
    self.scheduled = self.refreshPending = NO;
    [self.watcher stop]; [self.fallbackTimer invalidate]; self.fallbackTimer = nil;
    for (SCMirrorPreparation *request in self.preparations.allValues) { [request cancel]; }
    [self.preparations removeAllObjects];
    [self.snapshot cancel];
    for (SCDeviceCommand *query in self.queries.allValues) { [query cancel]; }
    [self.queries removeAllObjects];
    [self.detailQuery cancel]; [self.details close]; [self.wifi close];
}
@end

static SCDeviceManager *deviceManager;

static SCDeviceManager *
sc_device_picker_get_manager(void) {
    if (!deviceManager) {
        deviceManager = [[SCDeviceManager alloc] init];
    }
    return deviceManager;
}

@interface SCDeviceMenu : NSObject
- (void)showDevices:(id)sender;
- (void)rescan:(id)sender;
@end

@implementation SCDeviceMenu
- (instancetype)init {
    self = [super init];
    if (self && [SCMirrorHostBundleIdentifier() isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        [NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(showDevices:)
            name:[SCMirrorHostBundleIdentifier() stringByAppendingString:@".ShowDevices"] object:nil
            suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    }
    return self;
}
- (void)showDevices:(id)sender {
    (void) sender;
    NSBundle *host = SCMirrorHostBundle();
    if (![host.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:host.bundleIdentifier]) {
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:
                [SCMirrorHostBundleIdentifier() stringByAppendingString:@".ShowDevices"]
                object:nil userInfo:nil deliverImmediately:YES];
            [app activateWithOptions:NSApplicationActivateAllWindows]; return;
        }
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        configuration.environment = @{@"ANMIR_SHOW_DEVICES":@"1"};
        [NSWorkspace.sharedWorkspace openApplicationAtURL:host.bundleURL configuration:configuration
            completionHandler:^(NSRunningApplication *app, NSError *error) { (void)app;
                if (error) { LOGE("Could not open device manager: %s", error.localizedDescription.UTF8String); }
            }];
        return;
    }
    SCDeviceManager *manager = sc_device_picker_get_manager();
    [manager show];
}
- (void)rescan:(id)sender {
    [sc_device_picker_get_manager() refresh:sender];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return item.action != @selector(rescan:) || deviceManager.window.visible;
}
@end

static SCDeviceMenu *SCDeviceMenuController(void) {
    static SCDeviceMenu *controller;
    if (!controller) { controller = [[SCDeviceMenu alloc] init]; }
    return controller;
}

NSButton *SCDevicePickerButton(void) {
    NSButton *button = [SCDeviceIconButton buttonWithImage:SCDeviceListSymbol()
        target:SCDeviceMenuController() action:@selector(showDevices:)];
    button.identifier = @"Anmir.Devices";
    SCBind(button, @"toolTip", @"Open device list");
    SCBind(button, @"accessibilityLabel", @"Open device list");
    return button;
}

void
sc_device_picker_install_menu(SDL_Window *window) {
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundlePackageType"]
            isEqualToString:@"APPL"]) {
        return;
    }
    if (window) {
        SDL_PropertiesID properties = SDL_GetWindowProperties(window);
        mirrorWindow = (__bridge NSWindow *) SDL_GetPointerProperty(properties,
            SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    }
    void (^showDevices)(void) = ^{
        [SCDeviceMenuController() showDevices:nil];
    };
    SCApplicationLifecycleInstall(showDevices, ^BOOL(NSString *path) {
        return sc_apk_installer_open_file(path, showDevices);
    });
    NSMenu *mainMenu = NSApp.mainMenu;
    if (!mainMenu.numberOfItems) {
        return;
    }
    if (![mainMenu itemWithTag:0x53434544]) {
        NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
        editItem.tag = 0x53434544;
        SCBind(editItem, @"title", @"Edit");
        NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"]; SCBind(edit, @"title", @"Edit");
        NSArray *commands = @[
            @[@"Undo", @"undo:", @"z"], @[@"Redo", @"redo:", @"Z"],
            @[@"Cut", @"cut:", @"x"], @[@"Copy", @"copy:", @"c"],
            @[@"Paste", @"paste:", @"v"], @[@"Select All", @"selectAll:", @"a"],
        ];
        for (NSUInteger i = 0; i < commands.count; ++i) {
            if (i == 2 || i == 5) { [edit addItem:NSMenuItem.separatorItem]; }
            NSArray *command = commands[i];
            NSMenuItem *commandItem = [edit addItemWithTitle:command[0] action:NSSelectorFromString(command[1]) keyEquivalent:command[2]];
            SCBind(commandItem, @"title", command[0]);
        }
        editItem.submenu = edit;
        [mainMenu insertItem:editItem atIndex:1];
    }
    NSMenu *appMenu = [mainMenu itemAtIndex:0].submenu;
    if (!appMenu || [appMenu itemWithTag:0x53434456]) {
        return;
    }
    SCDeviceMenu *controller = SCDeviceMenuController();
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Devices…"
        action:@selector(showDevices:) keyEquivalent:@"d"];
    item.target = controller;
    SCBind(item, @"title", @"Devices…");
    item.tag = 0x53434456;
    item.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [appMenu insertItem:item atIndex:MIN(2, appMenu.numberOfItems)];
    NSMenuItem *rescan = [[NSMenuItem alloc] initWithTitle:@"Rescan devices"
        action:@selector(rescan:) keyEquivalent:@"r"];
    rescan.target = controller;
    SCBind(rescan, @"title", @"Rescan devices");
    [appMenu insertItem:rescan atIndex:MIN(3, appMenu.numberOfItems)];
    sc_theme_install_menu();
}

void
sc_device_picker_set_current_device(const char *serial) {
    currentDeviceSerial = serial ? sc_device_picker_string(serial) : nil;
    mirrorPresented = NO;
}

void
sc_device_picker_mirror_shown(void) {
    if (!currentDeviceSerial.length || !mirrorWindow.visible
            || !SCMirrorShownNotification().length) { return; }
    if (!mirrorPresented) {
        mirrorPresented = YES;
        SCMirrorMarkReady();
        [mirrorWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
    [NSDistributedNotificationCenter.defaultCenter
        postNotificationName:SCMirrorShownNotification() object:nil
        userInfo:@{@"serial":currentDeviceSerial,
                   @"pid":@(NSProcessInfo.processInfo.processIdentifier)}
        deliverImmediately:YES];
}

static void
sc_device_picker_run_windows(void) {
    // The manager may be created later by the Devices action while Settings
    // is already open. Read the shared manager on every iteration.
    while (SCApplicationHasWindows() || SCUpdaterBusy()
            || sc_apk_installer_busy()
            || deviceManager.pendingPreparations || deviceManager.reconnect.active) {
        @autoreleasepool {
            SDL_Event event;
            if (SDL_WaitEventTimeout(&event, 100)) {
                if (event.type == SDL_EVENT_DROP_FILE
                        && event.drop.windowID == 0 && event.drop.data) {
                    NSString *path = [NSString stringWithUTF8String:event.drop.data];
                    sc_apk_installer_open_file(path, ^{
                        [SCDeviceMenuController() showDevices:nil];
                    });
                } else if (event.type == SDL_EVENT_QUIT) {
                    SCApplicationRequestQuit();
                    SCUpdaterCancel();
                    [deviceManager.reconnect stop];
                    [deviceManager.window close];
                    for (NSWindow *window in NSApp.windows.copy) { [window close]; }
                }
            }
        }
    }
}

static BOOL
sc_device_picker_process_startup_apks(void) {
    BOOL handled = NO;
    // Launch Services may deliver the initial open-document Apple event just
    // after SDL has finished creating NSApplication. Give that event a small
    // head start so the device list does not flash before an APK open request
    // is routed to the installer.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.25];
    do {
        SDL_PumpEvents();
        SDL_Event event;
        while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_EVENT_DROP_FILE,
                SDL_EVENT_DROP_FILE) == 1) {
            if (event.drop.windowID == 0 && event.drop.data) {
                NSString *path = [NSString stringWithUTF8String:event.drop.data];
                handled |= sc_apk_installer_open_file(path, ^{
                    [SCDeviceMenuController() showDevices:nil];
                });
            }
        }
        // Once the lifecycle delegate handled the file directly, discovery is
        // already active and no SDL drop event remains in the queue.
        if (handled || sc_apk_installer_busy()) {
            return YES;
        }
        [NSRunLoop.mainRunLoop runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.01]];
    } while (deadline.timeIntervalSinceNow > 0);
    return NO;
}

enum sc_device_picker_result
sc_device_picker_run(const struct scrcpy_options *options, struct sc_intr *intr) {
    SCMirrorInstallCleanup();
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundlePackageType"]
            isEqualToString:@"APPL"]) {
        return SC_DEVICE_PICKER_CONTINUE;
    }
    sc_apk_installer_register_file_association();
    if (options->serial || options->select_usb ||
            options->select_tcpip || options->tcpip_dst || options->list ||
            !options->window || getenv("ANDROID_SERIAL")) {
        return SC_DEVICE_PICKER_CONTINUE;
    }
    @autoreleasepool {
        if (getenv("ANMIR_SHOW_SETTINGS") || getenv("ANMIR_CHECK_UPDATES")) {
            if (!SDL_WasInit(SDL_INIT_VIDEO) && !SDL_InitSubSystem(SDL_INIT_VIDEO)) {
                LOGE("Could not initialize application UI: %s", SDL_GetError());
                return SC_DEVICE_PICKER_ERROR;
            }
            sc_device_picker_install_menu(NULL);
            // Settings keeps precedence if both variables were inherited.
            if (getenv("ANMIR_SHOW_SETTINGS")) { SCSettingsShow(); }
            else { SCUpdaterCheck(); }
            sc_device_picker_run_windows();
            return SC_DEVICE_PICKER_FINISHED;
        }
        struct sc_vec_adb_devices devices = SC_VECTOR_INITIALIZER;
        bool listed = sc_adb_start_server(intr, 0)
            && sc_adb_list_devices(intr, 0, &devices);
        if (!SDL_WasInit(SDL_INIT_VIDEO) &&
                !SDL_InitSubSystem(SDL_INIT_VIDEO)) {
            LOGE("Could not initialize device manager: %s", SDL_GetError());
            sc_adb_devices_destroy(&devices);
            return SC_DEVICE_PICKER_ERROR;
        }
        SCDeviceManager *manager = sc_device_picker_get_manager();
        if (!manager) {
            sc_adb_devices_destroy(&devices);
            return SC_DEVICE_PICKER_ERROR;
        }
        manager.transports = sc_device_picker_entries(&devices);
        sc_adb_devices_destroy(&devices);
        sc_device_picker_install_menu(NULL);
        BOOL openedAPK = sc_device_picker_process_startup_apks();
        if (!openedAPK) {
            [manager show];
        }
        [manager updateSummary:listed];
        // Startup has no mirror window yet. Pump SDL/AppKit while the native
        // manager stays open; mirror processes run independently of this loop.
        // A close cancels preparation, but workers must still finish cleanup
        // before this process exits (including a codesign already in flight).
        sc_device_picker_run_windows();
        return SC_DEVICE_PICKER_FINISHED;
    }
}
