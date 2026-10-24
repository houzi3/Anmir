#include "util/file.h"

#import <Foundation/Foundation.h>

#include "util/log.h"

char *
sc_file_get_local_resource_path(const char *name) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if (![[bundle objectForInfoDictionaryKey:@"CFBundlePackageType"]
                isEqualToString:@"APPL"]) {
            return sc_file_get_local_path(name);
        }
        const char *resources = bundle.resourcePath.fileSystemRepresentation;
        if (!resources) {
            LOGE("Could not resolve application resources");
            return NULL;
        }
        return sc_file_build_path(resources, name);
    }
}
