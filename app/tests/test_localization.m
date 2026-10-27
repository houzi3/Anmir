#import <Foundation/Foundation.h>
#import "sys/macos/localization.h"
#include "localization.h"
#include <assert.h>
#include <string.h>

@interface SCLocalizationFixture : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *input;
@end
@implementation SCLocalizationFixture
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        NSBundle *resources = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        assert(resources);
        SCLocalizationInitialize(resources, @"en");
        assert([SCResolveLanguage(@"system", @[@"ja-JP", @"zh-TW", @"en"]) isEqualToString:@"zh-Hant"]);
        assert([SCResolveLanguage(@"system", @[@"zh-Hans-TW"]) isEqualToString:@"zh-Hans"]);
        assert([SCResolveLanguage(@"system", @[@"zh_HK"]) isEqualToString:@"zh-Hant"]);
        assert([SCResolveLanguage(@"system", @[@"zh-SG"]) isEqualToString:@"zh-Hans"]);
        assert([SCResolveLanguage(@"system", @[@"de", @"ja"]) isEqualToString:@"en"]);
        assert([SCResolveLanguage(@"en", @[@"zh-TW"]) isEqualToString:@"en"]);
        assert([SCLocalized(@"Unknown identifier") isEqualToString:@"Unknown identifier"]);
        const char *oldToast = sc_localize("Recording saved");
        SCLocalizationFixture *fixture = [[SCLocalizationFixture alloc] init];
        fixture.input = @"012345";
        SCBind(fixture, @"text", @"Connect");
        assert([fixture.text isEqualToString:@"Connect"]);
        SCUseLanguage(@"zh-Hans");
        assert([fixture.text isEqualToString:@"连接"]);
        assert([fixture.input isEqualToString:@"012345"]);
        // Recovery actions and company-network guidance also update live.
        SCBind(fixture, @"text", @"Fix connection");
        assert([fixture.text isEqualToString:@"修复连接"]);
        assert([SCLocalized(@"Install Anmir Connect App; skip if installed")
            isEqualToString:@"安装 Anmir Connect App，已安装可忽略"]);
        SCUseLanguage(@"zh-Hant");
        assert([fixture.text isEqualToString:@"修復連線"]);
        assert([SCLocalized(@"Install Anmir Connect App; skip if installed")
            isEqualToString:@"安裝 Anmir Connect App，已安裝可略過"]);
        SCBind(fixture, @"text", @"Connect");
        assert([fixture.text isEqualToString:@"連線"]);
        assert(!strcmp(oldToast, "Recording saved"));
        assert(!strcmp(sc_localize("Recording saved"), "錄影已儲存"));
        const char *oldHantToast;
        @autoreleasepool { oldHantToast = sc_localize("Recording saved"); }
        SCBindFormat(fixture, @"text", @"Details for %@", @[@"Phone %@ 7"]);
        assert([fixture.text isEqualToString:@"Phone %@ 7 的詳細資訊"]);
        SCUseLanguage(@"en");
        assert(!strcmp(oldHantToast, "錄影已儲存"));
        assert([fixture.text isEqualToString:@"Details for Phone %@ 7"]);
        SCBindFormat(fixture, @"text", @"%2$@ / %1$@", @[@"Phone %@", @"Tablet"]);
        assert([fixture.text isEqualToString:@"Tablet / Phone %@"]);
        SCBindFormat(fixture, @"text", @"%@ / %@", @[@"Phone %@", @"Tablet"]);
        assert([fixture.text isEqualToString:@"Phone %@ / Tablet"]);
        // Presentation bindings are weak and cannot keep closed UI alive.
        __weak SCLocalizationFixture *released;
        @autoreleasepool {
            SCLocalizationFixture *temporary = [[SCLocalizationFixture alloc] init];
            released = temporary; SCBind(temporary, @"text", @"Connect");
        }
        assert(!released);
        SCUseLanguage(@"zh-Hans");
        puts("Language matching, live bindings, input preservation, fallback and C string lifetime passed.");
    }
    return 0;
}
