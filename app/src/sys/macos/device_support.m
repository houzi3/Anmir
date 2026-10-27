#import "device_support.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <signal.h>

NSString *SCDeviceExecutable(const char *path) {
    NSString *value = path ? [NSString stringWithUTF8String:path] : @"adb";
    if ([value containsString:@"/"]) {
        return value.stringByStandardizingPath;
    }
    for (NSString *directory in [NSProcessInfo.processInfo.environment[@"PATH"]
            componentsSeparatedByString:@":"]) {
        NSString *candidate = [directory stringByAppendingPathComponent:value];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return value;
}

static BOOL SCDigits(NSString *value) {
    return value.length && [value rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]
            invertedSet]].location == NSNotFound;
}

NSString *SCDeviceEndpoint(NSString *address, NSString *port) {
    if (!address.length) {
        return nil;
    }
    BOOL embeddedPort = !port;
    NSString *host = [address stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!port) {
        NSRange colon = [host rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location == NSNotFound) {
            return nil;
        }
        port = [host substringFromIndex:colon.location + 1];
        host = [host substringToIndex:colon.location];
    }
    port = [port stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!SCDigits(port) || port.length > 5 || port.integerValue < 1
            || port.integerValue > 65535) {
        return nil;
    }
    BOOL bracketed = [host hasPrefix:@"["] && [host hasSuffix:@"]"];
    if (bracketed) {
        host = [host substringWithRange:NSMakeRange(1, host.length - 2)];
    } else if (embeddedPort && [host containsString:@":"]) {
        return nil;
    }
    struct in_addr ipv4;
    struct in6_addr ipv6;
    // Link-local IPv6 may have an interface zone. Keep it in the endpoint,
    // but validate the address and zone independently.
    NSArray<NSString *> *parts = [host componentsSeparatedByString:@"%"];
    NSString *literal = parts.firstObject;
    if (parts.count > 2 || (parts.count == 2 && (!parts[1].length
            || [parts[1] rangeOfCharacterFromSet:
                [[NSCharacterSet characterSetWithCharactersInString:
                    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"]
                    invertedSet]].location != NSNotFound))) {
        return nil;
    }
    BOOL v4 = inet_pton(AF_INET, literal.UTF8String, &ipv4) == 1;
    BOOL v6 = inet_pton(AF_INET6, literal.UTF8String, &ipv6) == 1;
    if ((!v4 && !v6) || (v4 && (bracketed || parts.count != 1))) {
        return nil;
    }
    return [NSString stringWithFormat:v6 ? @"[%@]:%ld" : @"%@:%ld",
        host, (long)port.integerValue];
}

NSString *SCDeviceHost(NSString *endpoint) {
    NSString *value = SCDeviceEndpoint(endpoint, nil);
    if (!value) {
        return nil;
    }
    NSRange colon = [value rangeOfString:@":" options:NSBackwardsSearch];
    NSString *host = [value substringToIndex:colon.location];
    return [host hasPrefix:@"["]
        ? [host substringWithRange:NSMakeRange(1, host.length - 2)] : host;
}

BOOL SCDevicePairingCodeValid(NSString *code) {
    return code.length == 6 && SCDigits(code);
}

BOOL SCDevicePairSucceeded(NSString *output, int status) {
    return !status && [output.lowercaseString containsString:@"successfully paired to"];
}

BOOL SCDeviceConnectSucceeded(NSString *output, int status) {
    if (status) {
        return NO;
    }
    for (NSString *line in [output.lowercaseString componentsSeparatedByString:@"\n"]) {
        NSString *value = [line stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([value hasPrefix:@"connected to "]
                || [value hasPrefix:@"already connected to "]) {
            return YES;
        }
    }
    return NO;
}

NSDictionary<NSString *, NSString *> *SCDeviceProperties(NSString *output) {
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if (![line hasPrefix:@"["]) {
            continue;
        }
        NSRange separator = [line rangeOfString:@"]: ["];
        NSRange end = [line rangeOfString:@"]" options:NSBackwardsSearch];
        if (separator.location == NSNotFound || end.location == NSNotFound
                || end.location < separator.location + 4) {
            continue;
        }
        NSString *key = [line substringWithRange:NSMakeRange(1, separator.location - 1)];
        properties[key] = [line substringWithRange:NSMakeRange(separator.location + 4,
            end.location - separator.location - 4)];
    }
    return properties;
}

NSString *SCDevicePhysicalIdentity(NSDictionary<NSString *, NSString *> *properties) {
    for (NSString *key in @[@"ro.serialno", @"ro.boot.serialno"]) {
        NSString *value = [properties[key] stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length && ![@[@"unknown", @"null", @"(null)"] containsObject:value.lowercaseString]) {
            return value;
        }
    }
    return nil;
}

NSArray<NSArray<NSString *> *> *SCDeviceTransportGroups(
        NSArray<NSString *> *serials, NSDictionary<NSString *, NSString *> *identities,
        NSSet<NSString *> *identifying) {
    NSMutableArray *groups = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *byIdentity = [NSMutableDictionary dictionary];
    for (NSString *serial in serials) {
        NSString *identity = identities[serial];
        // A newly discovered transport is not a new phone until its identity
        // lookup finishes. Publishing it early causes duplicate rows to flash.
        if (!identity.length && [identifying containsObject:serial]) { continue; }
        // Unknown identities remain separate; model names and IPs are not identities.
        NSString *key = identity.length ? [@"device:" stringByAppendingString:identity]
                                       : [@"transport:" stringByAppendingString:serial];
        NSMutableArray *group = byIdentity[key];
        if (!group) {
            group = [NSMutableArray array];
            byIdentity[key] = group;
            [groups addObject:group];
        }
        [group addObject:serial];
    }
    return groups;
}

static void SCStopTask(NSTask *task) {
    if (!task.running) {
        return;
    }
    [task terminate];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            if (task.running) {
                kill(task.processIdentifier, SIGKILL);
            }
        });
}

