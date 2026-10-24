#ifndef SC_THEME_H
#define SC_THEME_H

#include <stdbool.h>

// Native app startup loads the saved choice, or asks on the first GUI launch.
// Standalone CLI and non-macOS builds retain their existing dark appearance.
bool
sc_theme_initialize(void);

bool
sc_theme_is_light(void);

void
sc_theme_install_menu(void);

#endif
