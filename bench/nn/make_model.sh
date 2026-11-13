#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Makes the Core ML model build.sh bundles: Beat This! final0 -> ~/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage.
# Uses the annotation venv (bench/tools/annotate.sh) plus coremltools. Not committed to git (39 MB).
set -euo pipefail
cd "$(dirname "$0")"
VENV="${VCHAIN_BENCH_HOME:-$HOME/Music/vChainBench}/.venv"
OUT="${1:-$HOME/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage}"
VIRTUAL_ENV="$VENV" uv pip install -q coremltools
mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"
"$VENV/bin/python" -I make_model.py "$OUT"