@interface SCDeviceCommand ()
@property(nonatomic, strong) NSTask *task;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL timedOut;
+ (instancetype)runSilently:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
                    timeout:(NSTimeInterval)timeout completion:(void (^)(int status))completion;
@end

@implementation SCDeviceCommand
- (BOOL)running {
    return !self.finished && !self.cancelled;
}

+ (instancetype)run:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
              input:(NSString *)input timeout:(NSTimeInterval)timeout
         completion:(void (^)(NSString *, int))completion {
    return [self run:executable arguments:arguments input:input timeout:timeout
        discardOutput:NO completion:completion];
}

+ (instancetype)runSilently:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
                    timeout:(NSTimeInterval)timeout completion:(void (^)(int))completion {
    return [self run:executable arguments:arguments input:nil timeout:timeout
        discardOutput:YES completion:^(NSString *output, int status) {
            (void)output;
            completion(status);
        }];
}

+ (instancetype)run:(NSString *)executable arguments:(NSArray<NSString *> *)arguments
              input:(NSString *)input timeout:(NSTimeInterval)timeout
      discardOutput:(BOOL)discardOutput completion:(void (^)(NSString *, int))completion {
    SCDeviceCommand *command = [[self alloc] init];
    NSTask *task = [[NSTask alloc] init];
    command.task = task;
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    NSPipe *output = discardOutput ? nil : [NSPipe pipe];
    task.standardOutput = output ?: NSFileHandle.fileHandleWithNullDevice;
    task.standardError = output ?: NSFileHandle.fileHandleWithNullDevice;
    NSPipe *inputPipe = input ? [NSPipe pipe] : nil;
    task.standardInput = inputPipe ?: NSFileHandle.fileHandleWithNullDevice;
    // Pairing may be cancelled, or ADB may exit, before the worker writes its
    // input. Suppress SIGPIPE only on this descriptor, so EPIPE is catchable.
    if (inputPipe && fcntl(inputPipe.fileHandleForWriting.fileDescriptor,
            F_SETNOSIGPIPE, 1) == -1) {
        command.finished = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@"Could not prepare ADB input.", -1);
        });
        return command;
    }
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        command.finished = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error.localizedDescription ?: @"Could not start ADB.", -1);
        });
        return command;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (!command.finished && !command.cancelled) {
                command.timedOut = YES;
                SCStopTask(task);
            }
        });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = nil;
        @try {
            if (inputPipe) {
                @try {
                    [inputPipe.fileHandleForWriting writeData:
                        [input dataUsingEncoding:NSUTF8StringEncoding]];
                } @finally {
                    [inputPipe.fileHandleForWriting closeFile];
                }
            }
            if (output) { data = [output.fileHandleForReading readDataToEndOfFile]; }
        } @catch (NSException *exception) {
            (void) exception;
        }
        [task waitUntilExit];
        [output.fileHandleForReading closeFile];
        NSString *text = [[NSString alloc] initWithData:data ?: NSData.data
            encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            command.finished = YES;
            if (command.cancelled) {
                completion(@"Cancelled.", -2);
            } else if (command.timedOut) {
                completion(@"ADB timed out. Try again.", -3);
            } else {
                completion(text, task.terminationStatus);
            }
        });
    });
    return command;
}

