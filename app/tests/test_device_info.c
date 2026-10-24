#include "common.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "adb/adb.h"
#include "device_info.h"

static const char *android_version;
static const char *api_level;
static const char *manufacturer;
static const char *model;

char *
sc_adb_getprop(struct sc_intr *intr, const char *serial, const char *prop,
               unsigned flags) {
    (void) intr;
    (void) serial;
    (void) flags;
    const char *value = !strcmp(prop, "ro.build.version.release") ? android_version
        : !strcmp(prop, "ro.build.version.sdk") ? api_level
        : !strcmp(prop, "ro.product.manufacturer") ? manufacturer
        : !strcmp(prop, "ro.product.model") ? model : NULL;
    return value ? strdup(value) : NULL;
}

static void
test_load(void) {
    struct sc_device_info info;
    sc_device_info_init(&info);

    android_version = "16";
    api_level = "36";
    manufacturer = "Google";
    model = "Pixel 7";
    sc_device_info_load(&info, NULL, "serial");
    assert(!strcmp(info.android_version, "16"));
    assert(!strcmp(info.api_level, "36"));
    assert(!strcmp(info.manufacturer, "Google"));
    assert(!strcmp(info.model, "Pixel 7"));

    android_version = NULL;
    api_level = NULL;
    manufacturer = NULL;
    model = NULL;
    sc_device_info_load(&info, NULL, "serial");
    assert(!info.android_version);
    assert(!info.api_level);
    assert(!info.manufacturer);
    assert(!info.model);
    sc_device_info_destroy(&info);
}

static void
test_device_name(void) {
    struct sc_device_info info = {.manufacturer = "OnePlus", .model = "PKG110"};
    char *name = sc_device_info_build_name(&info, "Android device");
    assert(name && !strcmp(name, "OnePlus PKG110")); free(name);
    info.manufacturer = "Google"; info.model = "Pixel 7";
    name = sc_device_info_build_name(&info, "Pixel");
    assert(name && !strcmp(name, "Google Pixel 7")); free(name);
    info.manufacturer = "samsung"; info.model = "Samsung Galaxy S23";
    name = sc_device_info_build_name(&info, "Android device");
    assert(name && !strcmp(name, "Samsung Galaxy S23")); free(name);
    info.manufacturer = NULL; info.model = NULL;
    name = sc_device_info_build_name(&info, "Fallback name");
    assert(name && !strcmp(name, "Fallback name")); free(name);
}

static void
test_window_title(void) {
    struct sc_device_info info = {
        .android_version = "16",
        .api_level = "36",
    };

    char *title = sc_device_info_build_window_title(&info, "Pixel 7");
    assert(title);
    assert(!strcmp(title, "Pixel 7 · Android 16 | API 36"));
    free(title);

    info.api_level = "";
    title = sc_device_info_build_window_title(&info, "Pixel 7");
    assert(title);
    assert(!strcmp(title, "Pixel 7 · Android 16"));
    free(title);

    info.android_version = "";
    info.api_level = "36";
    title = sc_device_info_build_window_title(&info, "Pixel 7");
    assert(title);
    assert(!strcmp(title, "Pixel 7"));
    free(title);
}

static void
test_subtitle(void) {
    struct sc_device_info info = {
        .android_version = "16",
        .api_level = "36",
    };

    char *subtitle = sc_device_info_build_subtitle(&info);
    assert(subtitle);
    assert(!strcmp(subtitle, "Android 16 | API 36"));
    free(subtitle);

    info.api_level = NULL;
    subtitle = sc_device_info_build_subtitle(&info);
    assert(subtitle);
    assert(!strcmp(subtitle, "Android 16"));
    free(subtitle);

    info.android_version = NULL;
    info.api_level = "36";
    assert(!sc_device_info_build_subtitle(&info));
}

int
main(int argc, char *argv[]) {
    (void) argc;
    (void) argv;

    test_load();
    test_device_name();
    test_window_title();
    test_subtitle();
    return 0;
}
