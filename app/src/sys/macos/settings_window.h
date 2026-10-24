#import <AppKit/AppKit.h>

// Presentation only. The coordinator owns persistence and process messages.
@interface SCSettingsWindowController : NSWindowController
@property(nonatomic, copy) void (^themeChanged)(NSString *choice);
@property(nonatomic, copy) void (^languageChanged)(NSString *choice);
@property(nonatomic, copy) void (^toolbarChanged)(BOOL visible);
- (instancetype)initWithTheme:(NSString *)theme language:(NSString *)language toolbarVisible:(BOOL)visible;
- (void)updateTheme:(NSString *)theme language:(NSString *)language toolbarVisible:(BOOL)visible;
@end
