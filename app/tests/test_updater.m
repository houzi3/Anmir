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
    NSString *digest = @"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    NSMutableDictionary *asset = [@{@"name":@"Anmir-1.2.10-arm64.zip", @"digest":digest,
        @"browser_download_url":@"https://github.com/houzi3/Anmir/releases/download/v1.2.10/Anmir-1.2.10-arm64.zip"} mutableCopy];
    NSMutableDictionary *release = [@{@"tag_name":@"v1.2.10", @"draft":@NO, @"prerelease":@NO, @"assets":@[asset]} mutableCopy];
    assert(SCUpdateAsset(release, @"arm64"));
    assert(!SCUpdateAsset(release, @"x86_64"));
    release[@"prerelease"] = @YES; assert(!SCUpdateAsset(release, @"arm64")); release[@"prerelease"] = @NO;
    release[@"draft"] = @YES; assert(!SCUpdateAsset(release, @"arm64")); release[@"draft"] = @NO;
    id original = asset[@"browser_download_url"];
    for (NSString *url in @[@"http://github.com/houzi3/Anmir/releases/download/v1.2.10/Anmir-1.2.10-arm64.zip",
        @"https://github.com/attacker/Anmir/releases/download/v1.2.10/Anmir-1.2.10-arm64.zip",
        @"https://github.com/laobie/Anmir/releases/download/v1.2.10/Anmir-1.2.10-arm64.zip",
        @"https://example.com/Anmir-1.2.10-arm64.zip"]) {
        asset[@"browser_download_url"] = url; assert(!SCUpdateAsset(release, @"arm64"));
    }
    asset[@"browser_download_url"] = original; asset[@"digest"] = NSNull.null;
    assert(!SCUpdateAsset(release, @"arm64"));
    asset[@"digest"] = @"sha256:123"; assert(!SCUpdateAsset(release, @"arm64"));
    asset[@"digest"] = digest; assert(SCUpdateAsset(release, @"arm64"));
    release[@"draft"] = NSNull.null; assert(!SCUpdateAsset(release, @"arm64")); release[@"draft"] = @NO;
    release[@"assets"] = NSNull.null; assert(!SCUpdateAsset(release, @"arm64"));
    assert(!SCUpdateAsset((id)NSNull.null, @"arm64"));
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    assert([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES]);
    assert(SCUpdateVerifyArchive(file, digest));
    assert(!SCUpdateVerifyArchive(file, @"sha256:0000000000000000000000000000000000000000000000000000000000000000"));
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    assert(!SCUpdateVerifyArchive(file, digest));
    NSMenu *menu = [NSMenu new];
    SCUpdaterInstallMenu(menu);
    assert([menu itemWithTag:0x53435550]); // Mirror menus expose the forwarded action too.
    puts("Updater policy and checksum tests passed");
} return 0; }
