#include "device_info.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "adb/adb.h"

void
sc_device_info_init(struct sc_device_info *info) {
    info->manufacturer = NULL;
    info->model = NULL;
    info->android_version = NULL;
    info->api_level = NULL;
}

void
sc_device_info_load(struct sc_device_info *info, struct sc_intr *intr,
                    const char *serial) {
    free(info->manufacturer);
    free(info->model);
    info->manufacturer = sc_adb_getprop(intr, serial, "ro.product.manufacturer", SC_ADB_SILENT);
    if (!info->manufacturer || !*info->manufacturer) {
        free(info->manufacturer);
        info->manufacturer = sc_adb_getprop(intr, serial, "ro.product.brand", SC_ADB_SILENT);
    }
    info->model = sc_adb_getprop(intr, serial, "ro.product.model", SC_ADB_SILENT);
    free(info->android_version);
    free(info->api_level);
    info->android_version =
        sc_adb_getprop(intr, serial, "ro.build.version.release",
                       SC_ADB_SILENT);
    info->api_level =
        sc_adb_getprop(intr, serial, "ro.build.version.sdk", SC_ADB_SILENT);
}

void
sc_device_info_destroy(struct sc_device_info *info) {
    free(info->manufacturer);
    free(info->model);
    free(info->android_version);
    free(info->api_level);
}

char *
sc_device_info_build_name(const struct sc_device_info *info,
                          const char *fallback) {
    const char *model = info->model && *info->model ? info->model : fallback;
    const char *brand = info->manufacturer;
    if (!brand || !*brand) { return strdup(model); }
    size_t i = 0;
    while (brand[i] && model[i]
            && tolower((unsigned char)brand[i]) == tolower((unsigned char)model[i])) {
        ++i;
    }
    if (!brand[i] && (!model[i] || isspace((unsigned char)model[i]) || model[i] == '-')) {
        return strdup(model);
    }
    char *name;
    if (asprintf(&name, "%s %s", brand, model) == -1) { return NULL; }
    name[0] = toupper((unsigned char)name[0]);
    return name;
}

char *
sc_device_info_build_window_title(const struct sc_device_info *info,
                                  const char *base_title) {
    if (!info->android_version || !*info->android_version) {
        return strdup(base_title);
    }

    char *title;
    int r;
    if (info->api_level && *info->api_level) {
        r = asprintf(&title, "%s · Android %s | API %s", base_title,
                     info->android_version, info->api_level);
    } else {
        r = asprintf(&title, "%s · Android %s", base_title,
                     info->android_version);
    }
    return r == -1 ? NULL : title;
}

char *
sc_device_info_build_subtitle(const struct sc_device_info *info) {
    if (!info->android_version || !*info->android_version) {
        return NULL;
    }

    char *subtitle;
    int r;
    if (info->api_level && *info->api_level) {
        r = asprintf(&subtitle, "Android %s | API %s", info->android_version,
                     info->api_level);
    } else {
        r = asprintf(&subtitle, "Android %s", info->android_version);
    }
    return r == -1 ? NULL : subtitle;
}
