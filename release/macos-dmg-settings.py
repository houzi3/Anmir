"""Anmir's drag-to-Applications layout, generated without a desktop session."""
import os

application = defines["app"]
application_name = os.path.basename(application)
format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {
    "Applications": "/Applications",
    # Apple's built-in pane opens before Anmir has been approved to run.
    "Privacy & Security": "/System/Library/PreferencePanes/Security.prefPane",
}
background = defines["background"]
window_rect = ((280, 180), (600, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
icon_size = 64
text_size = 12
label_pos = "bottom"
icon_locations = {
    application_name: (154, 140),
    "Applications": (446, 140),
    "Privacy & Security": (486, 266),
}
