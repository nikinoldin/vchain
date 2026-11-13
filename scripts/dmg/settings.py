# SPDX-License-Identifier: GPL-3.0-or-later
# dmgbuild settings for vChain.dmg (scripts/release.sh passes app=<path to vChain.app> and background=<tiff>).
# Positions sit inside the rounded window of the BitmapBabe frame (assets/dmg/background.svg, 660 × 508) and match the
# arrow and captions drawn by scripts/dmg/background.py.
app = defines["app"]

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    "vChain.app": (215, 245),
    "Applications": (445, 245),
}
background = defines["background"]
# The window frame: the 660 × 508 background plus Finder's 32 pt title bar (macOS 26).
window_rect = ((200, 120), (660, 540))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
