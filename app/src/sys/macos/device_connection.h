#import <Foundation/Foundation.h>
#import "device_support.h"

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSUInteger, SCDeviceConnectionPhase) {
    SCDeviceConnectionIdle,
    SCDeviceConnectionPairing,
    SCDeviceConnectionWaitingForService,
    SCDeviceConnectionConnecting,
    SCDeviceConnectionVerifying,
    SCDeviceConnectionIdentifying,
    SCDeviceConnectionReady,
    SCDeviceConnectionNeedsAddress,
    SCDeviceConnectionFailed,
};

// Main-thread connection workflow. The view supplies discovered services and
// observes transitions; this object owns commands, deadlines and cancellation.
// It never creates windows, launches mirrors or persists pairing secrets.
@interface SCDeviceConnection : NSObject
@property(nonatomic, readonly) SCDeviceConnectionPhase phase;
@property(nonatomic, readonly) BOOL busy, paired, error;
@property(nonatomic, copy, readonly) NSString *message;
@property(nonatomic, copy, readonly, nullable) NSString *serial;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *properties;
@property(nonatomic, copy, nullable) void (^changed)(void);
- (instancetype)initWithExecutable:(NSString *)executable;
- (void)updateServices:(NSArray<SCDeviceService *> *)services;
- (void)pairEndpoint:(NSString *)endpoint secret:(NSString *)secret
        serviceName:(nullable NSString *)name requireGUID:(BOOL)requireGUID;
- (void)connectEndpoint:(NSString *)endpoint;
// Silent cancellation also invalidates all queued completions.
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
