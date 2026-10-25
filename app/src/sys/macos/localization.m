#import "localization.h"
#include "../../localization.h"

NSNotificationName const SCLanguageChangedNotification = @"AnmirLanguageChanged";
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *tables;
static NSDictionary<NSString *, NSDictionary<NSString *, NSData *> *> *encodedTables;
static NSString *language = @"en";
static NSMapTable<id, NSMutableDictionary *> *bindings;

NSString *SCResolveLanguage(NSString *choice, NSArray<NSString *> *preferred) {
    if ([@[@"en", @"zh-Hans", @"zh-Hant"] containsObject:choice]) { return choice; }
    for (NSString *identifier in preferred) {
        NSString *tag = [[identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
        NSArray *parts = [tag componentsSeparatedByString:@"-"];
        if ([parts.firstObject isEqualToString:@"en"]) { return @"en"; }
        if (![parts.firstObject isEqualToString:@"zh"]) { continue; }
        if ([parts containsObject:@"hans"]) { return @"zh-Hans"; }
        if ([parts containsObject:@"hant"]) { return @"zh-Hant"; }
        return [parts containsObject:@"tw"] || [parts containsObject:@"hk"] || [parts containsObject:@"mo"]
            ? @"zh-Hant" : @"zh-Hans";
    }
    return @"en";
}

NSString *SCCurrentLanguage(void) {
    @synchronized (SCLanguageChangedNotification) { return language; }
}

NSString *SCLocalized(NSString *key) {
    @synchronized (SCLanguageChangedNotification) {
        return tables[language][key] ?: tables[@"en"][key] ?: key;
    }
}

const char *sc_localize(const char *key) {
    if (!key) { return NULL; }
    NSString *identifier = [NSString stringWithUTF8String:key];
    @synchronized (SCLanguageChangedNotification) {
        NSData *value = encodedTables[language][identifier ?: @""] ?: encodedTables[@"en"][identifier ?: @""];
        // Immutable, NUL-terminated storage survives autorelease pools and
        // language changes, including asynchronous SDL file-dialog callbacks.
        return value ? value.bytes : key;
    }
}

static void SCApplyBinding(id target, NSString *property, NSArray *binding) {
    NSString *value = SCLocalized(binding[0]);
    NSArray *arguments = binding[1];
    if (arguments.count) {
        // Match the original format once: a device name containing %@ must
        // never become another substitution or a printf format string.
        static NSRegularExpression *slots;
        if (!slots) { slots = [NSRegularExpression regularExpressionWithPattern:@"%(?:([0-9]+)\\$)?@" options:0 error:nil]; }
        NSMutableString *formatted = [NSMutableString string];
        NSUInteger cursor = 0, sequential = 0;
        for (NSTextCheckingResult *match in [slots matchesInString:value options:0 range:NSMakeRange(0, value.length)]) {
            [formatted appendString:[value substringWithRange:NSMakeRange(cursor, match.range.location - cursor)]];
            NSRange position = [match rangeAtIndex:1];
            NSUInteger index = position.location == NSNotFound ? sequential++
                : [[value substringWithRange:position] integerValue] - 1;
            [formatted appendString:index < arguments.count ? arguments[index] : [value substringWithRange:match.range]];
            cursor = NSMaxRange(match.range);
        }
        [formatted appendString:[value substringFromIndex:cursor]];
        value = formatted;
    }
    [target setValue:value forKey:property];
}

void SCBindFormat(id target, NSString *property, NSString *key, NSArray<NSString *> *arguments) {
    NSCAssert(NSThread.isMainThread, @"Presentation bindings must be changed on the main thread");
    if (!target) { return; }
    if (!bindings) { bindings = [NSMapTable weakToStrongObjectsMapTable]; }
    NSMutableDictionary *properties = [bindings objectForKey:target];
    if (!properties) {
        properties = [NSMutableDictionary dictionary];
        [bindings setObject:properties forKey:target];
    }
    NSArray *binding = @[[key copy], [arguments copy]];
    properties[property] = binding;
    SCApplyBinding(target, property, binding);
}

void SCBind(id target, NSString *property, NSString *key) {
    SCBindFormat(target, property, key, @[]);
}

void SCUseLanguage(NSString *choice) {
    NSCAssert(NSThread.isMainThread, @"Language changes must be applied on the main thread");
    NSString *resolved = SCResolveLanguage(choice, NSLocale.preferredLanguages);
    BOOL changed;
    @synchronized (SCLanguageChangedNotification) {
        changed = ![resolved isEqualToString:language];
        language = resolved;
    }
    if (!changed) { return; }
    for (id target in bindings.keyEnumerator.allObjects) {
        NSDictionary *properties = [[bindings objectForKey:target] copy];
        for (NSString *property in properties) { SCApplyBinding(target, property, properties[property]); }
    }
    [NSNotificationCenter.defaultCenter postNotificationName:SCLanguageChangedNotification object:nil];
}

void SCLocalizationInitialize(NSBundle *resources, NSString *choice) {
    NSMutableDictionary *loaded = [NSMutableDictionary dictionary];
    NSMutableDictionary *encoded = [NSMutableDictionary dictionary];
    for (NSString *code in @[@"en", @"zh-Hans", @"zh-Hant"]) {
        NSString *path = [resources pathForResource:@"Localizable" ofType:@"strings"
            inDirectory:nil forLocalization:code];
        NSDictionary *table = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        loaded[code] = table ?: @{};
        NSMutableDictionary *strings = [NSMutableDictionary dictionary];
        for (NSString *key in table) {
            NSMutableData *bytes = [[table[key] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            [bytes increaseLengthBy:1]; // NUL terminator.
            strings[key] = [bytes copy];
        }
        encoded[code] = [strings copy];
    }
    // Initialize once in production. Tests may supply another resource bundle.
    @synchronized (SCLanguageChangedNotification) { tables = [loaded copy]; encodedTables = [encoded copy]; }
    SCUseLanguage(choice);
}
