#import "updater.h"
#import "localization.h"
#import "mirror_session.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/sysctl.h>

NSString *SCUpdateVersion(id value) {
    if (![value isKindOfClass:NSString.class]) { return nil; }
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^v?([0-9]+\\.[0-9]+\\.[0-9]+)\\z" options:0 error:nil];
    NSTextCheckingResult *match = [pattern firstMatchInString:value options:0 range:NSMakeRange(0, [value length])];
    return match ? [value substringWithRange:[match rangeAtIndex:1]] : nil;
}

static BOOL SCStableRelease(id release) {
    return [release isKindOfClass:NSDictionary.class]
        && [release[@"draft"] isKindOfClass:NSNumber.class]
        && [release[@"prerelease"] isKindOfClass:NSNumber.class]
        && ![release[@"draft"] boolValue] && ![release[@"prerelease"] boolValue];
}

NSDictionary *SCUpdateAsset(NSDictionary *release, NSString *architecture) {
    if (!SCStableRelease(release)) { return nil; }
    NSString *version = SCUpdateVersion(release[@"tag_name"]);
    if (!version || ![release[@"assets"] isKindOfClass:NSArray.class]) { return nil; }
    NSString *name = [NSString stringWithFormat:@"Anmir-%@-%@.zip", version, architecture];
    for (id asset in release[@"assets"]) {
        if (![asset isKindOfClass:NSDictionary.class] || ![asset[@"name"] isEqual:name]) { continue; }
        id digest = asset[@"digest"], address = asset[@"browser_download_url"];
        if (![digest isKindOfClass:NSString.class] || ![address isKindOfClass:NSString.class]) { continue; }
        NSRegularExpression *hash = [NSRegularExpression regularExpressionWithPattern:@"^sha256:[0-9a-f]{64}\\z" options:0 error:nil];
        NSURL *url = [NSURL URLWithString:address];
        NSString *expectedPath = [NSString stringWithFormat:@"/houzi3/Anmir/releases/download/%@/%@", release[@"tag_name"], name];
        if ([hash numberOfMatchesInString:digest options:0 range:NSMakeRange(0, [digest length])] == 1
            && [url.scheme isEqual:@"https"] && [url.host isEqual:@"github.com"]
            && [url.path isEqual:expectedPath] && !url.user && !url.password && !url.query && !url.fragment) { return asset; }
    }
    return nil;
}

static NSError *SCUpdateError(NSString *message) {
    return [NSError errorWithDomain:@"AnmirUpdater" code:1 userInfo:@{NSLocalizedDescriptionKey:SCLocalized(message)}];
}
static BOOL SCRun(NSString *path, NSArray *arguments, NSError **error) {
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:path]; task.arguments = arguments;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:error]) { return NO; }
    [task waitUntilExit];
    if (task.terminationStatus) { if (error) { *error = SCUpdateError(@"The update could not be prepared."); } return NO; }
    return YES;
}
BOOL SCUpdateVerifyArchive(NSURL *archive, NSString *digest) {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:archive];
    [stream open]; CC_SHA256_CTX context; CC_SHA256_Init(&context);
    uint8_t buffer[65536]; NSInteger count;
    while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) { CC_SHA256_Update(&context, buffer, (CC_LONG)count); }
    [stream close]; if (count < 0) { return NO; }
    uint8_t bytes[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(bytes, &context);
    NSMutableString *actual = [NSMutableString stringWithString:@"sha256:"];
    for (NSUInteger i = 0; i < sizeof(bytes); ++i) { [actual appendFormat:@"%02x", bytes[i]]; }
    return [actual isEqual:digest];
}

static NSString *const SCSkippedUpdateVersionKey = @"AnmirSkippedUpdateVersion";
static NSString *const SCLastUpdateCheckKey = @"AnmirLastUpdateCheck";

@interface SCUpdateAlert : NSAlert
@property(strong) NSButton *skipButton;
@property(strong) NSScrollView *notesScroll;
@property(strong) NSTextField *notesHeading;
@property BOOL positionedAtStart;
@end

