#import <CoreImage/CoreImage.h>
#import "sys/macos/device_pairing.h"
#include <assert.h>

static SCDeviceService *service(NSString *name, NSString *endpoint, BOOL pairing) {
    SCDeviceService *value = [[SCDeviceService alloc] init];
    value.name = name;
    value.endpoint = endpoint;
    value.host = SCDeviceHost(endpoint);
    value.pairing = pairing;
    return value;
}

static void testQR(void) {
    SCDeviceQRPairing *qr = [[SCDeviceQRPairing alloc] init];
    SCDeviceQRPairing *next = [[SCDeviceQRPairing alloc] init];
    assert(qr.image && [qr.serviceName hasPrefix:@"studio-"]);
    assert(qr.serviceName.length == 17 && qr.password.length == 20);
    assert(![qr.serviceName isEqualToString:next.serviceName]);
    assert(![qr.password isEqualToString:next.password]);

    // Decode the actual generated pixels, including its white quiet zone.
    // This checks the Android QR payload rather than only its string builder.
    CGImageRef pixels = [qr.image CGImageForProposedRect:NULL context:nil hints:nil];
    CIImage *image = [CIImage imageWithCGImage:pixels];
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
        options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
    NSArray *features = [detector featuresInImage:image];
    assert(features.count == 1);
    NSString *decoded = ((CIQRCodeFeature *)features.firstObject).messageString;
    NSString *expected = [NSString stringWithFormat:@"WIFI:T:ADB;S:%@;P:%@;;", qr.serviceName, qr.password];
    assert([decoded isEqualToString:expected]);

    SCDeviceService *other = service(next.serviceName, @"192.168.1.42:42187", YES);
    SCDeviceService *wrongType = service(qr.serviceName, @"192.168.1.42:37123", NO);
    SCDeviceService *target = service(qr.serviceName, @"192.168.1.43:42187", YES);
    assert((![qr serviceIn:@[other, wrongType]]));
    assert(([qr serviceIn:@[other, wrongType, target]] == target));
    assert(![next serviceIn:@[target]]);
}

static void testConnectionIdentity(void) {
    NSString *output = @"Successfully paired to 192.168.1.42:42187 [guid=adb-phone]\n";
    assert([SCDevicePairingGUID(output, 0) isEqualToString:@"adb-phone"]);
    assert(!SCDevicePairingGUID(output, 1));
    assert(!SCDevicePairingGUID(@"failed [guid=adb-phone]", 0));
    assert(!SCDevicePairingGUID(@"Successfully paired to device [guid=]", 0));
    assert(!SCDevicePairingGUID(@"Successfully paired to device", 0));

    SCDeviceService *pairing = service(@"adb-phone", @"192.168.1.42:42187", YES);
    SCDeviceService *other = service(@"adb-other", @"192.168.1.42:37123", NO);
    SCDeviceService *moved = service(@"adb-phone", @"192.168.1.99:39217", NO);
    assert(!SCDeviceConnectionService(@[pairing], @"adb-phone", @"192.168.1.42"));
    assert(!SCDeviceConnectionService(@[other], @"adb-phone", @"192.168.1.42"));
    assert(SCDeviceConnectionService(@[other, moved], @"adb-phone", @"192.168.1.42") == moved);
    assert(SCDeviceConnectionService(@[pairing, other], nil, @"192.168.1.42") == other);
    SCDeviceService *ambiguous = service(@"adb-third", @"192.168.1.42:39217", NO);
    assert(!SCDeviceConnectionService(@[other, ambiguous], nil, @"192.168.1.42"));
}

int main(void) {
    @autoreleasepool {
        testQR();
        testConnectionIdentity();
        puts("Device pairing tests passed.");
    }
    return 0;
}
