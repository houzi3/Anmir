#import "device_connection.h"
#import "device_pairing.h"

@interface SCDeviceConnection ()
@property(nonatomic, copy) NSString *executable;
@property(nonatomic, strong) SCDeviceCommand *operation;
@property(nonatomic, strong) NSTimer *deadline;
@property(nonatomic, copy) NSArray<SCDeviceService *> *services;
@property(nonatomic, copy) NSString *targetHost, *targetName;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL automaticConnection;
@property(nonatomic, readwrite) SCDeviceConnectionPhase phase;
@property(nonatomic, readwrite) BOOL paired, error;
@property(nonatomic, copy, readwrite) NSString *message, *serial;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *properties;
@end

@implementation SCDeviceConnection
- (NSString *)pairedGUID { return self.paired ? self.targetName : nil; }
- (instancetype)initWithExecutable:(NSString *)executable {
    self = [super init];
    if (self) {
        _executable = [executable copy];
        _services = @[];
        _properties = @{};
        _message = @"";
    }
    return self;
}
- (BOOL)busy {
    switch (self.phase) {
        case SCDeviceConnectionPairing:
        case SCDeviceConnectionWaitingForService:
        case SCDeviceConnectionConnecting:
        case SCDeviceConnectionVerifying:
        case SCDeviceConnectionIdentifying: return YES;
        default: return NO;
    }
}
- (void)transition:(SCDeviceConnectionPhase)phase message:(NSString *)message {
    self.phase = phase;
    self.message = message;
    self.error = phase == SCDeviceConnectionFailed;
    if (self.changed) { self.changed(); }
}
- (void)invalidateOperation {
    ++self.generation;
    [self.operation cancel];
    self.operation = nil;
    [self.deadline invalidate];
    self.deadline = nil;
}
- (void)cancel {
    [self invalidateOperation];
    self.phase = SCDeviceConnectionIdle;
    self.paired = self.error = NO;
    self.message = @"";
    self.serial = self.targetHost = self.targetName = nil;
    self.properties = @{};
}
- (void)dealloc { [self.operation cancel]; [self.deadline invalidate]; }
- (void)updateServices:(NSArray<SCDeviceService *> *)services {
    self.services = services;
    if (self.phase != SCDeviceConnectionWaitingForService) { return; }
    SCDeviceService *target = SCDeviceConnectionService(services, self.targetName, self.targetHost);
    if (target) {
        [self connectEndpoint:target.endpoint automatic:YES];
    }
}
- (void)pairEndpoint:(NSString *)endpoint secret:(NSString *)secret
        serviceName:(NSString *)name requireGUID:(BOOL)requireGUID {
    [self cancel];
    if (!SCDeviceEndpoint(endpoint, nil) || !secret.length) {
        [self transition:SCDeviceConnectionFailed message:@"Check the pairing address and code."];
        return;
    }
    self.targetHost = SCDeviceHost(endpoint);
    self.targetName = name;
    NSUInteger generation = self.generation;
    [self transition:SCDeviceConnectionPairing message:@"Pairing…"];
    __weak SCDeviceConnection *weakSelf = self;
    self.operation = [SCDeviceCommand run:self.executable arguments:@[@"pair", endpoint]
        input:[secret stringByAppendingString:@"\n"] timeout:20 completion:^(NSString *output, int status) {
        SCDeviceConnection *connection = weakSelf;
        if (!connection || generation != connection.generation) { return; }
        if (!SCDevicePairSucceeded(output, status)) {
            NSString *message = requireGUID ? @"Pairing failed. Choose New QR code and scan again."
                : status == -3 ? @"Pairing timed out. Open a new code and try again."
                : @"Pairing failed. Check the address and code.";
            [connection transition:SCDeviceConnectionFailed message:message];
            return;
        }
        connection.paired = YES;
        connection.targetName = SCDevicePairingGUID(output, status) ?: name;
        if (requireGUID && !connection.targetName.length) {
            [connection needsAddress];
            return;
        }
        connection.deadline = [NSTimer timerWithTimeInterval:12 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            SCDeviceConnection *current = weakSelf;
            if (current && generation == current.generation &&
                    current.phase == SCDeviceConnectionWaitingForService) {
                [current needsAddress];
            }
        }];
        [NSRunLoop.mainRunLoop addTimer:connection.deadline forMode:NSRunLoopCommonModes];
        [connection transition:SCDeviceConnectionWaitingForService message:@"Paired. Connecting…"];
        // The pairing endpoint is never reused as the connection endpoint.
        [connection updateServices:connection.services];
    }];
}
- (void)needsAddress {
    [self.deadline invalidate];
    self.deadline = nil;
    [self transition:SCDeviceConnectionNeedsAddress
        message:@"Paired. Enter the connection port from Wireless debugging."];
}
- (void)connectEndpoint:(NSString *)endpoint {
    [self connectEndpoint:endpoint automatic:NO];
}
- (void)connectEndpoint:(NSString *)endpoint automatic:(BOOL)automatic {
    [self invalidateOperation];
    self.serial = nil;
    self.properties = @{};
    self.automaticConnection = automatic;
    if (!SCDeviceEndpoint(endpoint, nil)) {
        [self transition:SCDeviceConnectionFailed message:@"Enter a valid connection address."];
        return;
    }
    NSUInteger generation = self.generation;
    [self transition:SCDeviceConnectionConnecting message:@"Connecting…"];
    __weak SCDeviceConnection *weakSelf = self;
    self.operation = [SCDeviceCommand run:self.executable arguments:@[@"connect", endpoint]
        input:nil timeout:8 completion:^(NSString *output, int status) {
        SCDeviceConnection *connection = weakSelf;
        if (!connection || generation != connection.generation) { return; }
        if (!SCDeviceConnectSucceeded(output, status)) {
            if (connection.paired && connection.automaticConnection) {
                [connection needsAddress];
            } else {
                [connection transition:SCDeviceConnectionFailed
                    message:@"Could not connect. Check Wi-Fi and the connection port."];
            }
            return;
        }
        [connection verifyEndpoint:endpoint generation:generation];
    }];
}
- (void)verifyEndpoint:(NSString *)endpoint generation:(NSUInteger)generation {
    [self transition:SCDeviceConnectionVerifying message:@"Connecting…"];
    __weak SCDeviceConnection *weakSelf = self;
    self.operation = [SCDeviceCommand run:self.executable arguments:@[@"-s", endpoint, @"get-state"]
        input:nil timeout:5 completion:^(NSString *output, int status) {
        SCDeviceConnection *connection = weakSelf;
        if (!connection || generation != connection.generation) { return; }
        NSString *state = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (status || ![state isEqualToString:@"device"]) {
            [connection transition:SCDeviceConnectionFailed
                message:@"Device is not ready. Allow debugging and try again."];
        } else {
            [connection identifyEndpoint:endpoint generation:generation];
        }
    }];
}
- (void)identifyEndpoint:(NSString *)endpoint generation:(NSUInteger)generation {
    [self transition:SCDeviceConnectionIdentifying message:@"Identifying device…"];
    __weak SCDeviceConnection *weakSelf = self;
    self.operation = [SCDeviceCommand run:self.executable arguments:@[@"-s", endpoint, @"shell", @"getprop"]
        input:nil timeout:5 completion:^(NSString *output, int status) {
        SCDeviceConnection *connection = weakSelf;
        if (!connection || generation != connection.generation) { return; }
        NSDictionary *properties = status ? @{} : SCDeviceProperties(output);
        if (!properties.count) {
            [connection transition:SCDeviceConnectionFailed message:@"Could not identify device. Try again."];
        } else {
            connection.serial = endpoint;
            connection.properties = properties;
            [connection transition:SCDeviceConnectionReady message:@""];
        }
    }];
}
@end
