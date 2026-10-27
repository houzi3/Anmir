#import <AppKit/AppKit.h>
#import "sys/macos/device_ui.h"
#include <assert.h>
#include <math.h>

static NSBitmapImageRep *SCIconBitmap(NSImage *image, NSInteger size) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = NSMakeSize(size, size);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    NSRect bounds = NSMakeRect(0, 0, size, size);
    NSRectFillUsingOperation(bounds, NSCompositingOperationClear);
    [image drawInRect:bounds];
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

static void SCCheckMirrorIcon(NSString *dataPath) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *bundleURL = [root URLByAppendingPathComponent:@"Icon test.app"];
    NSURL *contents = [bundleURL URLByAppendingPathComponent:@"Contents"];
    NSURL *resources = [contents URLByAppendingPathComponent:@"Resources"];
    assert([files createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil]);
    for (NSString *name in @[@"anmir-dock.icns", @"anmir-mirror.icns"]) {
        assert([files copyItemAtPath:[dataPath stringByAppendingPathComponent:name]
            toPath:[resources URLByAppendingPathComponent:name].path error:nil]);
    }
    NSDictionary *info = @{@"CFBundlePackageType":@"APPL",
        @"CFBundleIdentifier":[@"org.scrcpy.icontest." stringByAppendingString:NSUUID.UUID.UUIDString],
        @"CFBundleIconFile":@"anmir-dock.icns"};
    assert([info writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);
    NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
    NSImage *normal = [[NSImage alloc] initWithContentsOfFile:
        [dataPath stringByAppendingPathComponent:@"anmir-dock.icns"]];
    NSImage *raw = [[NSImage alloc] initWithContentsOfFile:
        [dataPath stringByAppendingPathComponent:@"anmir.icns"]];
    assert(bundle && normal && raw);
    NSImage *bundleIcon = [[NSImage alloc] initWithContentsOfFile:
        [dataPath stringByAppendingPathComponent:@"anmir-mirror-bundle.icns"]];
    assert(bundleIcon);
    NSBitmapImageRep *launch = SCIconBitmap(bundleIcon, 256);
    // The system-masked launch asset needs its own baked phone, not just the
    // runtime Dock override. Its safe inset keeps the phone inside the mask.
    NSUInteger launchInk = 0;
    for (NSInteger y = 194; y < 227; ++y) {
        for (NSInteger x = 195; x < 219; ++x) {
            NSColor *color = [[launch colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (color.redComponent < .5 && color.greenComponent < .5 && color.blueComponent < .5) { ++launchInk; }
        }
    }
    assert(launchInk > 30);
    NSImage *saved = NSApp.applicationIconImage;
    NSView *savedView = NSApp.dockTile.contentView;
    NSApp.applicationIconImage = raw;
    NSImage *fromRaw = SCDeviceMirrorIcon(bundle);
    NSApp.applicationIconImage = normal;
    NSImage *fromNormal = SCDeviceMirrorIcon(bundle);
    assert(fromRaw && fromNormal);
    for (NSNumber *value in @[@16, @32, @44, @64, @128, @256, @512, @1024]) {
        NSInteger size = value.integerValue;
        NSBitmapImageRep *reference = SCIconBitmap(normal, size);
        NSBitmapImageRep *first = SCIconBitmap(fromRaw, size);
        NSBitmapImageRep *second = SCIconBitmap(fromNormal, size);
        assert([[first representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            isEqualToData:[second representationUsingType:NSBitmapImageFileTypePNG properties:@{}]]);
        // Check absolute invariants, not a system-generated icon that could
        // itself be square, missing artwork or awaiting Icon Services metadata.
        for (NSBitmapImageRep *bitmap in @[reference, first]) {
            assert([bitmap colorAtX:0 y:0].alphaComponent < .05);
            assert([bitmap colorAtX:size - 1 y:0].alphaComponent < .05);
            assert([bitmap colorAtX:0 y:size - 1].alphaComponent < .05);
            assert([bitmap colorAtX:size - 1 y:size - 1].alphaComponent < .05);
            assert([bitmap colorAtX:size / 2 y:size / 2].alphaComponent > .99);
        }
        // The badge must not change the main tile's scale/silhouette.
        for (NSInteger x = 0; x < size; ++x) {
            CGFloat expected = [reference colorAtX:x y:size / 2].alphaComponent;
            CGFloat actual = [first colorAtX:x y:size / 2].alphaComponent;
            assert(fabs(expected - actual) <= 2.0 / 255);
        }
        // Bottom-right badge contains a dark phone outline, even at 16px.
        NSUInteger darkPixels = 0;
        // At 16/32px the 3pt outline is narrower than one raster pixel.
        // Its antialiasing still needs visible contrast against the white badge.
        CGFloat inkLimit = size <= 32 ? .90 : .65;
        for (NSInteger y = size * .76; y < size * .94; ++y) {
            for (NSInteger x = size * .77; x < size * .90; ++x) {
                NSColor *color = [[first colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                if (color.alphaComponent > .8 && color.redComponent < inkLimit
                    && color.greenComponent < inkLimit && color.blueComponent < inkLimit) { ++darkPixels; }
            }
        }
        assert(darkPixels > 0);
        // Badge surface extends below the main tile and survives serialization.
        assert([first colorAtX:size * .83 y:size * .95].alphaComponent > (size == 16 ? .25 : .9));
        assert([reference colorAtX:size * .83 y:size * .95].alphaComponent < .1);
    }
    SCDeviceInstallMirrorIcon(bundle);
    assert([NSApp.dockTile.contentView isKindOfClass:NSImageView.class]);
    NSImageView *tile = (NSImageView *)NSApp.dockTile.contentView;
    assert(tile.image && tile.image.representations.count > 1);
    // The runtime image is still the badged asset, regardless of the process's
    // initial app image. Applying again must also restore a replaced Dock view.
    NSApp.dockTile.contentView = nil;
    SCDeviceInstallMirrorIcon(bundle);
    assert([NSApp.dockTile.contentView isKindOfClass:NSImageView.class]);
    NSApp.applicationIconImage = saved;
    NSApp.dockTile.contentView = savedView;
    assert([files removeItemAtURL:root error:nil]);
}

int main(int argc, const char *argv[]) {
    assert(argc == 2);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        SCCheckMirrorIcon([NSString stringWithUTF8String:argv[1]]);
        puts("macOS Dock icons: transparent corners, stable scale, phone badges and repeated installation passed.");
    }
    return 0;
}
