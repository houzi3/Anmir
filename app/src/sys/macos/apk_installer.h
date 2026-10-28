#ifndef SC_APK_INSTALLER_H
#define SC_APK_INSTALLER_H

#include <stdbool.h>

// Handle the private invocation used by the bundled Finder extension.
// Returns the installer exit status and sets handled only for that invocation.
int sc_apk_installer_try_run(int argc, char *argv[], bool *handled);

#ifdef __OBJC__
@class NSString;

// Handle an APK opened by Launch Services. The request discovers currently
// available devices, installs directly when there is one, and presents a
// native chooser when there are several. Returns NO for unsupported paths.
bool sc_apk_installer_open_file(NSString *path,
                                void (^show_devices)(void));

// Make the installed Anmir bundle the preferred handler for .apk files. This
// is called only by the main launcher, never by per-device mirror helpers.
void sc_apk_installer_register_file_association(void);
#endif

// Keeps the native host event loop alive while discovery, device selection or
// installation is in progress.
bool sc_apk_installer_busy(void);

#endif
