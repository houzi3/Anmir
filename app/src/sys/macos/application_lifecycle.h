#import <AppKit/AppKit.h>

// Install after SDL initializes AppKit. Preserve SDL's delegate and event loop.
void SCApplicationLifecycleInstall(void (^showDevices)(void),
                                   BOOL (^openFile)(NSString *path));
BOOL SCApplicationHasWindows(void);
void SCApplicationRequestQuit(void);
