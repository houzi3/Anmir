// Exercise production scheduling and networking with an isolated preference
// store and an in-memory URL protocol. No GitHub, phones or windows are used.
#import "../src/sys/macos/updater.m"
#include <assert.h>
#include <stdatomic.h>

NSString *SCLocalized(NSString *key) { return key; }
void SCBind(id target, NSString *property, NSString *key) { (void)target; (void)property; (void)key; }
NSString *SCMirrorHostBundleIdentifier(void) { return @"io.github.laobie.anmir"; }
NSBundle *SCMirrorHostBundle(void) { return NSBundle.mainBundle; }
static BOOL mirroring;
NSArray<SCMirrorSession *> *SCMirrorRunningSessions(void) { return mirroring ? (id)@[@1] : @[]; }

static atomic_uint requests;
static NSDictionary *release;
static NSInteger status;
static NSTimeInterval responseDelay;
@interface SCUpdateProtocol : NSURLProtocol
@property BOOL stopped;
@end
@implementation SCUpdateProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"api.github.com"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    atomic_fetch_add(&requests, 1);
    NSDictionary *payload = release; NSInteger code = status;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(responseDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.stopped) { return; }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:code HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading { self.stopped = YES; }
@end

@interface SCUpdateFixture : SCUpdater
@property(strong) NSDate *clock;
@property(strong) NSCalendar *fixtureCalendar;
@property(strong) NSUserDefaults *store;
@property(copy) NSString *domain;
@property NSUInteger presented;
@property NSUInteger messages;
@property NSUInteger progressCount;
@property NSUInteger completed;
@property BOOL sawSkipped;
@end
@implementation SCUpdateFixture
- (BOOL)isHost { return YES; }
- (instancetype)init {
    self = [super init];
    if (self) {
        self.domain = [@"Anmir.UpdaterTest." stringByAppendingString:NSUUID.UUID.UUIDString];
        self.store = [[NSUserDefaults alloc] initWithSuiteName:self.domain];
        self.fixtureCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        self.fixtureCalendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        NSDateComponents *parts = [NSDateComponents new];
        parts.year = 2026; parts.month = 10; parts.day = 25; parts.hour = 23; parts.minute = 59;
        self.clock = [self.fixtureCalendar dateFromComponents:parts];
    }
    return self;
}
- (NSDate *)now { return self.clock; }
- (NSCalendar *)calendar { return self.fixtureCalendar; }
- (NSUserDefaults *)preferences { return self.store; }
- (NSString *)currentVersion { return @"0.0.9"; }
- (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.protocolClasses = @[SCUpdateProtocol.class]; return config;
}
- (void)showProgress:(NSString *)title { (void)title; ++self.progressCount; }
- (void)message:(NSString *)title detail:(NSString *)detail { (void)title; (void)detail; ++self.messages; }
- (void)showRelease:(NSDictionary *)payload current:(NSString *)current latest:(NSString *)latest {
    (void)payload; (void)current;
    ++self.presented;
    self.sawSkipped = [[self.store stringForKey:SCSkippedUpdateVersionKey] isEqual:latest];
    [self finish:nil];
}
- (void)finish:(NSError *)error { [super finish:error]; ++self.completed; }
- (void)dealloc { [self.store removePersistentDomainForName:self.domain]; }
@end

@interface SCUpdateForwardFixture : SCUpdater
@property NSUInteger forwarded;
@end
@implementation SCUpdateForwardFixture
- (BOOL)isHost { return NO; }
- (void)forwardCheckToHost { ++self.forwarded; }
@end

