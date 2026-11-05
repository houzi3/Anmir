#include "config.h"
#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import "sys/macos/device_wifi.h"
#import "sys/macos/device_pairing.h"
#import "sys/macos/device_connection.h"
#import "sys/macos/device_relay.h"
#import "sys/macos/device_ui.h"
#import "sys/macos/localization.h"
#include <assert.h>
#include <string.h>
#include <unistd.h>

@interface SCDeviceWiFiController (Testing)
- (void)discover;
- (void)performRepair;
@end

static NSString *root;
static NSString *file(NSString *name) { return [root stringByAppendingPathComponent:name]; }
static void fixtureWrite(NSString *name, NSString *value) {
    assert([value writeToFile:file(name) atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}
static NSString *fixtureRead(NSString *name) {
    return [NSString stringWithContentsOfFile:file(name) encoding:NSUTF8StringEncoding error:nil] ?: @"";
}
static void waitFor(BOOL (^condition)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition() && end.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
    assert(condition());
}
static void settle(SCDeviceWiFiController *wifi) {
    waitFor(^BOOL { return ![[wifi valueForKey:@"scan"] running]; });
}
static NSView *find(NSView *view, NSString *identifier) {
    if ([view.identifier isEqualToString:identifier]) { return view; }
    for (NSView *child in view.subviews) {
        NSView *match = find(child, identifier); if (match) { return match; }
    }
    return nil;
}
static NSBitmapImageRep *snapshot(NSView *view) {
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:view.bounds.size.width * 2 pixelsHigh:view.bounds.size.height * 2
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = view.bounds.size;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    }];
    return bitmap;
}
static void save(NSView *view, NSString *name) {
    NSString *output = NSProcessInfo.processInfo.environment[@"ANMIR_WIFI_SNAPSHOTS"];
    if (!output.length) { return; }
    assert([NSFileManager.defaultManager createDirectoryAtPath:output
        withIntermediateDirectories:YES attributes:nil error:nil]);
    assert([[snapshot(view) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[output stringByAppendingPathComponent:name] atomically:YES]);
}

// The test is its own ADB process. Only temporary fake services and secrets
// are used; no network, saved preferences or desktop windows are touched.
static int fixture(NSArray<NSString *> *args) {
    if ([args[1] isEqualToString:@"mdns"]) {
        fputs(fixtureRead(@"services").UTF8String, stdout);
    } else if ([args[1] isEqualToString:@"kill-server"] || [args[1] isEqualToString:@"start-server"]) {
        fixtureWrite(@"recovery-commands", [fixtureRead(@"recovery-commands")
            stringByAppendingFormat:@"%@\n", args[1]]);
        NSString *mode = fixtureRead(@"recovery-mode");
        if ([args[1] isEqualToString:@"kill-server"] && [mode hasPrefix:@"slow"]) { usleep(300000); }
        if ([args[1] isEqualToString:@"kill-server"] && [mode isEqualToString:@"slowfail"]) { return 1; }
    } else if ([args[1] isEqualToString:@"pair"]) {
        fixtureWrite(@"pair-arguments", [args componentsJoinedByString:@" "]);
        char input[128]; assert(fgets(input, sizeof(input), stdin));
        assert([[NSString stringWithUTF8String:input] isEqualToString:[fixtureRead(@"secret") stringByAppendingString:@"\n"]]);
        if ([fixtureRead(@"mode") isEqualToString:@"hang"]) { sleep(10); }
        if ([fixtureRead(@"mode") isEqualToString:@"fail"]) { puts("Failed to pair"); return 1; }
        puts("Successfully paired to 192.0.2.1:42187 [guid=adb-qr-fixture]");
    } else if ([args[1] isEqualToString:@"connect"]) {
        assert([args[2] isEqualToString:@"192.0.2.2:39217"]);
        puts("connected to 192.0.2.2:39217");
    } else if ([args[1] isEqualToString:@"-s"]) {
        assert([args[2] isEqualToString:@"192.0.2.2:39217"]);
        if ([args[3] isEqualToString:@"get-state"]) { puts("device"); }
        else { puts("[ro.product.model]: [QR test phone]\n[ro.serialno]: [test-phone]"); }
    } else { return 1; }
    return 0;
}

static void checkLayout(SCDeviceWiFiController *wifi) {
    NSView *content = wifi.window.contentView;
    SCDeviceQRPairing *qr = [wifi valueForKey:@"qrPairing"];
    for (NSString *language in @[@"zh-Hans", @"zh-Hant", @"en"]) {
        for (NSString *theme in @[@"light", @"dark"]) {
            SCUseLanguage(language);
            wifi.window.appearance = [NSAppearance appearanceNamed:[theme isEqualToString:@"light"]
                ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
            [content layoutSubtreeIfNeeded];
            assert(!content.hasAmbiguousLayout);
            NSView *networkMode = find(content, @"WiFi.companyNetwork");
            NSRect entry = [networkMode convertRect:networkMode.bounds toView:content];
            assert(NSMaxX(entry) <= NSWidth(content.bounds) - 20);
            NSTextField *path = (NSTextField *)find(content, @"WiFi.phonePath");
            NSTextField *network = (NSTextField *)find(content, @"WiFi.network");
            assert(path && network);
            NSButton *download = (NSButton *)find(content, @"WiFi.companionInstaller");
            if (download) {
                NSView *caption = find(content, @"WiFi.companionInstall");
                NSView *helper = find(content, @"WiFi.companionGuide");
                NSButton *scan = (NSButton *)find(content, @"WiFi.companionInstallQRButton");
                NSTextField *alternative = (NSTextField *)find(content, @"WiFi.companionInstallAlternative");
                assert(scan);
                assert(alternative);
                assert([download.toolTip isEqualToString:
                    @"https://github.com/houzi3/Anmir/releases/tag/v" SCRCPY_VERSION]);
                assert([scan.toolTip isEqualToString:
                    @"https://github.com/houzi3/Anmir/releases/download/v" SCRCPY_VERSION
                    "/AnmirConnect-" SCRCPY_VERSION ".apk"]);
                assert(find(content, @"WiFi.companySteps"));
                if (![language isEqualToString:@"en"]) {
                    assert(fabs(NSHeight(caption.superview.bounds) - NSHeight(helper.superview.bounds)) <= 1);
                    assert(fabs(NSHeight(caption.superview.bounds) - NSHeight(path.superview.bounds)) <= 1);
                }
                assert([(SCDeviceIconButton *)networkMode glyphSize] == 20);
            }
            assert(path.bounds.size.height + 1 >= [path.attributedStringValue
                boundingRectWithSize:NSMakeSize(path.bounds.size.width, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading].size.height);
            if (!download) {
                assert([path.stringValue containsString:[language isEqualToString:@"en"] ? @"On your phone:"
                    : [language isEqualToString:@"zh-Hans"] ? @"在手机上：" : @"在手機上："]);
            }
            assert(qr == [wifi valueForKey:@"qrPairing"]); // Theme/language cannot rotate a live code.
            NSView *image = find(content, @"WiFi.qrCode");
            NSBitmapImageRep *pixels = snapshot(image);
            CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
                options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];
            NSArray *features = [detector featuresInImage:[CIImage imageWithCGImage:pixels.CGImage]];
            assert(features.count == 1);
            assert([((CIQRCodeFeature *)features.firstObject).messageString isEqualToString:qr.payload]);
            save(content, [NSString stringWithFormat:@"%@-%@.png", language, theme]);
            NSButton *refresh = (NSButton *)find(content, @"WiFi.refreshQR");
            NSRect status = [find(content, @"WiFi.qrStatus") convertRect:find(content, @"WiFi.qrStatus").bounds toView:content];
            assert(NSMinY(status) >= NSMaxY(refresh.frame) + 20);
            assert(NSMinY(status) <= NSMaxY(refresh.frame) + 44);
            if (!download) { save(content, [NSString stringWithFormat:@"standard-%@-%@.png", language, theme]); }
            [refresh highlight:YES]; save(content, [NSString stringWithFormat:@"%@-%@-pressed.png", language, theme]);
            [refresh highlight:NO];
        }
    }
}

static void checkHelpLayout(SCDeviceWiFiController *wifi) {
    NSView *content = wifi.window.contentView;
    for (NSString *language in @[@"zh-Hans", @"zh-Hant", @"en"]) {
        for (NSString *theme in @[@"light", @"dark"]) {
            SCUseLanguage(language);
            wifi.window.appearance = [NSAppearance appearanceNamed:[theme isEqualToString:@"light"]
                ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
            [content layoutSubtreeIfNeeded];
            NSButton *company = (NSButton *)find(content, @"WiFi.companyNetwork");
            NSButton *repair = (NSButton *)find(content, @"WiFi.repair");
            assert(company && repair && company.enabled && repair.enabled);
            assert(!company.title.length && !repair.title.length);
            assert(!content.hasAmbiguousLayout);
            assert(NSHeight(company.bounds) >= 46 && NSHeight(repair.bounds) >= 46);
            NSRect companyRect = [company convertRect:company.bounds toView:content];
            NSRect repairRect = [repair convertRect:repair.bounds toView:content];
            assert(NSMaxX(companyRect) <= NSWidth(content.bounds) - 20);
            assert(NSMinY(companyRect) >= NSMaxY(repairRect));
            assert([[company accessibilityLabel] isEqualToString:SCLocalized(@"Company network connection")]);
            assert([[repair accessibilityLabel] isEqualToString:SCLocalized(@"Fix connection")]);
            save(content, [NSString stringWithFormat:@"help-%@-%@.png", language, theme]);
        }
    }
    SCUseLanguage(@"en");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        root = NSProcessInfo.processInfo.environment[@"ANMIR_WIFI_FIXTURE"];
        if (argc > 2 || (argc == 2 && (!strcmp(argv[1], "kill-server")
                || !strcmp(argv[1], "start-server")))) { return fixture(NSProcessInfo.processInfo.arguments); }
        assert(argc == 2);
        root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]);
        setenv("ANMIR_WIFI_FIXTURE", root.UTF8String, 1);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        SCLocalizationInitialize([NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]], @"en");
        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(-10000, -10000, 600, 550)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        parent.releasedWhenClosed = NO;
        [parent orderFront:nil];
        __block NSUInteger mirrors = 0;
        NSString *executable = [NSString stringWithUTF8String:argv[0]].stringByStandardizingPath;
        BOOL (^mirror)(NSString *, NSDictionary *) = ^BOOL(NSString *serial, NSDictionary *properties) {
            assert([serial isEqualToString:@"192.0.2.2:39217"]);
            assert([properties[@"ro.product.model"] isEqualToString:@"QR test phone"]);
            ++mirrors; return YES;
        };
        SCDeviceWiFiController *wifi = [[SCDeviceWiFiController alloc] initWithExecutable:executable mirror:mirror];
        fixtureWrite(@"services", @"");
        [wifi presentFrom:parent]; settle(wifi);
        checkLayout(wifi);
        SCUseLanguage(@"en");
        // Company mode carries the callback in a standard Android ADB QR code.
        [(NSButton *)find(wifi.window.contentView, @"WiFi.companyNetwork") performClick:nil];
        settle(wifi);
        assert([wifi valueForKey:@"relay"]);
        assert([[wifi valueForKey:@"qrDeadline"] timeIntervalSinceNow] > 240);
        assert([[[wifi valueForKey:@"qrPairing"] serviceName] hasPrefix:@"studio-anmir1-"]);
        checkLayout(wifi); // The longer QR must decode in every supported theme/language.
        SCUseLanguage(@"en");
        NSButton *installerQRButton = (NSButton *)find(wifi.window.contentView, @"WiFi.companionInstallQRButton");
        [installerQRButton performClick:nil];
        NSPopover *installerPopover = [wifi valueForKey:@"companionDownloadPopover"];
        assert(installerPopover.shown);
        NSView *installerQR = find(installerPopover.contentViewController.view, @"WiFi.companionInstallQR");
        NSBitmapImageRep *installerPixels = snapshot(installerQR);
        CIDetector *installerDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
            options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];
        NSArray *installerFeatures = [installerDetector featuresInImage:
            [CIImage imageWithCGImage:installerPixels.CGImage]];
        assert(installerFeatures.count == 1);
        assert([((CIQRCodeFeature *)installerFeatures.firstObject).messageString isEqualToString:
            @"https://github.com/houzi3/Anmir/releases/download/v" SCRCPY_VERSION
            "/AnmirConnect-" SCRCPY_VERSION ".apk"]);
        assert(find(installerPopover.contentViewController.view, @"WiFi.companionInstallQRHint"));
        save(installerPopover.contentViewController.view, @"companion-installer.png");
        [installerPopover close];
        [(NSButton *)find(wifi.window.contentView, @"WiFi.companyNetwork") performClick:nil];
        settle(wifi);
        assert(![wifi valueForKey:@"relay"]);
        // An idle phone has not advertised a pairing service yet. Repeated
        // successful discovery must retain the scanner guidance, not warn.
        for (NSUInteger i = 0; i < 12; ++i) { [wifi discover]; settle(wifi); }
        assert([[[wifi valueForKey:@"message"] stringValue] containsString:@"system pairing scanner"]);
        assert(!find(wifi.window.contentView, @"WiFi.repair"));
        assert(!fixtureRead(@"recovery-commands").length);

        // The delay is only a neutral help entry. Canceling the native sheet
        // must not restart the shared ADB server.
        [wifi setValue:NSDate.distantPast forKey:@"helpDeadline"];
        [wifi discover]; settle(wifi);
        assert([[wifi valueForKey:@"helpShown"] boolValue]);
        checkHelpLayout(wifi);
        NSButton *repair = (NSButton *)find(wifi.window.contentView, @"WiFi.repair");
        [repair performClick:nil];
        NSAlert *alert = [wifi valueForKey:@"repairAlert"];
        assert(alert && !fixtureRead(@"recovery-commands").length);
        [wifi.window endSheet:alert.window returnCode:NSAlertSecondButtonReturn];
        waitFor(^BOOL { return ![wifi valueForKey:@"repairAlert"]; });
        assert(!fixtureRead(@"recovery-commands").length);

        // Switching QR mode invalidates a confirmation; even a stale first
        // button result must never restart the shared ADB server.
        [(NSButton *)find(wifi.window.contentView, @"WiFi.repair") performClick:nil];
        alert = [wifi valueForKey:@"repairAlert"];
        assert(alert);
        [(NSButton *)find(wifi.window.contentView, @"WiFi.companyNetwork") performClick:nil];
        assert(![wifi valueForKey:@"repairAlert"]);
        assert([[wifi valueForKey:@"companionMode"] boolValue]);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        assert(!fixtureRead(@"recovery-commands").length);
        [(NSButton *)find(wifi.window.contentView, @"WiFi.companyNetwork") performClick:nil];
        settle(wifi);
        [wifi setValue:NSDate.distantPast forKey:@"helpDeadline"];
        [wifi discover]; settle(wifi);

        // Refresh also invalidates a pending confirmation and the old QR.
        SCDeviceQRPairing *beforeRefresh = [wifi valueForKey:@"qrPairing"];
        [(NSButton *)find(wifi.window.contentView, @"WiFi.repair") performClick:nil];
        assert([wifi valueForKey:@"repairAlert"]);
        [[wifi valueForKey:@"qrRefreshButton"] performClick:nil];
        assert(![wifi valueForKey:@"repairAlert"]);
        assert(![beforeRefresh.payload isEqualToString:[[wifi valueForKey:@"qrPairing"] payload]]);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        assert(!fixtureRead(@"recovery-commands").length);
        settle(wifi);
        [wifi setValue:NSDate.distantPast forKey:@"helpDeadline"];
        [wifi discover]; settle(wifi);


        // A confirmed repair runs once and replaces the old QR. Starting the
        // ADB service is not treated as a phone connection.
        fixtureWrite(@"recovery-mode", @"slow");
        SCDeviceQRPairing *beforeRepair = [wifi valueForKey:@"qrPairing"];
        [(NSButton *)find(wifi.window.contentView, @"WiFi.repair") performClick:nil];
        alert = [wifi valueForKey:@"repairAlert"];
        assert(alert);
        [wifi.window endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
        waitFor(^BOOL { return [[wifi valueForKey:@"repairing"] boolValue]; });
        assert(![[wifi valueForKey:@"qrRefreshButton"] isEnabled]);
        [(NSButton *)find(wifi.window.contentView, @"WiFi.repair") performClick:nil];
        waitFor(^BOOL { return ![[wifi valueForKey:@"repairing"] boolValue]; });
        assert([fixtureRead(@"recovery-commands") isEqualToString:@"kill-server\nstart-server\n"]);
        assert(![beforeRepair.payload isEqualToString:[[wifi valueForKey:@"qrPairing"] payload]]);
        assert([[[wifi valueForKey:@"message"] stringValue] isEqualToString:
            SCLocalized(@"Connection service restarted. Scan the new QR code.")]);
        assert(mirrors == 0);
        settle(wifi);

        SCDeviceQRPairing *old = [wifi valueForKey:@"qrPairing"];
        [wifi setValue:NSDate.distantPast forKey:@"qrDeadline"];
        [wifi discover];
        assert([[[wifi valueForKey:@"message"] stringValue] containsString:@"expired"]);
        save(wifi.window.contentView, @"expired.png");
        [[wifi valueForKey:@"qrRefreshButton"] performClick:nil]; settle(wifi);
        SCDeviceQRPairing *qr = [wifi valueForKey:@"qrPairing"];
        assert(![old.payload isEqualToString:qr.payload]);
        fixtureWrite(@"services", [NSString stringWithFormat:@"%@ _adb-tls-pairing._tcp 192.0.2.1:42187\n", old.serviceName]);
        [wifi discover]; settle(wifi);
        assert(!fixtureRead(@"pair-arguments").length);

        fixtureWrite(@"secret", qr.password);
        fixtureWrite(@"services", [NSString stringWithFormat:
            @"other _adb-tls-pairing._tcp 192.0.2.1:40001\n%@ _adb-tls-pairing._tcp 192.0.2.1:42187\nadb-other _adb-tls-connect._tcp 192.0.2.1:37123\nadb-qr-fixture _adb-tls-connect._tcp 192.0.2.2:39217\n", qr.serviceName]);
        [wifi discover]; waitFor(^BOOL { return mirrors == 1; });
        assert(![fixtureRead(@"pair-arguments") containsString:qr.password]);
        assert(!wifi.window.visible);

        for (NSString *mode in @[@"fail", @"hang"]) {
            [NSFileManager.defaultManager removeItemAtPath:file(@"pair-arguments") error:nil];
            fixtureWrite(@"services", @""); fixtureWrite(@"mode", mode);
            wifi = [[SCDeviceWiFiController alloc] initWithExecutable:executable mirror:mirror];
            [wifi presentFrom:parent]; settle(wifi);
            qr = [wifi valueForKey:@"qrPairing"]; fixtureWrite(@"secret", qr.password);
            fixtureWrite(@"services", [NSString stringWithFormat:@"%@ _adb-tls-pairing._tcp 192.0.2.1:42187\n", qr.serviceName]);
            [wifi discover];
            if ([mode isEqualToString:@"fail"]) {
                waitFor(^BOOL { return [[wifi valueForKey:@"qrFailed"] boolValue]; });
                assert([[wifi valueForKey:@"qrRefreshButton"] isEnabled]);
                save(wifi.window.contentView, @"pairing-failed.png");
                [[wifi valueForKey:@"modeButton"] performClick:nil];
                assert([wifi valueForKey:@"code"]);
            } else {
                waitFor(^BOOL { return fixtureRead(@"pair-arguments").length > 0; });
                assert(![[wifi valueForKey:@"qrRefreshButton"] isEnabled]);
            }
            [wifi close];
            assert(![[wifi valueForKey:@"connection"] busy]);
            assert(mirrors == 1);
        }

        // A phone may finish scanning while the restart confirmation is open.
        // Starting pairing dismisses the stale sheet and must not restart ADB.
        __block NSUInteger raceMirrors = 0;
        fixtureWrite(@"services", @""); fixtureWrite(@"mode", @"");
        fixtureWrite(@"recovery-commands", @"");
        SCDeviceWiFiController *race = [[SCDeviceWiFiController alloc] initWithExecutable:executable
            mirror:^BOOL(NSString *serial, NSDictionary *properties) {
                (void)serial; (void)properties; ++raceMirrors; return YES;
            }];
        [race presentFrom:parent]; settle(race);
        [race setValue:NSDate.distantPast forKey:@"helpDeadline"];
        [race discover]; settle(race);
        [(NSButton *)find(race.window.contentView, @"WiFi.repair") performClick:nil];
        assert([race valueForKey:@"repairAlert"]);
        SCDeviceQRPairing *raceQR = [race valueForKey:@"qrPairing"];
        fixtureWrite(@"secret", raceQR.password);
        fixtureWrite(@"services", [NSString stringWithFormat:
            @"%@ _adb-tls-pairing._tcp 192.0.2.1:42187\nadb-qr-fixture _adb-tls-connect._tcp 192.0.2.2:39217\n", raceQR.serviceName]);
        [race discover];
        waitFor(^BOOL { return raceMirrors == 1; });
        assert(![race valueForKey:@"repairAlert"]);
        assert(!fixtureRead(@"recovery-commands").length);

        // A successful restart also reports its result after the window is reopened.
        fixtureWrite(@"services", @""); fixtureWrite(@"recovery-mode", @"slow");
        fixtureWrite(@"recovery-commands", @"");
        wifi = [[SCDeviceWiFiController alloc] initWithExecutable:executable mirror:mirror];
        [wifi presentFrom:parent]; settle(wifi);
        [wifi performRepair];
        assert([[wifi valueForKey:@"repairing"] boolValue]);
        [wifi close];
        [wifi presentFrom:parent];
        waitFor(^BOOL { return ![[wifi valueForKey:@"repairing"] boolValue]; });
        assert(![[wifi valueForKey:@"repairFailed"] boolValue]);
        assert([wifi valueForKey:@"qrPairing"]);
        assert([[[wifi valueForKey:@"message"] stringValue] isEqualToString:
            SCLocalized(@"Connection service restarted. Scan the new QR code.")]);
        assert([fixtureRead(@"recovery-commands") isEqualToString:@"kill-server\nstart-server\n"]);
        [wifi close];

        // Closing and reopening during a failed restart must show the failure
        // on the new window, instead of silently presenting a fresh QR.
        fixtureWrite(@"services", @""); fixtureWrite(@"recovery-mode", @"slowfail");
        fixtureWrite(@"recovery-commands", @"");
        wifi = [[SCDeviceWiFiController alloc] initWithExecutable:executable mirror:mirror];
        [wifi presentFrom:parent]; settle(wifi);
        [wifi performRepair];
        assert([[wifi valueForKey:@"repairing"] boolValue]);
        [wifi close];
        [wifi presentFrom:parent];
        waitFor(^BOOL { return ![[wifi valueForKey:@"repairing"] boolValue]; });
        assert([[wifi valueForKey:@"repairFailed"] boolValue]);
        assert([[[wifi valueForKey:@"message"] stringValue] isEqualToString:
            SCLocalized(@"Could not restart connection service. Try again.")]);
        assert(find(wifi.window.contentView, @"WiFi.repair"));
        assert([fixtureRead(@"recovery-commands") isEqualToString:@"kill-server\nstart-server\n"]);
        [wifi close];

        // Reopening an unavailable company QR must create its relay after the
        // window advances generation; otherwise every phone report is stale.
        fixtureWrite(@"services", @""); fixtureWrite(@"mode", @"hang");
        SCDeviceWiFiController *relayWifi = [[SCDeviceWiFiController alloc] initWithExecutable:executable mirror:mirror];
        [relayWifi setValue:@YES forKey:@"companionMode"];
        [relayWifi setValue:@YES forKey:@"qrFailed"];
        [relayWifi presentQRCodeFrom:parent]; settle(relayWifi);
        SCDeviceQRPairing *relayQR = [relayWifi valueForKey:@"qrPairing"];
        SCDeviceRelay *relay = [relayWifi valueForKey:@"relay"];
        assert(relay && relay.received && relayQR);
        fixtureWrite(@"secret", relayQR.password);
        SCDeviceService *service = [[SCDeviceService alloc] init];
        service.name = relayQR.serviceName;
        service.host = @"192.0.2.1";
        service.endpoint = @"192.0.2.1:42187";
        service.pairing = YES;
        relay.received(@[service]);
        assert([[[relayWifi valueForKey:@"connection"] valueForKey:@"phase"] unsignedIntegerValue]
            == SCDeviceConnectionPairing);
        [relayWifi close];
        [parent close];
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
        puts("QR UI: six language/theme renders decode; refresh, expiry, exact service, automatic mirroring, failure and cancellation passed.");
    }
    return 0;
}
