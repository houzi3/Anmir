#import "finder_device_menu.h"

NSString *const SCFinderDeviceSerialKey = @"serial";
NSString *const SCFinderDeviceModelKey = @"model";
NSString *const SCFinderDeviceTransportKey = @"transport";

BOOL SCFinderSelectionIsSingleAPK(NSArray<NSURL *> *urls) {
    if (urls.count != 1) {
        return NO;
    }
    NSURL *url = urls.firstObject;
    NSNumber *regular = nil;
    [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
    return url.fileURL && regular.boolValue
        && [url.pathExtension caseInsensitiveCompare:@"apk"] == NSOrderedSame;
}

NSArray<NSDictionary<NSString *, NSString *> *> *SCFinderParseADBDevices(
        NSString *output) {
    NSMutableArray *devices = [NSMutableArray array];
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceCharacterSet;
    for (NSString *rawLine in [output componentsSeparatedByCharactersInSet:
            NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:whitespace];
        if (!line.length || [line hasPrefix:@"List of devices attached"]) {
            continue;
        }
        NSArray *rawFields = [line componentsSeparatedByCharactersInSet:whitespace];
        NSMutableArray<NSString *> *fields = [NSMutableArray array];
        for (NSString *field in rawFields) {
            if (field.length) {
                [fields addObject:field];
            }
        }
        if (fields.count < 2 || ![fields[1] isEqualToString:@"device"]) {
            continue;
        }
        NSString *serial = fields[0];
        NSString *model = nil;
        for (NSString *field in fields) {
            if ([field hasPrefix:@"model:"] && field.length > 6) {
                model = [[field substringFromIndex:6]
                    stringByReplacingOccurrencesOfString:@"_" withString:@" "];
                break;
            }
        }
        NSString *transport = [serial hasPrefix:@"emulator-"] ? @"Emulator"
            : [serial containsString:@":"] ? @"Wi-Fi" : @"USB";
        [devices addObject:@{
            SCFinderDeviceSerialKey: serial,
            SCFinderDeviceModelKey: model.length ? model : @"Android device",
            SCFinderDeviceTransportKey: transport,
        }];
    }
    return devices;
}
