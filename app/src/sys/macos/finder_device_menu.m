#import "finder_device_menu.h"

NSString *const SCFinderDeviceSerialKey = @"serial";
NSString *const SCFinderDeviceModelKey = @"model";
NSString *const SCFinderDeviceTransportKey = @"transport";
NSString *const SCFinderDeviceTransportIDKey = @"transport_id";

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
    NSCharacterSet *nonDigits = [[NSCharacterSet
        characterSetWithCharactersInString:@"0123456789"] invertedSet];
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
        NSString *transportID = nil;
        for (NSString *field in fields) {
            if ([field hasPrefix:@"model:"] && field.length > 6) {
                model = [[field substringFromIndex:6]
                    stringByReplacingOccurrencesOfString:@"_" withString:@" "];
            } else if ([field hasPrefix:@"transport_id:"]) {
                NSString *value = [field substringFromIndex:13];
                if (value.length && ![value hasPrefix:@"0"]
                        && [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
                    transportID = value;
                }
            }
        }
        BOOL wireless = [serial containsString:@":"]
            || [serial containsString:@"adb-tls-connect"];
        NSString *transport = [serial hasPrefix:@"emulator-"] ? @"Emulator"
            : wireless ? @"Wi-Fi" : @"USB";
        NSMutableDictionary *device = [@{
            SCFinderDeviceSerialKey: serial,
            SCFinderDeviceModelKey: model.length ? model : @"Android device",
            SCFinderDeviceTransportKey: transport,
        } mutableCopy];
        if (transportID) {
            device[SCFinderDeviceTransportIDKey] = transportID;
        }
        [devices addObject:[device copy]];
    }
    return devices;
}
