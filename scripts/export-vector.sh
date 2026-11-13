#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Exports the three modules and the keychain at rest as vector PDFs and SVGs (light and dark).
# Usage: scripts/export-vector.sh [out dir] [app]   (defaults: build/vector, build/vChain.app)
# Needs pdftocairo (brew install poppler) for the SVGs; without it you get the PDFs only.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/vector}"
APP="${2:-build/vChain.app}"
BIN="$APP/Contents/MacOS/VChain"
[ -x "$BIN" ] || { echo "No app at $APP: run ./build.sh first" >&2; exit 1; }
for look in light dark; do
    mkdir -p "$OUT/$look"
    # Renders offscreen and quits; BPM detection off so it never joins Link.
    "$BIN" -debugRenderVector "$OUT/$look" -forceAppearance "$look" -bpmEnabled NO -midiPortName "vChain Export" >/dev/null 2>&1
    if command -v pdftocairo >/dev/null; then
        for pdf in "$OUT/$look"/*.pdf; do pdftocairo -svg "$pdf" "${pdf%.pdf}.svg"; done
    fi
done
echo "Wrote $(ls "$OUT"/*/* | wc -l | tr -d ' ') files to $OUT"
