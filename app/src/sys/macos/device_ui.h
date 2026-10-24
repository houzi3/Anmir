#import <AppKit/AppKit.h>

NSColor *SCDeviceBackground(void);
NSColor *SCDeviceBlue(void);
NSTextField *SCDeviceLabel(NSString *text, CGFloat size, NSFontWeight weight, BOOL secondary);
NSImage *SCDeviceSymbol(NSString *name);
NSImage *SCDeviceWiFiSymbol(void);
NSStackView *SCDeviceStack(NSArray<NSView *> *views, BOOL vertical, CGFloat spacing);

@interface SCDeviceSurface : NSView
@end

// Compact, predictable toolbar and row controls across macOS versions.
@interface SCDeviceButton : NSButton
@property(nonatomic) BOOL primary;
@end

@interface SCDeviceIconButton : NSButton
@end

// A custom-drawn choice card uses its entire visible surface as the hit area,
// while retaining native radio-button tracking and accessibility semantics.
@interface SCDeviceCardCell : NSButtonCell
@end

@interface SCDeviceStepBadge : NSView
- (instancetype)initWithNumber:(NSUInteger)number;
@end

// A native field editor inside a padded, appearance-aware outline. The editor
// and placeholder share the same geometry, including during focus and typing.
@interface SCDeviceInput : NSView
@property(nonatomic, strong, readonly) NSTextField *textField;
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic) BOOL enabled;
- (instancetype)initWithPlaceholder:(NSString *)placeholder identifier:(NSString *)identifier;
- (void)usePairingCodeStyle;
@end

NSImage *SCDeviceMirrorIcon(NSImage *base);
