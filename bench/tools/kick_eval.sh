#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds and runs kick_eval (see kick_eval.cpp) from the repo it lives in, so a worktree measures its own DSP code.
# Usage: bench/tools/kick_eval.sh [track names without extension...]   (default: all annotated tracks with audio)
# Audio: $VCHAIN_BENCH_AUDIO or ~/Music/vChainBench/audio. Prints a table and the means.
set -euo pipefail
cd "$(dirname "$0")/../.."
AUDIO="${VCHAIN_BENCH_AUDIO:-$HOME/Music/vChainBench/audio}"
OUT="$(mktemp -d)/kick_eval"
clang++ -std=c++17 -O2 -ISources/VChainDSP/include -ISources/VChainBench bench/tools/kick_eval.cpp \
  Sources/VChainDSP/trigger_bands.cpp Sources/VChainDSP/drum_onsets.cpp Sources/VChainBench/decode.cpp \
  -framework AudioToolbox -framework CoreFoundation -o "$OUT"
args=()
if [ $# -gt 0 ]; then names=("$@"); else names=(); for f in bench/annotations/*.beats; do names+=("$(basename "$f" .beats)"); done; fi
for n in "${names[@]}"; do
  a="$AUDIO/$n.mp3"; [ -f "$a" ] || continue
  args+=("$a" "bench/annotations/$n.beats")
done
"$OUT" "${args[@]}"