static NSTextField *SCUpdateFindText(NSView *view, NSString *text) {
    if ([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqual:text]) {
        return (NSTextField *)view;
    }
    for (NSView *child in view.subviews) {
        NSTextField *result = SCUpdateFindText(child, text);
        if (result) { return result; }
    }
    return nil;
}

@implementation SCUpdateAlert
- (void)skipVersion:(id)sender {
    (void)sender;
    [NSApp stopModalWithCode:NSAlertThirdButtonReturn];
    [self.window orderOut:nil];
}
- (void)positionNotesAtStart {
    NSTextView *text = (NSTextView *)self.notesScroll.documentView;
    self.window.initialFirstResponder = self.buttons.firstObject;
    [self.window makeFirstResponder:self.buttons.firstObject];
    text.selectedRange = NSMakeRange(0, 0);
    [text.layoutManager ensureLayoutForTextContainer:text.textContainer];
    [self.notesScroll.contentView scrollToPoint:NSZeroPoint];
    [self.notesScroll reflectScrolledClipView:self.notesScroll.contentView];
}
- (NSModalResponse)runModal {
    // Reset after AppKit orders the window and chooses its first responder.
    NSTimer *position = [NSTimer timerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [self positionNotesAtStart];
    }];
    [NSRunLoop.mainRunLoop addTimer:position forMode:NSModalPanelRunLoopMode];
    NSModalResponse response = [super runModal];
    [position invalidate];
    return response;
}
- (void)layout {
    [super layout];
    // NSAlert gives native text a different inset from its accessory view.
    // Align the heading's text, including its cell inset, with the native copy.
    NSTextField *description = SCUpdateFindText(self.window.contentView, self.informativeText);
    if (description) {
        NSRect reference = [description convertRect:[description.cell titleRectForBounds:description.bounds]
            toView:self.accessoryView];
        NSRect frame = self.notesHeading.frame;
        NSRect text = [self.notesHeading.cell titleRectForBounds:self.notesHeading.bounds];
        frame.origin.x = NSMinX(reference) - NSMinX(text);
        frame.size.width = self.accessoryView.bounds.size.width - frame.origin.x;
        self.notesHeading.frame = frame;
    }
    // Retain the native two-button row, including its system appearance and
    // keyboard actions. Newer macOS versions center it; align it to the notes.
    NSView *row = self.buttons.firstObject.superview;
    if ([row isKindOfClass:NSStackView.class]) {
        NSStackView *stack = (NSStackView *)row;
        stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        for (NSView *view in stack.views.copy) { [stack removeView:view]; }
        [stack setViews:@[self.buttons[1], self.buttons[0]] inGravity:NSStackViewGravityLeading];
        [row.superview layoutSubtreeIfNeeded];
        NSRect notes = [self.notesScroll convertRect:self.notesScroll.bounds toView:row.superview];
        for (NSLayoutConstraint *constraint in row.superview.constraints) {
            if (constraint.firstItem == row && constraint.firstAttribute == NSLayoutAttributeCenterX
                && constraint.secondItem == row.superview && constraint.secondAttribute == NSLayoutAttributeCenterX) {
                constraint.constant += NSMaxX(notes) - NSMaxX(row.frame);
                break;
            }
        }
        [row.superview layoutSubtreeIfNeeded];
    }
    // Skip is separate from the native actions, so it stays at the far left.
    NSRect notes = [self.notesScroll convertRect:self.notesScroll.bounds toView:row.superview];
    [self.skipButton sizeToFit];
    CGFloat width = MAX(110, self.skipButton.frame.size.width);
    self.skipButton.frame = NSMakeRect(NSMinX(notes), NSMinY(row.frame), width, self.buttons[0].frame.size.height);
    [row.superview addSubview:self.skipButton];
    if (!self.positionedAtStart) {
        [self positionNotesAtStart];
        self.positionedAtStart = YES;
    }
}
@end

