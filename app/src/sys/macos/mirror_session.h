#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSBundle *SCMirrorHostBundle(void);
NSString *SCMirrorHostBundleIdentifier(void);
void SCMirrorInstallCleanup(void);
void SCMirrorMarkReady(void);

@class NSRunningApplication;
@interface SCMirrorSession : NSObject
@property(nonatomic, copy, readonly) NSString *serial;
@property(nonatomic, strong, readonly) NSRunningApplication *application;
@property(nonatomic, readonly) BOOL ready;
@end
NSArray<SCMirrorSession *> *SCMirrorRunningSessions(void);
NSArray<NSString *> *SCMirrorArguments(NSArray<NSString *> *original, NSString *serial);

@interface SCMirrorPreparation : NSObject
- (void)cancel;
@end

// A disposable app gives each mirror its own public macOS display name.
@interface SCMirrorLaunch : NSObject
@property(nonatomic, strong, readonly) NSURL *bundleURL;
@property(nonatomic, strong, readonly) NSURL *executableURL;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;
+ (nullable instancetype)prepareWithName:(NSString *)name serial:(NSString *)serial hostBundle:(NSBundle *)host error:(NSError **)error;
// Copies and signs on a worker queue. Completion runs exactly once on main,
// including cancellation; a cancelled preparation cleans up its temporary app.
+ (SCMirrorPreparation *)prepareWithName:(NSString *)name serial:(NSString *)serial
    hostBundle:(NSBundle *)host completion:(void (^)(SCMirrorLaunch * _Nullable launch,
                                                    NSError * _Nullable error))completion;
- (void)cleanup;
@end
NS_ASSUME_NONNULL_END
