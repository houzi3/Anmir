#import <AppKit/AppKit.h>

@interface SCDeviceWiFiController : NSWindowController
- (instancetype)initWithExecutable:(NSString *)executable
                            mirror:(BOOL (^)(NSString *serial, NSDictionary<NSString *, NSString *> *properties))mirror;
- (void)presentFrom:(NSWindow *)parent;
- (void)presentQRCodeFrom:(NSWindow *)parent;
@end