static NSAlert *SCUpdateReleaseAlert(NSString *current, NSString *latest, NSString *notes) {
    SCUpdateAlert *alert = [SCUpdateAlert new];
    alert.messageText = SCLocalized(@"A new version of Anmir is available");
    alert.informativeText = [NSString stringWithFormat:SCLocalized(@"Anmir %@ is available. You’re currently using %@. Would you like to download and install it now?"), latest, current];

    NSFont *font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    NSLayoutManager *layout = [NSLayoutManager new];
    CGFloat height = ceil([layout defaultLineHeightForFont:font] * 15) + 14;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 500, height)];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;

    NSTextView *text = [[NSTextView alloc] initWithFrame:(NSRect){NSZeroPoint, scroll.contentSize}];
    text.editable = NO;
    text.selectable = YES;
    text.richText = NO;
    text.font = font;
    text.textColor = NSColor.textColor;
    text.backgroundColor = NSColor.textBackgroundColor;
    text.textContainerInset = NSMakeSize(8, 6);
    text.verticallyResizable = YES;
    text.horizontallyResizable = NO;
    text.autoresizingMask = NSViewWidthSizable;
    text.minSize = NSMakeSize(0, scroll.contentSize.height);
    text.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    text.textContainer.containerSize = NSMakeSize(scroll.contentSize.width, CGFLOAT_MAX);
    text.textContainer.widthTracksTextView = YES;
    text.string = notes;
    scroll.documentView = text;
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, height + 28)];
    NSTextField *label = [NSTextField labelWithString:SCLocalized(@"Release Notes:")];
    label.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    label.frame = NSMakeRect(0, height + 8, 500, 20);
    alert.notesHeading = label;
    [content addSubview:label];
    [content addSubview:scroll];
    alert.notesScroll = scroll;
    alert.accessoryView = content;
    [alert addButtonWithTitle:SCLocalized(@"Install Update")];
    [alert addButtonWithTitle:SCLocalized(@"Install Later")];
    for (NSButton *button in alert.buttons) {
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
    }
    alert.skipButton = [NSButton buttonWithTitle:SCLocalized(@"Skip This Version") target:alert action:@selector(skipVersion:)];
    alert.skipButton.bezelStyle = NSBezelStyleRounded;
    return alert;
}

@interface SCUpdater : NSObject <NSURLSessionDownloadDelegate, NSMenuItemValidation>
- (void)cancel:(id)sender;
- (void)scheduleAutomaticCheck;
@property BOOL automatic;
@property BOOL startupScheduled;
@property(strong) NSTimer *startupTimer;
@property BOOL busy;
@property BOOL cancelled;
@property(strong) NSURLSession *session;
@property(strong) NSURLSessionDownloadTask *download;
@property(strong) NSURLSessionDataTask *requestTask;
@property(strong) NSPanel *panel;
@property(strong) NSProgressIndicator *progress;
@property(copy) NSDictionary *asset;
@property(copy) NSString *version;
@property(strong) NSURL *work;
@property(strong) NSURL *stage;
@end

static SCUpdater *updater;
BOOL SCUpdaterBusy(void) { return updater.busy; }
void SCUpdaterCancel(void) { [updater cancel:nil]; }

@implementation SCUpdater
- (NSDate *)now { return NSDate.date; }
- (NSCalendar *)calendar { return NSCalendar.currentCalendar; }
- (NSUserDefaults *)preferences { return NSUserDefaults.standardUserDefaults; }
- (NSString *)currentVersion { return SCUpdateVersion([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]); }
- (NSURLSessionConfiguration *)sessionConfiguration { return NSURLSessionConfiguration.ephemeralSessionConfiguration; }
- (NSTimeInterval)startupDelay {
    NSDate *launched = NSRunningApplication.currentApplication.launchDate;
    return launched ? MAX(0, 7 - [[self now] timeIntervalSinceDate:launched]) : 7;
}
- (void)scheduleAutomaticCheck {
    if (self.startupScheduled || getenv("ANMIR_SHOW_SETTINGS")) { return; }
    self.startupScheduled = YES;
    self.startupTimer = [NSTimer scheduledTimerWithTimeInterval:[self startupDelay] repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        self.startupTimer = nil;
        [self checkAutomatically:YES];
    }];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { (void)item; return !self.busy || self.automatic; }
