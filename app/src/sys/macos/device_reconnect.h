#import "device_relay.h"

NS_ASSUME_NONNULL_BEGIN
// Main-thread owner of remembered company-network phones, independent of QR UI.
@interface SCDeviceReconnect : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, copy, nullable) BOOL (^restoreMirror)(NSString *serial, NSDictionary *properties);
- (instancetype)initWithExecutable:(NSString *)executable defaults:(NSUserDefaults *)defaults;
- (BOOL)rememberRelay:(SCDeviceRelay *)relay guid:(NSString *)guid serial:(NSString *)serial properties:(NSDictionary *)properties;
- (void)mirroringSerial:(NSString *)serial properties:(NSDictionary *)properties;
- (void)mirrorEnded:(NSString *)serial properties:(NSDictionary *)properties unexpected:(BOOL)unexpected;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
