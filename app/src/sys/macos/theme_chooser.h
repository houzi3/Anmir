#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
// UI only: selection previews are reported to the caller; this window neither
// reads nor writes preferences and is independently testable without SDL.
@interface SCThemeChooser : NSWindowController
@property(nonatomic, copy, readonly) NSString *selection;
@property(nonatomic, copy, nullable) void (^change)(NSString *choice);
@end
NS_ASSUME_NONNULL_END
