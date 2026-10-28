#import <Foundation/Foundation.h>
#include <assert.h>
#import "sys/macos/finder_device_menu.h"

int main(void) {
    @autoreleasepool {
        NSString *output = @"List of devices attached\n"
            "USB123 device product:foo model:Google_Pixel_7a device:lynx transport_id:1\n"
            "192.168.1.10:5555 device product:foo model:Pixel_8 transport_id:2\n"
            "emulator-5554 device product:sdk model:sdk_gphone64_arm64 transport_id:3\n"
            "BAD unauthorized usb:1-1 transport_id:4\n"
            "OFF offline transport_id:5\n";
        NSArray *devices = SCFinderParseADBDevices(output);
        assert(devices.count == 3);
        assert([devices[0][SCFinderDeviceSerialKey] isEqualToString:@"USB123"]);
        assert([devices[0][SCFinderDeviceModelKey] isEqualToString:@"Google Pixel 7a"]);
        assert([devices[0][SCFinderDeviceTransportKey] isEqualToString:@"USB"]);
        assert([devices[1][SCFinderDeviceTransportKey] isEqualToString:@"Wi-Fi"]);
        assert([devices[2][SCFinderDeviceTransportKey] isEqualToString:@"Emulator"]);

        NSString *directory = [NSTemporaryDirectory()
            stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:directory
            withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *apk = [directory stringByAppendingPathComponent:@"demo.APK"];
        assert([NSData.data writeToFile:apk atomically:YES]);
        NSURL *apkURL = [NSURL fileURLWithPath:apk];
        assert(SCFinderSelectionIsSingleAPK(@[apkURL]));
        assert(!SCFinderSelectionIsSingleAPK(@[]));
        assert(!SCFinderSelectionIsSingleAPK(@[apkURL, apkURL]));
        assert(!SCFinderSelectionIsSingleAPK(@[[NSURL fileURLWithPath:directory]]));
        [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    }
    return 0;
}