- (void)cancel {
    self.cancelled = YES;
    SCStopTask(self.task);
}
@end

@interface SCDeviceRecovery ()
@property(nonatomic, copy) NSString *executable;
@property(nonatomic) NSTimeInterval timeout;
@property(nonatomic, strong) SCDeviceCommand *operation;
@property(nonatomic, copy) void (^completion)(SCDeviceRecoveryResult);
@end

// The ADB server is shared by all windows in this process. Retaining the
// active operation also lets it safely finish after its requesting window closes.
static SCDeviceRecovery *SCActiveDeviceRecovery;

@implementation SCDeviceRecovery
- (instancetype)initWithExecutable:(NSString *)executable {
    return [self initWithExecutable:executable timeout:8];
}

- (instancetype)initWithExecutable:(NSString *)executable timeout:(NSTimeInterval)timeout {
    self = [super init];
    if (self) {
        _executable = [executable copy];
        _timeout = timeout > 0 ? timeout : 8;
    }
    return self;
}

+ (BOOL)isRunning {
    return SCActiveDeviceRecovery != nil;
}

- (void)finish:(SCDeviceRecoveryResult)result {
    if (SCActiveDeviceRecovery != self) { return; }
    void (^completion)(SCDeviceRecoveryResult) = self.completion;
    self.completion = nil;
    self.operation = nil;
    SCActiveDeviceRecovery = nil;
    if (completion) { completion(result); }
}

- (BOOL)start:(void (^)(SCDeviceRecoveryResult))completion {
    NSAssert(NSThread.isMainThread, @"ADB recovery must start on the main thread");
    if (SCActiveDeviceRecovery) { return NO; }
    SCActiveDeviceRecovery = self;
    self.completion = completion;
    // ADB may spawn a long-lived server inheriting stdout and stderr. Do not
    // capture pipes here: descendants holding them open would prevent the
    // command from completing after the client exits or times out.
    self.operation = [SCDeviceCommand runSilently:self.executable arguments:@[@"kill-server"]
        timeout:self.timeout completion:^(int status) {
            // The server may already have stopped even if the client failed or
            // timed out. Always attempt to restore it before reporting failure.
            SCDeviceRecoveryResult stopResult = !status ? SCDeviceRecoverySuccess
                : status == -3 ? SCDeviceRecoveryTimedOut : SCDeviceRecoveryStopFailed;
            self.operation = [SCDeviceCommand runSilently:self.executable arguments:@[@"start-server"]
                timeout:self.timeout completion:^(int startStatus) {
                    SCDeviceRecoveryResult startResult = !startStatus ? SCDeviceRecoverySuccess
                        : startStatus == -3 ? SCDeviceRecoveryTimedOut : SCDeviceRecoveryStartFailed;
                    // Keep diagnostics useful without recording endpoints or pairing secrets.
                    NSLog(@"Anmir ADB recovery: stop status=%d, start status=%d", status, startStatus);
                    [self finish:stopResult != SCDeviceRecoverySuccess ? stopResult : startResult];
                }];
        }];
    return YES;
}
@end

