#import "device_reconnect.h"
#import "device_connection.h"

static NSString * const SCReconnectDefaults = @"CompanyNetworkPhones.v1";

@interface SCReconnectPhone : NSObject
@property(nonatomic, strong) SCDeviceRelay *relay;
@property(nonatomic, copy) NSDictionary *registration, *properties;
@property(nonatomic, copy) NSString *serial, *candidate;
@property(nonatomic, strong) SCDeviceConnection *connection;
@property(nonatomic, strong) SCDeviceCommand *probe;
@property(nonatomic, strong) NSDate *reported, *nextAttempt;
@property(nonatomic) NSUInteger failures;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL connected, mirrorWanted, restorePending;
@end
@implementation SCReconnectPhone
@end

@interface SCDeviceReconnect ()
@property(nonatomic, copy) NSString *executable;
@property(nonatomic, strong) NSUserDefaults *defaults;
@property(nonatomic, strong) NSMutableArray<SCReconnectPhone *> *phones;
@property(nonatomic, strong) NSTimer *timer;
@end

@implementation SCDeviceReconnect
- (BOOL)active { return self.phones.count > 0; }
- (instancetype)initWithExecutable:(NSString *)executable defaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _executable = [executable copy]; _defaults = defaults;
        _phones = [NSMutableArray array];
        id saved = [defaults objectForKey:SCReconnectDefaults];
        if ([saved isKindOfClass:NSArray.class]) {
            for (id registration in saved) {
                if (_phones.count == 8) { break; }
                SCDeviceRelay *relay = [SCDeviceRelay resumeRegistration:registration error:nil];
                if (!relay) { continue; }
                [self addRelay:relay];
            }
        }
        __weak SCDeviceReconnect *weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
            (void)timer; [weakSelf tick];
        }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}
