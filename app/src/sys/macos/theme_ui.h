#import <AppKit/AppKit.h>

// All windows use this factory so icons, tooltips and cross-process theme
// updates stay in sync. The icon always describes the destination theme.
NSButton *SCThemeButton(void);
