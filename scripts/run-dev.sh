#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Launch this checkout's build as a separate dev copy in the background and print its pid.
# The copy ("vChain Dev") has its own process name (VChainDev), bundle id (own preferences) and MIDI port
# ("vChain Dev"), plays a test file instead of capturing (no permission prompts) and never takes
# focus. It does join Ableton Link like the real app. Screenshot it with scripts/screenshot.sh.
#   PID=$(./scripts/run-dev.sh <audio file> [app args…]);  kill $PID
# Extra args go to the app, e.g. -forceAppearance dark, -debugOpen settings,
# -settingsPane general|bpm|midi|energy.
set -euo pipefail
cd "$(dirname "$0")/.."
FILE="${1:?usage: run-dev.sh <audio file> [app args…]}"; shift
SRC="build/vChain.app"
DEV="build/vChain Dev.app"
rm -rf "$DEV"
cp -R "$SRC" "$DEV"
mv "$DEV/Contents/MacOS/VChain" "$DEV/Contents/MacOS/VChainDev"
plutil -replace CFBundleExecutable -string VChainDev "$DEV/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.bitmapbabe.vchain.dev "$DEV/Contents/Info.plist"
plutil -replace CFBundleName -string "vChain Dev" "$DEV/Contents/Info.plist"
codesign --force --sign - "$DEV" >/dev/null 2>&1
open -g -n "$DEV" --args -ApplePersistenceIgnoreState YES -midiPortName "vChain Dev" \
  -testAudioFile "$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")" "$@"
PID=""
for _ in $(seq 1 40); do
  PID=$(pgrep -n -f "$PWD/$DEV/Contents/MacOS/VChainDev" || true)
  [ -n "$PID" ] && break
  sleep 0.25
done
echo "$PID"
