#import <Foundation/Foundation.h>

@class SCAPKTarget;

NS_ASSUME_NONNULL_BEGIN

@interface SCAPKBatchController : NSObject
- (instancetype)initWithAPK:(NSString *)apk adb:(NSString *)adb
    targets:(NSArray<SCAPKTarget *> *)targets completion:(void (^)(void))completion;
- (void)show;
@end

NS_ASSUME_NONNULL_END
