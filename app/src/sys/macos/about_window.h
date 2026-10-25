#import <AppKit/AppKit.h>

@interface SCAboutWindowController : NSWindowController
- (instancetype)initWithBundle:(NSBundle *)bundle;
@property(nonatomic, readonly) BOOL anyWindowVisible;
@end
