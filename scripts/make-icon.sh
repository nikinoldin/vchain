#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regenerate the app icon (the BPM tag on a white grid squircle, AppIconRender) from the app's own views (run it when the BPM tag changes):
# builds the app, runs a throwaway copy with -debugRenderIcon (offscreen, no window, all modules off so it
# never joins Link; its MIDI port, which always exists, is named "vChain Icon") and turns the iconset into assets/AppIcon.icns + AppIcon.png (1024).
#   scripts/make-icon.sh [out dir]   (default: assets/)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mkdir -p "${1:-assets}" && cd "${1:-assets}" && pwd)"
swift build --build-system native -c release --product VChain 2>&1 | { grep -E "error:" || true; }
BIN="$(swift build --build-system native -c release --show-bin-path 2>/dev/null)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
APP="$TMP/VChainIcon.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN/VChain" "$APP/Contents/MacOS/VChainIcon"
cp Info.plist "$APP/Contents/Info.plist"
cp Sources/VChain/Fonts/* "$APP/Contents/Resources/Fonts/"
plutil -replace CFBundleExecutable -string VChainIcon "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.bitmapbabe.vchain.icon "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "vChain Icon" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
SET="$TMP/AppIcon.iconset"
# -W waits for the app to quit (it does once the iconset is written).
open -W -g -n "$APP" --args -ApplePersistenceIgnoreState YES -bpmEnabled NO -stripEnabled NO -energyEnabled NO \
  -midiPortName "vChain Icon" -debugRenderIcon "$SET"
[ -f "$SET/icon_512x512@2x.png" ] || { echo "render failed: no iconset in $SET" >&2; exit 1; }
iconutil -c icns "$SET" -o "$OUT/AppIcon.icns"
cp "$SET/icon_512x512@2x.png" "$OUT/AppIcon.png"
echo "$OUT/AppIcon.icns, $OUT/AppIcon.png"
