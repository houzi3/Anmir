#ifndef SC_DEVICE_PICKER_H
#define SC_DEVICE_PICKER_H

#include "common.h"
#include <SDL3/SDL.h>

struct scrcpy_options;
struct sc_intr;

enum sc_device_picker_result {
    SC_DEVICE_PICKER_CONTINUE,
    SC_DEVICE_PICKER_FINISHED,
    SC_DEVICE_PICKER_ERROR,
};

/**
 * macOS application startup only. ADB must already be initialized.
 * Continue normal CLI startup when no manager applies; otherwise manage
 * independent mirror processes and report whether native startup finished.
 */
enum sc_device_picker_result
sc_device_picker_run(const struct scrcpy_options *options, struct sc_intr *intr);

void
sc_device_picker_install_menu(SDL_Window *window);

void
sc_device_picker_set_current_device(const char *serial);

/** Notify the manager after the mirror window becomes visible. macOS only. */
void
sc_device_picker_mirror_shown(void);

#endif
