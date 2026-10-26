#import <AppKit/AppKit.h>
@class SCDeviceReconnect;

@interface SCDeviceWiFiController : NSWindowController
@property(nonatomic, strong) SCDeviceReconnect *reconnect;
- (instancetype)initWithExecutable:(NSString *)executable
                            mirror:(BOOL (^)(NSString *serial, NSDictionary<NSString *, NSString *> *properties))mirror;
- (void)presentFrom:(NSWindow *)parent;
- (void)presentQRCodeFrom:(NSWindow *)parent;
@end
