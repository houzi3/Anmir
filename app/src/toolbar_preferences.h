#ifndef SC_TOOLBAR_PREFERENCES_H
#define SC_TOOLBAR_PREFERENCES_H

#include "common.h"

#include <stdbool.h>

bool
sc_toolbar_preferences_load_visible(void);

// Read the previous file-based preference without conflating an absent or
// invalid file with a user who explicitly disabled the toolbar.
bool
sc_toolbar_preferences_load_saved_visible(bool *visible);

bool
sc_toolbar_preferences_save_visible(bool visible);

#endif
