#import "apk_devices.h"

#import "device_support.h"
#import "finder_device_menu.h"

static NSArray<NSString *> *SCAPKSelectionArguments(NSString *serial,
                                                   NSString *transportID) {
    return transportID.length ? @[@"-t", transportID] : @[@"-s", serial];
}

@interface SCAPKTarget ()
- (instancetype)initWithDevice:(NSDictionary<NSString *, NSString *> *)device
                       identity:(NSString *)identity;
@end

@implementation SCAPKTarget
- (instancetype)initWithDevice:(NSDictionary<NSString *, NSString *> *)device
                       identity:(NSString *)identity {
    self = [super init];
    if (self) {
        _serial = [device[SCFinderDeviceSerialKey] copy];
        _model = [device[SCFinderDeviceModelKey] copy];
        _transport = [device[SCFinderDeviceTransportKey] copy];
        _transportID = [device[SCFinderDeviceTransportIDKey] copy];
        _identity = [identity copy];
    }
    return self;
}

- (NSArray<NSString *> *)selectionArguments {
    return SCAPKSelectionArguments(self.serial, self.transportID);
}
@end

@interface SCAPKDeviceDiscovery ()
@property(nonatomic, copy) NSString *adb;
@property(nonatomic, strong) SCDeviceCommand *listCommand;
@property(nonatomic, strong) NSMutableDictionary<NSString *, SCDeviceCommand *> *queries;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *identities;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *devices;
@property(nonatomic) NSUInteger nextDevice;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, copy) void (^completion)(NSArray<SCAPKTarget *> *, int);
@end

@implementation SCAPKDeviceDiscovery
- (instancetype)initWithADB:(NSString *)adb {
    self = [super init];
    if (self) {
        _adb = [adb copy];
        _queries = [NSMutableDictionary dictionary];
        _identities = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)startWithCompletion:(void (^)(NSArray<SCAPKTarget *> *, int))completion {
    [self cancel];
    self.completion = completion;
    NSUInteger generation = self.generation;
    __weak SCAPKDeviceDiscovery *weakSelf = self;
    self.listCommand = [SCDeviceCommand run:self.adb arguments:@[@"devices", @"-l"]
        input:nil timeout:5 completion:^(NSString *output, int status) {
            SCAPKDeviceDiscovery *discovery = weakSelf;
            if (!discovery || discovery.generation != generation) { return; }
            discovery.listCommand = nil;
            if (status) {
                [discovery finish:@[] status:status];
                return;
            }
            discovery.devices = SCFinderParseADBDevices(output);
            [discovery startIdentityQueries];
        }];
}

- (void)startIdentityQueries {
    NSUInteger generation = self.generation;
    __weak SCAPKDeviceDiscovery *weakSelf = self;
    // Several phones can answer independently, but bound concurrent ADB
    // subprocesses when a large USB hub is connected.
    while (self.queries.count < 4 && self.nextDevice < self.devices.count) {
        NSDictionary<NSString *, NSString *> *device = self.devices[self.nextDevice++];
        NSString *serial = device[SCFinderDeviceSerialKey];
        if ([serial hasPrefix:@"emulator-"] || self.queries[serial]) { continue; }
        NSArray<NSString *> *selection = SCAPKSelectionArguments(serial,
            device[SCFinderDeviceTransportIDKey]);
        self.queries[serial] = [SCDeviceCommand run:self.adb
            arguments:[selection arrayByAddingObjectsFromArray:@[@"shell", @"getprop"]]
            input:nil timeout:5 completion:^(NSString *output, int status) {
                SCAPKDeviceDiscovery *discovery = weakSelf;
                if (!discovery || discovery.generation != generation) { return; }
                [discovery.queries removeObjectForKey:serial];
                if (!status) {
                    NSString *identity = SCDevicePhysicalIdentity(SCDeviceProperties(output));
                    if (identity) { discovery.identities[serial] = identity; }
                }
                [discovery startIdentityQueries];
            }];
    }
    if (!self.queries.count) {
        [self finish:[self groupedTargets] status:0];
    }
}

- (NSArray<SCAPKTarget *> *)groupedTargets {
    NSMutableArray<NSString *> *serials = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *devicesBySerial =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, NSString *> *device in self.devices) {
        NSString *serial = device[SCFinderDeviceSerialKey];
        if (devicesBySerial[serial]) { continue; }
        [serials addObject:serial];
        devicesBySerial[serial] = device;
    }
    NSMutableArray<SCAPKTarget *> *targets = [NSMutableArray array];
    for (NSArray<NSString *> *group in SCDeviceTransportGroups(serials, self.identities, NSSet.set)) {
        NSString *preferred = group.firstObject;
        for (NSString *serial in group) {
            if ([devicesBySerial[serial][SCFinderDeviceTransportKey] isEqualToString:@"USB"]) {
                preferred = serial;
                break;
            }
        }
        [targets addObject:[[SCAPKTarget alloc] initWithDevice:devicesBySerial[preferred]
            identity:self.identities[preferred]]];
    }
    return targets;
}

- (void)finish:(NSArray<SCAPKTarget *> *)targets status:(int)status {
    void (^completion)(NSArray<SCAPKTarget *> *, int) = self.completion;
    [self cancel];
    if (completion) { completion(targets, status); }
}

- (void)cancel {
    ++self.generation;
    self.completion = nil;
    [self.listCommand cancel];
    self.listCommand = nil;
    for (SCDeviceCommand *query in self.queries.allValues) { [query cancel]; }
    [self.queries removeAllObjects];
    [self.identities removeAllObjects];
    self.devices = nil;
    self.nextDevice = 0;
}
@end