- (SCReconnectPhone *)addRelay:(SCDeviceRelay *)relay {
    SCReconnectPhone *phone = [[SCReconnectPhone alloc] init];
    phone.relay = relay; phone.registration = relay.registration;
    NSString *lastEndpoint = phone.registration[@"lastEndpoint"];
    if ([lastEndpoint isKindOfClass:NSString.class] && SCDeviceEndpoint(lastEndpoint, nil)) { phone.serial = lastEndpoint; }
    phone.connection = [[SCDeviceConnection alloc] initWithExecutable:self.executable];
    [self.phones addObject:phone];
    __weak SCDeviceReconnect *weakSelf = self;
    __weak SCReconnectPhone *weakPhone = phone;
    relay.reconnected = ^(NSArray<SCDeviceService *> *services, BOOL retry) {
        SCDeviceReconnect *owner = weakSelf; SCReconnectPhone *current = weakPhone;
        if (!owner || !current) { return; }
        NSString *endpoint = services.firstObject.endpoint;
        BOOL changed = ![endpoint ?: @"" isEqualToString:current.candidate ?: @""];
        current.reported = [NSDate date];
        if (changed) {
            ++current.generation;
            if (current.connected && ![endpoint isEqualToString:current.serial]) { [owner lost:current]; }
            current.candidate = endpoint;
            current.failures = 0; current.nextAttempt = NSDate.distantPast;
            [current.probe cancel]; current.probe = nil;
            [current.connection cancel];
        }
        if (retry) {
            ++current.generation;
            [current.probe cancel]; current.probe = nil;
            if (!current.connected) { [current.connection cancel]; }
            current.nextAttempt = NSDate.distantPast; current.failures = 0;
        }
        if (!endpoint) { [owner lost:current]; }
        [owner tick];
    };
    phone.connection.changed = ^{
        SCDeviceReconnect *owner = weakSelf; SCReconnectPhone *current = weakPhone;
        if (!owner || !current) { return; }
        if (current.connection.phase == SCDeviceConnectionReady) {
            // A callback token and advertised GUID never replace TLS + identity verification.
            if (![SCDevicePhysicalIdentity(current.connection.properties) isEqualToString:current.registration[@"identity"]]) {
                [owner failed:current]; return;
            }
            current.connected = YES;
            current.serial = current.connection.serial;
            current.properties = current.connection.properties;
            NSMutableDictionary *registration = [current.registration mutableCopy];
            registration[@"lastEndpoint"] = current.serial;
            current.registration = registration;
            [owner.defaults setObject:[owner.phones valueForKey:@"registration"] forKey:SCReconnectDefaults];
            current.failures = 0;
            current.nextAttempt = [NSDate dateWithTimeIntervalSinceNow:5];
            [owner restore:current];
        } else if (current.connection.phase == SCDeviceConnectionFailed) { [owner failed:current]; }
    };
    return phone;
}
- (BOOL)rememberRelay:(SCDeviceRelay *)relay guid:(NSString *)guid serial:(NSString *)serial properties:(NSDictionary *)properties {
    NSString *identity = SCDevicePhysicalIdentity(properties);
    if (!relay || !identity.length || !guid.length || !SCDeviceHost(serial)) { return NO; }
    for (SCReconnectPhone *old in [self.phones copy]) {
        if ([old.registration[@"guid"] isEqualToString:guid] || [old.registration[@"identity"] isEqualToString:identity]) {
            [self removePhone:old];
        }
    }
    // Bounded remembered-device storage; replacing the oldest route also revokes its token.
    if (self.phones.count == 8) { [self removePhone:self.phones.firstObject]; }
    [relay registerGUID:guid identity:identity peer:SCDeviceHost(serial)];
    SCReconnectPhone *phone = [self addRelay:relay];
    phone.serial = phone.candidate = serial; phone.properties = properties;
    NSMutableDictionary *registration = [phone.registration mutableCopy];
    registration[@"lastEndpoint"] = serial; phone.registration = registration;
    phone.connected = phone.mirrorWanted = YES;
    phone.reported = [NSDate date]; phone.nextAttempt = [NSDate dateWithTimeIntervalSinceNow:5];
    [self.defaults setObject:[self.phones valueForKey:@"registration"] forKey:SCReconnectDefaults];
    return YES;
}
- (void)removePhone:(SCReconnectPhone *)phone {
    ++phone.generation;
    [phone.relay stop]; [phone.probe cancel]; [phone.connection cancel];
    phone.connection.changed = nil;
    [self.phones removeObject:phone];
}
- (void)mirroringSerial:(NSString *)serial properties:(NSDictionary *)properties {
    NSString *identity = SCDevicePhysicalIdentity(properties);
    for (SCReconnectPhone *phone in self.phones) {
        if ([identity isEqualToString:phone.registration[@"identity"]] || [phone.serial isEqualToString:serial]) {
            phone.mirrorWanted = YES;
        }
    }
}
- (void)mirrorEnded:(NSString *)serial properties:(NSDictionary *)properties unexpected:(BOOL)unexpected {
    NSString *identity = SCDevicePhysicalIdentity(properties);
    for (SCReconnectPhone *phone in self.phones) {
        if (![phone.serial isEqualToString:serial] && ![identity isEqualToString:phone.registration[@"identity"]]) { continue; }
        if (!unexpected) { phone.mirrorWanted = phone.restorePending = NO; }
        else { phone.nextAttempt = NSDate.distantPast; }
    }
}
- (void)lost:(SCReconnectPhone *)phone {
    if (phone.connected && phone.mirrorWanted) { phone.restorePending = YES; }
    phone.connected = NO;
}
- (void)failed:(SCReconnectPhone *)phone {
    [self lost:phone];
    NSUInteger exponent = MIN(phone.failures, 4u);
    ++phone.failures;
    NSTimeInterval delay = MIN(30, 2u << exponent);
    phone.nextAttempt = [NSDate dateWithTimeIntervalSinceNow:delay];
}
- (void)restore:(SCReconnectPhone *)phone {
    if (phone.restorePending && phone.mirrorWanted && self.restoreMirror
            && self.restoreMirror(phone.serial, phone.properties)) { phone.restorePending = NO; }
}
- (void)tick {
    for (SCReconnectPhone *phone in self.phones) {
        if (phone.connected) { [self restore:phone]; }
        if (phone.probe.running || phone.connection.busy || phone.nextAttempt.timeIntervalSinceNow > 0) { continue; }
        if (phone.connected) {
            NSUInteger generation = phone.generation;
            __weak SCDeviceReconnect *weakSelf = self;
            __weak SCReconnectPhone *weakPhone = phone;
            phone.probe = [SCDeviceCommand run:self.executable arguments:@[@"-s", phone.serial, @"get-state"]
                input:nil timeout:3 completion:^(NSString *output, int status) {
                SCDeviceReconnect *owner = weakSelf; SCReconnectPhone *current = weakPhone;
                if (!owner || !current || generation != current.generation) { return; }
                current.probe = nil;
                if (status || ![[output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                        isEqualToString:@"device"]) { [owner failed:current]; }
                else { current.nextAttempt = [NSDate dateWithTimeIntervalSinceNow:5]; }
            }];
        } else if (phone.candidate.length && phone.reported && -phone.reported.timeIntervalSinceNow < 45) {
            [phone.connection connectEndpoint:phone.candidate];
        }
    }
}
- (void)stop {
    [self.timer invalidate]; self.timer = nil;
    for (SCReconnectPhone *phone in [self.phones copy]) { [self removePhone:phone]; }
    self.restoreMirror = nil;
}
- (void)dealloc { [self.timer invalidate]; for (SCReconnectPhone *phone in _phones) { [phone.relay stop]; [phone.probe cancel]; [phone.connection cancel]; } }
@end
