#import "device_support.h"

NS_ASSUME_NONNULL_BEGIN
extern const NSTimeInterval SCDeviceRelayLifetime;
NSArray<NSString *> *SCDeviceRelayAddresses(void);

// QR bootstrap, then an independently authenticated, paired-device callback.
// Addresses always come from the TCP peer, never from a reported host.
@interface SCDeviceRelay : NSObject
@property(nonatomic, copy, readonly) NSString *serviceName;
@property(nonatomic, readonly) uint16_t port;
@property(nonatomic, copy, nullable) void (^received)(NSArray<SCDeviceService *> *services);
@property(nonatomic, copy, nullable) void (^reconnected)(NSArray<SCDeviceService *> *services, BOOL retry);
@property(atomic, copy, readonly, nullable) NSDictionary *registration;
+ (nullable instancetype)listenOnHost:(NSString *)host error:(NSError **)error;
+ (nullable instancetype)resumeRegistration:(NSDictionary *)registration error:(NSError **)error;
// Only call after ADB pairing, TLS connection and physical identity verification.
- (void)registerGUID:(NSString *)guid identity:(NSString *)identity peer:(NSString *)peer;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
