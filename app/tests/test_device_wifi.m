#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import "sys/macos/device_wifi.h"
#import "sys/macos/device_pairing.h"
#import "sys/macos/device_connection.h"
#import "sys/macos/device_ui.h"
#import "sys/macos/localization.h"
#include <assert.h>
#include <unistd.h>

@interface SCDeviceWiFiController (Testing)
- (void)discover;
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
    NSString *output = NSProcessInfo.processInfo.environment[@"SCRCPYX_WIFI_SNAPSHOTS"];
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
            NSTextField *path = (NSTextField *)find(content, @"WiFi.phonePath");
            NSTextField *network = (NSTextField *)find(content, @"WiFi.network");
            assert(path && network && network.fittingSize.width <= network.bounds.size.width + 1);
            assert(path.bounds.size.height + 1 >= [path.attributedStringValue
                boundingRectWithSize:NSMakeSize(path.bounds.size.width, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading].size.height);
            assert([path.stringValue containsString:[language isEqualToString:@"en"] ? @"On your phone:"
                : [language isEqualToString:@"zh-Hans"] ? @"在手机上：" : @"在手機上："]);
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
            [refresh highlight:YES]; save(content, [NSString stringWithFormat:@"%@-%@-pressed.png", language, theme]);
            [refresh highlight:NO];
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        root = NSProcessInfo.processInfo.environment[@"SCRCPYX_WIFI_FIXTURE"];
        if (argc > 2) { return fixture(NSProcessInfo.processInfo.arguments); }
        assert(argc == 2);
        root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]);
        setenv("SCRCPYX_WIFI_FIXTURE", root.UTF8String, 1);
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
        // An idle phone has not advertised a pairing service yet. Repeated
        // successful discovery must retain the scanner guidance, not warn.
        for (NSUInteger i = 0; i < 12; ++i) { [wifi discover]; settle(wifi); }
        assert([[[wifi valueForKey:@"message"] stringValue] containsString:@"system pairing scanner"]);

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
        [parent close];
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
        puts("QR UI: six language/theme renders decode; refresh, expiry, exact service, automatic mirroring, failure and cancellation passed.");
    }
    return 0;
}