static void setRelease(NSString *version) {
    NSMutableArray *assets = [NSMutableArray array];
    for (NSString *arch in @[@"arm64", @"x86_64"]) {
        NSString *name = [NSString stringWithFormat:@"Anmir-%@-%@.zip", version, arch];
        [assets addObject:@{@"name":name, @"digest":@"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            @"browser_download_url":[NSString stringWithFormat:@"https://github.com/houzi3/Anmir/releases/download/v%@/%@", version, name]}];
    }
    release = @{@"tag_name":[@"v" stringByAppendingString:version], @"draft":@NO, @"prerelease":@NO, @"assets":assets, @"body":@"Notes"};
}
static SCUpdateFixture *fixture(void) {
    atomic_store(&requests, 0); mirroring = NO; status = 200; responseDelay = .02; setRelease(@"0.1.0");
    return [SCUpdateFixture new];
}
static void waitFor(SCUpdateFixture *test, NSUInteger count) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (test.completed < count && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    }
    assert(test.completed == count);
}
int main(void) { @autoreleasepool {
    SCUpdateForwardFixture *forward = [SCUpdateForwardFixture new];
    [forward check:nil];
    assert(forward.forwarded == 1 && !forward.busy);

    // Startup is scheduled once for seven seconds, and a manual check cancels it.
    SCUpdateFixture *test = fixture(); test.clock = NSDate.date;
    NSTimeInterval delay = [test startupDelay];
    [test scheduleAutomaticCheck]; NSTimer *timer = test.startupTimer;
    assert(delay >= 0 && delay <= 7);
    assert(timer && fabs([timer.fireDate timeIntervalSinceDate:test.clock] - delay) < .1);
    [test scheduleAutomaticCheck]; assert(test.startupTimer == timer);
    [test check:nil]; assert(!timer.valid && !test.startupTimer); waitFor(test, 1);
    assert(atomic_load(&requests) == 1 && test.presented == 1);
    test = fixture(); test.clock = NSDate.date;
    [test scheduleAutomaticCheck]; timer = test.startupTimer;
    [timer fire]; [timer invalidate]; waitFor(test, 1);
    assert(!test.startupTimer && !test.progressCount && test.presented == 1);

    // Persist the daily budget across updater instances. Midnight is a new day,
    // even when less than 24 hours elapsed since the previous check.
    test = fixture(); [test checkAutomatically:YES]; waitFor(test, 1);
    assert(test.presented == 1 && !test.progressCount && !test.messages);
    [test checkAutomatically:YES]; assert(atomic_load(&requests) == 1);
    SCUpdateFixture *relaunch = [SCUpdateFixture new]; relaunch.store = test.store; relaunch.clock = test.clock;
    [relaunch checkAutomatically:YES]; assert(!relaunch.busy && atomic_load(&requests) == 1);
    test.clock = [test.clock dateByAddingTimeInterval:120];
    [test checkAutomatically:YES]; waitFor(test, 2); assert(atomic_load(&requests) == 2);

    // Network errors and an already-current version stay silent automatically.
    test = fixture(); status = 503; [test checkAutomatically:YES]; waitFor(test, 1);
    [test checkAutomatically:YES]; assert(atomic_load(&requests) == 1 && !test.messages && !test.progressCount);
    [test check:nil]; waitFor(test, 2); assert(atomic_load(&requests) == 2 && test.messages == 1);
    test = fixture(); setRelease(@"0.0.9"); [test checkAutomatically:YES]; waitFor(test, 1);
    assert(!test.messages && !test.presented);
    [test check:nil]; waitFor(test, 2); assert(test.messages == 1);

    // Skips affect automatic prompts only, and do not suppress a later release.
    test = fixture(); [test.store setObject:@"0.1.0" forKey:SCSkippedUpdateVersionKey];
    [test checkAutomatically:YES]; waitFor(test, 1); assert(!test.presented);
    [test check:nil]; waitFor(test, 2); assert(test.presented == 1 && test.sawSkipped);
    setRelease(@"0.2.0"); test.clock = [test.clock dateByAddingTimeInterval:120];
    [test checkAutomatically:YES]; waitFor(test, 3); assert(test.presented == 2 && !test.sawSkipped);

    // Detect a mirror which starts while the request is in flight, and remain
    // silent if a mirror was already present. Explicit manual checks still work.
    test = fixture(); [test checkAutomatically:YES]; mirroring = YES; waitFor(test, 1);
    assert(!test.presented && !test.messages && !test.progressCount);
    test.clock = [test.clock dateByAddingTimeInterval:120];
    [test checkAutomatically:YES]; waitFor(test, 2); assert(!test.presented);
    [test check:nil]; waitFor(test, 3); assert(test.presented == 1);

    // Manual input adopts the pending request rather than issuing a duplicate.
    test = fixture(); [test checkAutomatically:YES]; [test check:nil]; waitFor(test, 1);
    assert(atomic_load(&requests) == 1 && test.presented == 1 && test.progressCount == 1);
    test = fixture(); [test checkAutomatically:YES]; [test cancel:nil]; waitFor(test, 1);
    assert(!test.presented && !test.messages && !test.busy);
    puts("Automatic update scheduling, daily budget, quiet failures, skip, mirroring and manual override passed");
} return 0; }
