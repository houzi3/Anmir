#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SCFinderDeviceSerialKey;
extern NSString *const SCFinderDeviceModelKey;
extern NSString *const SCFinderDeviceTransportKey;
extern NSString *const SCFinderDeviceTransportIDKey;

BOOL SCFinderSelectionIsSingleAPK(NSArray<NSURL *> *urls);
NSArray<NSDictionary<NSString *, NSString *> *> *SCFinderParseADBDevices(
    NSString *output);

NS_ASSUME_NONNULL_END
