#include "toolbar_preferences.h"

#include <stdlib.h>
#include <SDL3/SDL.h>

#include "util/log.h"
#ifdef __APPLE__
# include "sys/macos/settings.h"
#endif

#define SC_TOOLBAR_VISIBILITY_FILENAME "toolbar-visible.txt"

static char *
sc_toolbar_preferences_get_path(void) {
    char *pref = SDL_GetPrefPath("Genymobile", "scrcpy");
    if (!pref) {
        LOGW("Could not resolve toolbar preferences directory: %s",
             SDL_GetError());
        return NULL;
    }

    char *path = NULL;
    if (asprintf(&path, "%s%s", pref,
                 SC_TOOLBAR_VISIBILITY_FILENAME) == -1) {
        LOG_OOM();
        path = NULL;
    }
    SDL_free(pref);
    return path;
}

bool
sc_toolbar_preferences_load_saved_visible(bool *visible) {
    char *path = sc_toolbar_preferences_get_path();
    if (!path) {
        return false;
    }

    size_t size = 0;
    char *data = SDL_LoadFile(path, &size);
    free(path);
    if (!data) {
        // Missing preferences are expected on the first run.
        return false;
    }

    bool valid = size == 1 && (data[0] == '0' || data[0] == '1');
    if (!valid) {
        LOGW("Ignoring invalid toolbar visibility preference");
    } else {
        *visible = data[0] == '1';
    }
    SDL_free(data);
    return valid;
}

bool
sc_toolbar_preferences_load_visible(void) {
#ifdef __APPLE__
    if (sc_settings_is_app()) { return sc_settings_toolbar_visible(); }
#endif
    bool visible;
    return sc_toolbar_preferences_load_saved_visible(&visible) ? visible : true;
}

bool
sc_toolbar_preferences_save_visible(bool visible) {
#ifdef __APPLE__
    if (sc_settings_is_app()) { return sc_settings_set_toolbar_visible(visible); }
#endif
    char *path = sc_toolbar_preferences_get_path();
    if (!path) {
        return false;
    }

    char value = visible ? '1' : '0';
    bool ok = SDL_SaveFile(path, &value, sizeof(value));
    if (!ok) {
        LOGW("Could not save toolbar visibility preference: %s",
             SDL_GetError());
    }
    free(path);
    return ok;
}
