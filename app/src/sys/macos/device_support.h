#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *SCDeviceExecutable(const char *path);
NSString * _Nullable SCDeviceEndpoint(NSString *address, NSString * _Nullable port);
NSString * _Nullable SCDeviceHost(NSString *endpoint);
BOOL SCDevicePairingCodeValid(NSString *code);
BOOL SCDevicePairSucceeded(NSString *output, int status);
BOOL SCDeviceConnectSucceeded(NSString *output, int status);
NSDictionary<NSString *, NSString *> *SCDeviceProperties(NSString *output);
NSString * _Nullable SCDevicePhysicalIdentity(NSDictionary<NSString *, NSString *> *properties);
NSArray<NSArray<NSString *> *> *SCDeviceTransportGroups(
    NSArray<NSString *> *serials, NSDictionary<NSString *, NSString *> *identities,
    NSSet<NSString *> *identifying);

// All completions and public lifecycle methods run on the main thread.
// The pairing code is sent over stdin, never in process arguments or logs.
@interface SCDeviceCommand : NSObject
@property(nonatomic, readonly) BOOL running;
+ (instancetype)run:(NSString *)executable
          arguments:(NSArray<NSString *> *)arguments
              input:(nullable NSString *)input
            timeout:(NSTimeInterval)timeout
         completion:(void (^)(NSString *output, int status))completion;
- (void)cancel;
@end

@interface SCDeviceWatcher : NSObject
@property(nonatomic, readonly) BOOL connected;
@property(nonatomic, copy) void (^changed)(void);
@property(nonatomic, copy) void (^availabilityChanged)(void);
- (instancetype)initWithExecutable:(NSString *)executable;
- (void)start;
- (void)stop;
@end

@interface SCDeviceService : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *endpoint;
@property(nonatomic, copy) NSString *host;
@property(nonatomic) BOOL pairing;
+ (NSArray<SCDeviceService *> *)parse:(NSString *)output;
@end

NS_ASSUME_NONNULL_END
