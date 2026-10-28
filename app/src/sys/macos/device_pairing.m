#import "device_pairing.h"
#import <CoreImage/CoreImage.h>

static NSString *SCRandomPairingString(NSUInteger length) {
    // Alphanumeric values need no escaping in the Android WIFI QR format.
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    for (NSUInteger i = 0; i < length; ++i) {
        [result appendFormat:@"%c", alphabet[arc4random_uniform(sizeof(alphabet) - 1)]];
    }
    return result;
}

NSImage *SCDeviceQRCodeImage(NSString *payload) {
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:[payload dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *code = filter.outputImage;
    if (!code) { return nil; }
    // Keep a white four-module quiet zone in both light and dark mode.
    CIImage *white = [CIImage imageWithColor:[CIColor colorWithRed:1 green:1 blue:1 alpha:1]];
    CIImage *padded = [[code imageByCompositingOverImage:white]
        imageByCroppingToRect:CGRectInset(code.extent, -4, -4)];
    CIImage *scaled = [padded imageByApplyingTransform:CGAffineTransformMakeScale(8, 8)];
    CIContext *context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @YES}];
    CGImageRef image = [context createCGImage:scaled fromRect:scaled.extent];
    if (!image) { return nil; }
    NSImage *result = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(224, 224)];
    CGImageRelease(image);
    return result;
}

@implementation SCDeviceQRPairing
- (instancetype)init {
    return [self initWithServiceName:[@"studio-" stringByAppendingString:SCRandomPairingString(10)]];
}
- (instancetype)initWithServiceName:(NSString *)name {
    self = [super init];
    if (self) {
        _serviceName = [name copy];
        _password = SCRandomPairingString(20);
        _payload = [NSString stringWithFormat:@"WIFI:T:ADB;S:%@;P:%@;;", _serviceName, _password];
        _image = SCDeviceQRCodeImage(_payload);
    }
    return self;
}

- (SCDeviceService *)serviceIn:(NSArray<SCDeviceService *> *)services {
    for (SCDeviceService *service in services) {
        if (service.pairing && [service.name isEqualToString:self.serviceName]) {
            return service;
        }
    }
    return nil;
}
@end

NSString *SCDevicePairingGUID(NSString *output, int status) {
    if (!SCDevicePairSucceeded(output, status)) { return nil; }
    NSRange start = [output rangeOfString:@"[guid="];
    if (start.location == NSNotFound) { return nil; }
    NSString *suffix = [output substringFromIndex:NSMaxRange(start)];
    NSRange end = [suffix rangeOfString:@"]"];
    if (end.location == NSNotFound || !end.location) { return nil; }
    return [suffix substringToIndex:end.location];
}

SCDeviceService *SCDeviceConnectionService(NSArray<SCDeviceService *> *services,
                                         NSString *guid, NSString *host) {
    SCDeviceService *candidate = nil;
    NSUInteger candidates = 0;
    for (SCDeviceService *service in services) {
        if (service.pairing) { continue; }
        if (guid.length) {
            // A matching GUID still identifies the phone after its IP changes.
            // Never substitute another phone merely because its IP matches.
            if ([service.name isEqualToString:guid]) { return service; }
        } else if (host.length && [service.host isEqualToString:host]) {
            candidate = service;
            ++candidates;
        }
    }
    return !guid.length && candidates == 1 ? candidate : nil;
}
