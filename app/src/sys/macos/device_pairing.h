#import <AppKit/AppKit.h>
#import "device_support.h"

NS_ASSUME_NONNULL_BEGIN

NSImage * _Nullable SCDeviceQRCodeImage(NSString *payload);

// Each QR code names one pairing service and carries a fresh shared secret.
// Neither value is persisted or passed on the adb command line.
@interface SCDeviceQRPairing : NSObject
@property(nonatomic, copy, readonly) NSString *serviceName;
@property(nonatomic, copy, readonly) NSString *password;
@property(nonatomic, copy, readonly) NSString *payload;
@property(nonatomic, strong, readonly, nullable) NSImage *image;
- (instancetype)initWithServiceName:(NSString *)name;
- (nullable SCDeviceService *)serviceIn:(NSArray<SCDeviceService *> *)services;
@end

NSString * _Nullable SCDevicePairingGUID(NSString *output, int status);
SCDeviceService * _Nullable SCDeviceConnectionService(
    NSArray<SCDeviceService *> *services, NSString * _Nullable guid,
    NSString * _Nullable host);

NS_ASSUME_NONNULL_END
