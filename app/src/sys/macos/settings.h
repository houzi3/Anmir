#ifndef SC_MACOS_SETTINGS_H
#define SC_MACOS_SETTINGS_H
#include <stdbool.h>

bool sc_settings_is_app(void);
bool sc_settings_toolbar_visible(void);
bool sc_settings_set_toolbar_visible(bool visible);

#ifdef __OBJC__
#import <Foundation/Foundation.h>
extern NSNotificationName const SCSettingsChangedNotification;
void SCSettingsInitialize(void);
NSString *SCSettingsTheme(void);
BOOL SCSettingsHasTheme(void);
void SCSettingsAcceptOnboarding(NSString *theme, NSString *language);
NSString *SCSettingsLanguage(void);
void SCSettingsSetTheme(NSString *choice);
void SCSettingsSetLanguage(NSString *choice);
void SCSettingsPreviewLanguage(NSString *choice);
void SCSettingsEndLanguagePreview(void);
#endif
#endif
