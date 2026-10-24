#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const SCLanguageChangedNotification;

// Call on the main thread. Resource dictionaries are immutable and retained
// for the process lifetime so C strings used by asynchronous dialogs stay live.
void SCLocalizationInitialize(NSBundle *resources, NSString *choice);
NSString *SCResolveLanguage(NSString *choice, NSArray<NSString *> *preferred);
NSString *SCCurrentLanguage(void);
void SCUseLanguage(NSString *choice);
NSString *SCLocalized(NSString *key);

// Bind only presentation properties, never editable text or protocol values.
// Weak targets keep closed windows/temporary table cells from being retained.
void SCBind(id _Nullable target, NSString *property, NSString *key);
void SCBindFormat(id _Nullable target, NSString *property, NSString *key,
                  NSArray<NSString *> *arguments);
NS_ASSUME_NONNULL_END
