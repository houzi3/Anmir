#import "about_window.h"
#import "localization.h"

@interface SCAboutWindowController ()
@property(nonatomic, strong) NSBundle *bundle;
@property(nonatomic, strong) NSWindowController *licenses;
@property(nonatomic, strong) NSTextView *licenseText;
@end

static NSTextField *SCAboutLabel(NSString *identifier, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.identifier = identifier;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.alignment = NSTextAlignmentCenter;
    label.selectable = YES;
    return label;
}

@implementation SCAboutWindowController
- (instancetype)initWithBundle:(NSBundle *)bundle {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 438)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    self = [super initWithWindow:window];
    if (!self) { return nil; }
    self.bundle = bundle;
    SCBindFormat(window, @"title", @"About %@", @[@"Anmir"]);
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:28],
        [stack.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor],
        [stack.widthAnchor constraintEqualToConstant:464],
    ]];
    NSImageView *icon = [NSImageView new];
    icon.identifier = @"About.icon";
    NSString *iconPath = [bundle pathForResource:@"scrcpy" ofType:@"icns"];
    // Use macOS's normalized bundle icon, including its rounded mask.
    icon.image = [NSWorkspace.sharedWorkspace iconForFile:bundle.bundlePath];
    if (!icon.image) { icon.image = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : NSApp.applicationIconImage; }
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [icon.widthAnchor constraintEqualToConstant:104].active = YES;
    [icon.heightAnchor constraintEqualToConstant:104].active = YES;
    [stack addArrangedSubview:icon];
    NSTextField *name = SCAboutLabel(@"About.name", 24, NSFontWeightBold);
    name.stringValue = @"Anmir"; [stack addArrangedSubview:name];
    [stack setCustomSpacing:4 afterView:name];
    NSTextField *version = SCAboutLabel(@"About.version", 13, NSFontWeightRegular);
    version.textColor = NSColor.secondaryLabelColor;
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: shortVersion;
    if (build.length && ![build isEqual:shortVersion]) {
        SCBindFormat(version, @"stringValue", @"Version %@ (Build %@)", @[shortVersion, build]);
    } else {
        SCBindFormat(version, @"stringValue", @"Version %@", @[shortVersion]);
    }
    [stack addArrangedSubview:version];
    NSTextField *description = SCAboutLabel(@"About.description", 13, NSFontWeightRegular);
    SCBind(description, @"stringValue", @"Mirror and control Android devices from your Mac.");
    [stack addArrangedSubview:description];
    [description.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [description.heightAnchor constraintEqualToConstant:36].active = YES;
    NSStackView *links = [NSStackView new];
    links.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    links.spacing = 16;
    NSArray *keys = @[@"Project Home", @"Report an Issue", @"Open Source Licenses"];
    NSArray *identifiers = @[@"About.project", @"About.feedback", @"About.licenses"];
    SEL selectors[] = {@selector(openProject:), @selector(openFeedback:), @selector(showLicenses:)};
    for (NSUInteger i = 0; i < keys.count; ++i) {
        NSButton *button = [NSButton buttonWithTitle:@"" target:self action:selectors[i]];
        button.identifier = identifiers[i];
        button.bezelStyle = NSBezelStyleInline;
        button.bordered = NO;
        button.font = [NSFont systemFontOfSize:13];
        button.contentTintColor = NSColor.linkColor;
        SCBind(button, @"title", keys[i]);
        if (i == 0) { button.toolTip = @"https://github.com/houzi3/Anmir"; }
        else if (i == 1) { button.toolTip = @"https://github.com/houzi3/Anmir/issues"; }
        else { SCBind(button, @"toolTip", @"Open Source Licenses"); }
        [links addArrangedSubview:button];
    }
    [stack addArrangedSubview:links];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged:)
        name:SCLanguageChangedNotification object:nil];
    [window.contentView layoutSubtreeIfNeeded];
    [window setContentSize:NSMakeSize(520, MAX(300, ceil(stack.fittingSize.height) + 56))];
    [window center];
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)anyWindowVisible { return self.window.visible || self.licenses.window.visible; }
- (void)openProject:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/houzi3/Anmir"]];
}
- (void)openFeedback:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/houzi3/Anmir/issues"]];
}
- (void)refreshLicenses {
    if (!self.licenseText) { return; }
    NSMutableString *content = [NSMutableString stringWithFormat:@"%@\n\n",
        SCLocalized(@"Anmir is licensed under Apache 2.0. Third-party components retain their own licenses.")];
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray *paths = @[@"LICENSE", @"NOTICE", @"THIRD_PARTY.md"];
    NSArray *titles = @[@"Anmir License", @"Upstream Notices", @"Third-Party Notices"];
    NSMutableArray<NSURL *> *documents = [NSMutableArray array];
    for (NSUInteger i = 0; i < paths.count; ++i) {
        NSURL *url = [self.bundle.resourceURL URLByAppendingPathComponent:paths[i]];
        NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if (text.length) { [content appendFormat:@"%@\n\n%@\n\n", SCLocalized(titles[i]), text]; [documents addObject:url]; }
    }
    NSURL *directory = [self.bundle.resourceURL URLByAppendingPathComponent:@"licenses" isDirectory:YES];
    NSDirectoryEnumerator *entries = [files enumeratorAtURL:directory includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSArray<NSURL *> *licenses = [entries.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.path compare:b.path];
    }];
    for (NSURL *url in licenses) {
        BOOL isDirectory = NO;
        if (![files fileExistsAtPath:url.path isDirectory:&isDirectory] || isDirectory) { continue; }
        NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if (text.length) { [content appendFormat:@"%@\n\n%@\n\n", url.lastPathComponent, text]; [documents addObject:url]; }
    }
    if (!documents.count) { [content appendString:SCLocalized(@"License files are unavailable in this build.")]; }
    NSScrollView *scroll = self.licenseText.enclosingScrollView;
    NSPoint position = scroll.contentView.bounds.origin;
    self.licenseText.string = content;
    [scroll.contentView scrollToPoint:position];
    [scroll reflectScrolledClipView:scroll.contentView];
}
- (void)languageChanged:(NSNotification *)notification { (void)notification; [self refreshLicenses]; }
- (void)showLicenses:(id)sender {
    (void)sender;
    if (!self.licenses) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 520)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
            backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.minSize = NSMakeSize(420, 300);
        SCBind(window, @"title", @"Open Source Licenses");
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scroll.hasVerticalScroller = YES;
        self.licenseText = [[NSTextView alloc] initWithFrame:(NSRect){NSZeroPoint, scroll.contentSize}];
        self.licenseText.editable = NO;
        self.licenseText.richText = NO;
        self.licenseText.textColor = NSColor.textColor;
        self.licenseText.backgroundColor = NSColor.textBackgroundColor;
        self.licenseText.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        self.licenseText.textContainerInset = NSMakeSize(14, 12);
        self.licenseText.autoresizingMask = NSViewWidthSizable;
        self.licenseText.verticallyResizable = YES;
        self.licenseText.horizontallyResizable = NO;
        self.licenseText.textContainer.containerSize = NSMakeSize(scroll.contentSize.width, CGFLOAT_MAX);
        self.licenseText.textContainer.widthTracksTextView = YES;
        scroll.documentView = self.licenseText;
        [window.contentView addSubview:scroll];
        self.licenses = [[NSWindowController alloc] initWithWindow:window];
        [window center];
    }
    [self refreshLicenses];
    [self.licenses showWindow:nil];
    [self.licenses.window makeKeyAndOrderFront:nil];
}
@end
