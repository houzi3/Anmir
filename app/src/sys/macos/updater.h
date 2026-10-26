#import <AppKit/AppKit.h>

// Every app menu exposes updates; disposable mirror bundles forward the action
// to the installed host, which remains the only process that performs updates.
void SCUpdaterInstallMenu(NSMenu *menu);
void SCUpdaterCheck(void);
// Strict release versions: vMAJOR.MINOR.PATCH (optional leading v).
NSString *SCUpdateVersion(id value);
NSDictionary *SCUpdateAsset(NSDictionary *release, NSString *architecture);
BOOL SCUpdateVerifyArchive(NSURL *archive, NSString *digest);
BOOL SCUpdaterBusy(void);
void SCUpdaterCancel(void);
