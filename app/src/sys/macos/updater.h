#import <AppKit/AppKit.h>

// Only the installed host owns updates; disposable mirror bundles are excluded.
void SCUpdaterInstallMenu(NSMenu *menu);
// Strict release versions: vMAJOR.MINOR.PATCH (optional leading v).
NSString *SCUpdateVersion(id value);
NSDictionary *SCUpdateAsset(NSDictionary *release, NSString *architecture);
BOOL SCUpdateVerifyArchive(NSURL *archive, NSString *digest);
BOOL SCUpdaterBusy(void);
void SCUpdaterCancel(void);
