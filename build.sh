#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build "build/vChain.app": SwiftPM release build (C++ engine + SwiftUI app), hand-assembled bundle, signature.
# Prerequisites: Command Line Tools, `git submodule update --init --recursive` (Ableton Link and aubio).
# UNIVERSAL=1 also builds for Intel (x86_64, in .build-x86) and merges both into one universal app (releases do).
set -euo pipefail
cd "$(dirname "$0")"
# pipefail: a failed build fails the script (only the deprecation notice is filtered out of the log).
swift build --build-system native -c release --product VChain 2>&1 | { grep -v "build-system native' has been deprecated" || true; }
BIN="$(swift build --build-system native -c release --show-bin-path 2>/dev/null)"
[ -x "$BIN/VChain" ] || { echo "Build failed" >&2; exit 1; }

APP="build/vChain.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
if [ "${UNIVERSAL:-0}" = 1 ]; then
  X86=(--build-system native -c release --triple x86_64-apple-macosx15.0 --scratch-path .build-x86)
  swift build "${X86[@]}" --product VChain 2>&1 | { grep -v "build-system native' has been deprecated" || true; }
  X86_BIN="$(swift build "${X86[@]}" --show-bin-path 2>/dev/null)"
  [ -x "$X86_BIN/VChain" ] || { echo "Intel build failed" >&2; exit 1; }
  lipo -create "$BIN/VChain" "$X86_BIN/VChain" -output "$APP/Contents/MacOS/VChain"
else
  cp "$BIN/VChain" "$APP/Contents/MacOS/VChain"
fi
cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/VChain/Fonts/* "$APP/Contents/Resources/Fonts/"
# Sparkle (updates): the framework with its helper apps and XPC services, kept as built (symlinks intact).
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# The licence (GPL-3.0-or-later) and the third-party notices travel with the app.
cp LICENSE THIRD_PARTY_NOTICES.md assets/Credits.html "$APP/Contents/Resources/"

# Beat This! (MIT) as a Core ML model, bundled so the NN front end works offline (no download at first launch). Make it once with
# bench/nn/make_model.sh; the app compiles it at first launch into ~/Library/Application Support/vChain/NN.
MODEL="${VCHAIN_NN_MODEL:-$HOME/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage}"
if [ -d "$MODEL" ]; then
  cp -R "$MODEL" "$APP/Contents/Resources/beat_this_final0_T600_fp16.mlpackage"
else
  echo "warning: no Beat This! model at $MODEL (bench/nn/make_model.sh): building without the NN front end (drum-only)" >&2
fi

# Sign with the persistent "vChain Dev" certificate so macOS keeps the Screen Recording and
# Microphone permissions across rebuilds; fall back to ad-hoc (permissions are asked again) without it.
# Sparkle's parts are signed first, inside out (XPC services, Autoupdate, Updater.app, the framework), then the app:
# an update is only installed when it is signed like the running app.
IDENTITY="vChain Dev"
if ! security find-identity -v -p codesigning | grep -q "vChain Dev"; then
  echo "warning: \"vChain Dev\" signing identity not found; signing ad-hoc" >&2
  IDENTITY="-"
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign "$IDENTITY" "$part"
done
codesign --force --sign "$IDENTITY" "$APP"

echo ""
echo "Built: $APP"
echo "Run:   open '$APP'"
