#import <AppKit/AppKit.h>
#import "sys/macos/updater.h"
#import "sys/macos/mirror_session.h"
#include <assert.h>

// The updater's pure policy is exercised without network, UI, or an installed app.
NSString *SCLocalized(NSString *key) { return key; }
void SCBind(id target, NSString *property, NSString *key) { (void)target; (void)property; (void)key; }
NSString *SCMirrorHostBundleIdentifier(void) { return @"io.github.laobie.anmir"; }
NSBundle *SCMirrorHostBundle(void) { return NSBundle.mainBundle; }
NSArray<SCMirrorSession *> *SCMirrorRunningSessions(void) { return @[]; }

int main(void) { @autoreleasepool {
    assert([SCUpdateVersion(@"v1.2.10") isEqual:@"1.2.10"]);
    assert([SCUpdateVersion(@"0.1.0") isEqual:@"0.1.0"]);
    for (id invalid in @[@"1.0", @"v1.0.0-beta", @"1.0.0\n", @"v1.0.0+build", @"garbage", @42, NSNull.null]) {
        assert(!SCUpdateVersion(invalid));
    }
    assert([SCUpdateVersion(@"v0.10.0") compare:SCUpdateVersion(@"0.9.0") options:NSNumericSearch] == NSOrderedDescending);
    assert([SCUpdateVersion(@"1.2.9") compare:SCUpdateVersion(@"1.2.10") options:NSNumericSearch] == NSOrderedAscending);
    NSString *checksum = @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    NSMutableDictionary *asset = [@{@"name":@"Anmir-1.2.10-arm64.zip", @"sha256":checksum} mutableCopy];
    NSMutableDictionary *assets = [@{@"arm64":asset} mutableCopy];
    NSMutableDictionary *release = [@{@"schema":@1, @"version":@"1.2.10",
        @"notes":@"Notes", @"assets":assets} mutableCopy];
    NSDictionary *selected = SCUpdateAsset(release, @"arm64");
    assert([selected[@"digest"] isEqual:[@"sha256:" stringByAppendingString:checksum]]);
    assert([selected[@"browser_download_url"] isEqual:
        @"https://github.com/houzi3/Anmir/releases/download/v1.2.10/Anmir-1.2.10-arm64.zip"]);
    assert(!SCUpdateAsset(release, @"x86_64"));
    release[@"schema"] = @2; assert(!SCUpdateAsset(release, @"arm64")); release[@"schema"] = @1;
    release[@"notes"] = @42; assert(!SCUpdateAsset(release, @"arm64")); release[@"notes"] = @"Notes";
    release[@"version"] = @"v1.2.10"; assert(!SCUpdateAsset(release, @"arm64"));
    release[@"version"] = @"1.2.10";
    asset[@"name"] = @"Anmir-1.2.10-x86_64.zip"; assert(!SCUpdateAsset(release, @"arm64"));
    asset[@"name"] = @"Anmir-1.2.10-arm64.zip";
    asset[@"sha256"] = NSNull.null; assert(!SCUpdateAsset(release, @"arm64"));
    asset[@"sha256"] = @"123"; assert(!SCUpdateAsset(release, @"arm64"));
    asset[@"sha256"] = checksum; assert(SCUpdateAsset(release, @"arm64"));
    release[@"assets"] = NSNull.null; assert(!SCUpdateAsset(release, @"arm64"));
    assert(!SCUpdateAsset((id)NSNull.null, @"arm64"));
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    assert([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES]);
    assert(SCUpdateVerifyArchive(file, [@"sha256:" stringByAppendingString:checksum]));
    assert(!SCUpdateVerifyArchive(file, @"sha256:0000000000000000000000000000000000000000000000000000000000000000"));
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    assert(!SCUpdateVerifyArchive(file, [@"sha256:" stringByAppendingString:checksum]));
    NSMenu *menu = [NSMenu new];
    SCUpdaterInstallMenu(menu);
    assert([menu itemWithTag:0x53435550]); // Mirror menus expose the forwarded action too.
    puts("Updater policy and checksum tests passed");
} return 0; }