@interface SCDeviceWatcher ()
@property(nonatomic, copy) NSString *executable;
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, strong) NSFileHandle *reader;
@property(nonatomic, readwrite) BOOL connected;
@property(nonatomic) BOOL wanted;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger attempts;
@end

@implementation SCDeviceWatcher
- (instancetype)initWithExecutable:(NSString *)executable {
    self = [super init];
    if (self) {
        _executable = [executable copy];
    }
    return self;
}

- (void)setConnected:(BOOL)connected {
    if (_connected != connected) {
        _connected = connected;
        if (self.availabilityChanged) {
            self.availabilityChanged();
        }
    }
}

- (void)retry:(NSUInteger)generation {
    self.connected = NO;
    self.reader.readabilityHandler = nil;
    self.reader = nil;
    self.task = nil;
    NSUInteger attempt = MIN(self.attempts, 3);
    self.attempts = attempt + 1;
    NSTimeInterval delay = 1u << attempt;
    __weak SCDeviceWatcher *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            SCDeviceWatcher *watcher = weakSelf;
            if (watcher.wanted && watcher.generation == generation) {
                [watcher launch];
            }
        });
}

- (void)launch {
    NSUInteger generation = ++self.generation;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:self.executable];
    task.arguments = @[@"track-devices", @"-l"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    self.task = task;
    self.reader = pipe.fileHandleForReading;
    __weak SCDeviceWatcher *weakSelf = self;
    self.reader.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = nil;
        @try {
            data = handle.availableData;
        } @catch (NSException *exception) {
            (void) exception;
        }
        if (!data.length) {
            handle.readabilityHandler = nil;
            return;
        }
        // The stream is only a change signal. A debounced devices -l snapshot
        // is parsed by the existing scrcpy parser, independent of pipe framing.
        dispatch_async(dispatch_get_main_queue(), ^{
            SCDeviceWatcher *watcher = weakSelf;
            if (watcher.wanted && watcher.generation == generation) {
                watcher.connected = YES;
                watcher.attempts = 0;
                if (watcher.changed) {
                    watcher.changed();
                }
            }
        });
    };
    task.terminationHandler = ^(NSTask *completed) {
        (void) completed;
        dispatch_async(dispatch_get_main_queue(), ^{
            SCDeviceWatcher *watcher = weakSelf;
            if (watcher.wanted && watcher.generation == generation) {
                [watcher retry:generation];
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self retry:generation];
    }
}

- (void)start {
    if (!self.wanted) {
        self.wanted = YES;
        self.attempts = 0;
        [self launch];
    }
}

- (void)stop {
    self.wanted = NO;
    ++self.generation;
    self.reader.readabilityHandler = nil;
    self.reader = nil;
    SCStopTask(self.task);
    self.task = nil;
    self.connected = NO;
}
@end

@implementation SCDeviceService
+ (NSArray<SCDeviceService *> *)parse:(NSString *)output {
    NSMutableArray *services = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [[line componentsSeparatedByCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (parts.count != 3) {
            continue;
        }
        NSString *type = parts[1];
        BOOL pairing = [type isEqualToString:@"_adb-tls-pairing._tcp."]
            || [type isEqualToString:@"_adb-tls-pairing._tcp"];
        if (!pairing && ![type isEqualToString:@"_adb-tls-connect._tcp."]
                && ![type isEqualToString:@"_adb-tls-connect._tcp"]) {
            continue;
        }
        NSString *endpoint = SCDeviceEndpoint(parts[2], nil);
        // QR pairing selects an exact service name. Two advertisements may
        // share an endpoint without representing the same service instance.
        NSString *key = [NSString stringWithFormat:@"%@/%@/%@", parts[0],
            pairing ? @"pair" : @"connect", endpoint];
        if (!endpoint || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        SCDeviceService *service = [[self alloc] init];
        service.name = parts[0];
        service.endpoint = endpoint;
        service.host = SCDeviceHost(endpoint);
        service.pairing = pairing;
        [services addObject:service];
    }
    return services;
}
@end