- (void)message:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [NSAlert new]; alert.messageText = SCLocalized(title); alert.informativeText = detail ?: @"";
    [alert addButtonWithTitle:SCLocalized(@"OK")]; [alert runModal];
}
- (void)finish:(NSError *)error {
    [self.panel close]; self.panel = nil;
    [self.session invalidateAndCancel]; self.session = nil; self.download = nil; self.requestTask = nil;
    if (self.work) { [NSFileManager.defaultManager removeItemAtURL:self.work error:nil]; self.work = nil; }
    if (self.stage) { [NSFileManager.defaultManager removeItemAtURL:self.stage error:nil]; self.stage = nil; }
    BOOL report = error && !self.cancelled && !self.automatic;
    self.busy = NO; self.automatic = NO;
    if (report) { [self message:@"Update failed" detail:error.localizedDescription]; }
}
- (void)cancel:(id)sender {
    (void)sender;
    [self.startupTimer invalidate]; self.startupTimer = nil;
    self.cancelled = YES; [self.requestTask cancel]; [self.download cancel];
}
- (void)showProgress:(NSString *)title {
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 120) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.panel.releasedWhenClosed = NO;
    self.panel.title = SCLocalized(title);
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 65, 340, 20)];
    self.progress.indeterminate = YES; [self.progress startAnimation:nil]; [self.panel.contentView addSubview:self.progress];
    NSButton *cancel = [NSButton buttonWithTitle:SCLocalized(@"Cancel") target:self action:@selector(cancel:)]; cancel.frame = NSMakeRect(260, 15, 100, 32);
    [self.panel.contentView addSubview:cancel]; [self.panel center]; [self.panel makeKeyAndOrderFront:nil];
}
- (void)check:(id)sender {
    (void)sender;
    [self.startupTimer invalidate]; self.startupTimer = nil;
    if (self.busy && self.automatic) {
        // A manual request adopts the in-flight background check.
        self.automatic = NO;
        [self showProgress:@"Checking for updates…"];
        return;
    }
    [self checkAutomatically:NO];
}
- (void)checkAutomatically:(BOOL)automatic {
    if (self.busy) { return; }
    NSDate *now = [self now];
    id last = [[self preferences] objectForKey:SCLastUpdateCheckKey];
    if (automatic && [last isKindOfClass:NSDate.class] && [[self calendar] isDate:last inSameDayAsDate:now]) { return; }
    // Count attempts, including failed requests, so relaunching cannot cause
    // repeated background traffic or prompts. Manual checks remain unlimited.
    [[self preferences] setObject:now forKey:SCLastUpdateCheckKey];
    self.automatic = automatic; self.busy = YES; self.cancelled = NO;
    NSURLSessionConfiguration *configuration = [self sessionConfiguration];
    configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 600;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.github.com/repos/houzi3/Anmir/releases/latest"]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"Anmir-Updater" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    if (!automatic) { [self showProgress:@"Checking for updates…"]; }
    self.requestTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.panel close]; self.panel = nil; self.requestTask = nil;
            if (self.cancelled) { [self finish:nil]; return; }
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (error || status != 200) { [self finish:error ?: SCUpdateError(@"Could not contact GitHub. Please try again later.")]; return; }
            id release = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *latest = [release isKindOfClass:NSDictionary.class] ? SCUpdateVersion(release[@"tag_name"]) : nil;
            NSString *current = [self currentVersion];
            if (!latest || !current || !SCStableRelease(release)) {
                [self finish:SCUpdateError(@"The release information is invalid.")]; return;
            }
            if ([latest compare:current options:NSNumericSearch] != NSOrderedDescending) {
                BOOL quietly = self.automatic;
                [self finish:nil];
                if (!quietly) { [self message:@"You’re up to date" detail:[NSString stringWithFormat:@"Anmir %@", current]]; }
                return;
            }
            // Detect the physical CPU, including an Intel binary running under Rosetta.
            int arm = 0; size_t length = sizeof(arm); sysctlbyname("hw.optional.arm64", &arm, &length, NULL, 0);
            self.asset = SCUpdateAsset(release, arm ? @"arm64" : @"x86_64"); self.version = latest;
            if (!self.asset) { [self finish:SCUpdateError(@"No verified update package is available for this Mac.")]; return; }
            BOOL skipped = [[[self preferences] stringForKey:SCSkippedUpdateVersionKey] isEqual:latest];
            // Re-read mirror state after the network response: a phone may have
            // started mirroring while the request was in flight.
            if (self.automatic && (skipped || SCMirrorRunningSessions().count)) { [self finish:nil]; return; }
            self.automatic = NO; // Once offered, download/install failures are visible.
            [self showRelease:release current:current latest:latest];
        });
    }];
    [self.requestTask resume];
}
- (void)showRelease:(NSDictionary *)release current:(NSString *)current latest:(NSString *)latest {
    NSString *notes = [release[@"body"] isKindOfClass:NSString.class] ? release[@"body"] : @"";
    if ([[[self preferences] stringForKey:SCSkippedUpdateVersionKey] isEqual:latest]) {
        NSAlert *skipped = [NSAlert new];
        skipped.messageText = SCLocalized(@"You skipped this version");
        skipped.informativeText = [NSString stringWithFormat:SCLocalized(@"You skipped Anmir %@. You can still view and install it manually."), latest];
        [skipped addButtonWithTitle:SCLocalized(@"View Update")];
        [skipped addButtonWithTitle:SCLocalized(@"Install Later")];
        if ([skipped runModal] != NSAlertFirstButtonReturn) { [self finish:nil]; return; }
    }
    NSAlert *alert = SCUpdateReleaseAlert(current, latest, notes);
    NSModalResponse choice = [alert runModal];
    if (choice == NSAlertThirdButtonReturn) { [[self preferences] setObject:latest forKey:SCSkippedUpdateVersionKey]; }
    if (choice != NSAlertFirstButtonReturn) { [self finish:nil]; return; }
    [[self preferences] removeObjectForKey:SCSkippedUpdateVersionKey];
    [self startDownload];
}
- (void)startDownload {
    if (SCMirrorRunningSessions().count) {
        [self finish:SCUpdateError(@"Close all mirroring windows before installing an update.")]; return;
    }
    NSURL *host = NSBundle.mainBundle.bundleURL;
    if (![host.pathExtension isEqual:@"app"] || [host.path hasPrefix:@"/Volumes/"]
        || ![NSFileManager.defaultManager isWritableFileAtPath:host.URLByDeletingLastPathComponent.path]) {
        [self finish:SCUpdateError(@"Move Anmir to a writable Applications folder before updating.")]; return;
    }
    NSError *error = nil;
    self.work = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"anmir-update-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:self.work withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]) { [self finish:error]; return; }
    [self showProgress:@"Downloading update…"];
    self.download = [self.session downloadTaskWithURL:[NSURL URLWithString:self.asset[@"browser_download_url"]]];
    [self.download resume];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytes totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    (void)session; (void)task; (void)bytes;
    if (expected > 0) { self.progress.indeterminate = NO; self.progress.maxValue = expected; self.progress.doubleValue = written; }
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    (void)session;
    if (self.cancelled) { [self finish:nil]; return; }
    if ([(NSHTTPURLResponse *)task.response statusCode] != 200) { [self finish:SCUpdateError(@"The update download failed.")]; return; }
    NSError *error = nil; NSURL *archive = [self.work URLByAppendingPathComponent:@"update.zip"];
    if (![NSFileManager.defaultManager moveItemAtURL:location toURL:archive error:&error]) { [self finish:error]; return; }
    self.panel.title = SCLocalized(@"Preparing update…"); self.progress.indeterminate = YES; [self.progress startAnimation:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *failure = nil;
        if (!SCUpdateVerifyArchive(archive, self.asset[@"digest"])) { failure = SCUpdateError(@"The update checksum does not match."); }
        NSURL *unpacked = [self.work URLByAppendingPathComponent:@"unpacked" isDirectory:YES];
        if (!failure) { SCRun(@"/usr/bin/ditto", @[@"-x", @"-k", archive.path, unpacked.path], &failure); }
        NSURL *app = [unpacked URLByAppendingPathComponent:@"Anmir.app" isDirectory:YES];
        NSBundle *bundle = [NSBundle bundleWithURL:app];
        if (!failure && (![bundle.bundleIdentifier isEqual:NSBundle.mainBundle.bundleIdentifier]
            || ![SCUpdateVersion([bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]) isEqual:self.version]
            || ![bundle.executableURL.lastPathComponent isEqual:@"anmir"])) { failure = SCUpdateError(@"The downloaded application is invalid."); }
        NSString *minimum = [bundle objectForInfoDictionaryKey:@"LSMinimumSystemVersion"];
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        NSString *system = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
        if (!failure && minimum && [minimum compare:system options:NSNumericSearch] == NSOrderedDescending) { failure = SCUpdateError(@"This update requires a newer version of macOS."); }
        if (!failure) { SCRun(@"/usr/bin/codesign", @[@"--verify", @"--deep", @"--strict", app.path], &failure); }
        // Stage next to the installed app, so replacement stays on the same volume.
        if (!failure) {
            self.stage = [NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".anmir-update-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
            [NSFileManager.defaultManager createDirectoryAtURL:self.stage withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&failure];
            if (!failure) { SCRun(@"/usr/bin/ditto", @[app.path, [self.stage URLByAppendingPathComponent:@"Anmir.app"].path], &failure); }
            if (!failure) { SCRun(@"/usr/bin/codesign", @[@"--verify", @"--deep", @"--strict", [self.stage URLByAppendingPathComponent:@"Anmir.app"].path], &failure); }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (failure || self.cancelled) { [self finish:failure]; return; }
            [self install];
        });
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session; (void)task; if (error) { [self finish:error]; }
}
- (void)install {
    if (SCMirrorRunningSessions().count) { [self finish:SCUpdateError(@"Close all mirroring windows before installing an update.")]; return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = SCLocalized(@"Ready to install");
    alert.informativeText = SCLocalized(@"Anmir will quit, install the update, and reopen. The previous version will be kept next to the application.");
    [alert addButtonWithTitle:SCLocalized(@"Install and Restart")]; [alert addButtonWithTitle:SCLocalized(@"Cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) { [self finish:nil]; return; }
    if (SCMirrorRunningSessions().count) { [self finish:SCUpdateError(@"Close all mirroring windows before installing an update.")]; return; }
    NSURL *source = [NSBundle.mainBundle URLForResource:@"install-update" withExtension:@"sh"];
    NSURL *script = [self.work URLByAppendingPathComponent:@"install.sh"]; NSError *error = nil;
    if (!source || ![NSFileManager.defaultManager copyItemAtURL:source toURL:script error:&error]) { [self finish:error ?: SCUpdateError(@"The update installer is missing.")]; return; }
    NSTask *helper = [NSTask new]; helper.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    helper.arguments = @[script.path, [NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier],
        self.stage.path, NSBundle.mainBundle.bundlePath, self.work.path];
    helper.standardOutput = NSFileHandle.fileHandleWithNullDevice; helper.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![helper launchAndReturnError:&error]) { [self finish:error]; return; }
    // The helper now owns staging and cleanup. It waits for a normal application exit.
    [self.panel close]; [self.session finishTasksAndInvalidate]; self.busy = NO; [NSApp terminate:nil];
}
@end

void SCUpdaterInstallMenu(NSMenu *menu) {
    if (![SCMirrorHostBundleIdentifier() isEqual:NSBundle.mainBundle.bundleIdentifier]) { return; }
    if (!updater) { updater = [SCUpdater new]; [updater scheduleAutomaticCheck]; }
    if ([menu itemWithTag:0x53435550]) { return; }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(check:) keyEquivalent:@""];
    item.target = updater; item.tag = 0x53435550; SCBind(item, @"title", @"Check for Updates…");
    [menu insertItem:item atIndex:MIN(1, menu.numberOfItems)];
}
