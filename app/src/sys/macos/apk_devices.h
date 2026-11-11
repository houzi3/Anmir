#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCAPKTarget : NSObject
@property(nonatomic, copy, readonly) NSString *serial;
@property(nonatomic, copy, readonly) NSString *model;
@property(nonatomic, copy, readonly) NSString *transport;
@property(nonatomic, copy, readonly, nullable) NSString *identity;
@property(nonatomic, copy, readonly, nullable) NSString *transportID;
- (instancetype)init NS_UNAVAILABLE;
// A transport ID selects the connection from this ADB snapshot. IDs may be
// reused when ADB restarts, so revalidate the device before a deferred install.
- (NSArray<NSString *> *)selectionArguments;
@end

// Retain while discovery is needed. Use and receive results on the main
// thread. Starting again or cancelling discards the previous completion.
@interface SCAPKDeviceDiscovery : NSObject
- (instancetype)initWithADB:(NSString *)adb;
- (instancetype)init NS_UNAVAILABLE;
- (void)startWithCompletion:(void (^)(NSArray<SCAPKTarget *> *targets,
                                      int status))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
