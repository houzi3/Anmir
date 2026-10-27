#ifndef SC_APK_INSTALLER_H
#define SC_APK_INSTALLER_H

#include <stdbool.h>

// Handle the private invocation used by the bundled Finder extension.
// Returns the installer exit status and sets handled only for that invocation.
int sc_apk_installer_try_run(int argc, char *argv[], bool *handled);

#endif
