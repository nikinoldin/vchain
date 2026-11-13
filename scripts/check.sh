#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs the VChainKit checks (XCTest is unavailable with Command Line Tools only), then the bench's unit
# checks and synthetic scenarios (VChainBench: offline, never joins Link). BENCH_STAGE = the assert level
# for the synthetic scenarios (1 = the shipped pipeline's targets, docs/beat-tracking.md). Any build failure or failed check fails the script.
set -euo pipefail
cd "$(dirname "$0")/.."
BENCH_STAGE=1
BENCH_PIPELINE=tempo-phase
swift run --build-system native VChainChecks "$@"
# The bench build is quiet unless something goes wrong: show its errors, warnings and summary lines,
# but take the exit code from swift build itself.
if ! log="$(swift build --build-system native -c release --product VChainBench 2>&1)"; then
  echo "$log" >&2
  echo "VChainBench build failed" >&2
  exit 1
fi
echo "$log" | grep -E "error|warning: unre|Build" || true
.build/release/VChainBench --unit | tail -1
.build/release/VChainBench --synthetic all --pipeline "$BENCH_PIPELINE" --assert "$BENCH_STAGE" | tail -1
