#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Pre-annotates every item in bench/sources.tsv with Beat This! (MIT, github.com/CPJKU/beat_this) and writes
# bench/annotations/<set_id>.beats ("time_seconds<TAB>beat_in_bar", 1 = downbeat). The venv and the audio live
# outside the repo (~/Music/vChainBench); audio is never written into the repo.
# Usage: bench/tools/annotate.sh [set_id ...]   (FORCE=1 re-annotates existing .beats files)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCES="$ROOT/bench/sources.tsv"
OUT_DIR="$ROOT/bench/annotations"
BENCH_HOME="${VCHAIN_BENCH_HOME:-$HOME/Music/vChainBench}"
AUDIO_DIR="${VCHAIN_BENCH_AUDIO:-$BENCH_HOME/audio}"
VENV="$BENCH_HOME/.venv"
BEAT_THIS="$VENV/bin/beat_this"

# --- venv (python >= 3.10) with torch + beat_this -------------------------------------------------------------
if [ ! -x "$BEAT_THIS" ]; then
  mkdir -p "$BENCH_HOME"
  if command -v uv >/dev/null 2>&1; then
    # uv-managed pythons ship without ensurepip, so let uv create the venv and install into it
    uv venv -q --python 3.12 "$VENV"
    VIRTUAL_ENV="$VENV" uv pip install -q torch torchaudio soundfile soxr beat-this \
      || VIRTUAL_ENV="$VENV" uv pip install -q torch torchaudio soundfile soxr \
           https://github.com/CPJKU/beat_this/archive/main.zip
  else
    PY=""
    for c in python3.13 python3.12 python3.11 python3.10 python3; do
      if command -v "$c" >/dev/null 2>&1 &&
         "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then PY="$c"; break; fi
    done
    [ -n "$PY" ] || { echo "annotate: need python >= 3.10 (or uv)" >&2; exit 1; }
    "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q torch torchaudio soundfile soxr beat-this \
      || "$VENV/bin/pip" install -q torch torchaudio soundfile soxr \
           https://github.com/CPJKU/beat_this/archive/main.zip
  fi
fi

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vchain-annotate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- annotate -------------------------------------------------------------------------------------------------
fail=0
while IFS=$'\t' read -r set_id kind genre source_url licence_url attribution sha256 file duration_s _rest; do
  [ "$set_id" = "set_id" ] && continue
  [ -z "$set_id" ] && continue
  if [ $# -gt 0 ] && [[ " $* " != *" $set_id "* ]]; then continue; fi
  out="$OUT_DIR/$set_id.beats"
  if [ -s "$out" ] && [ "${FORCE:-0}" != "1" ]; then echo "skip  $set_id (exists)"; continue; fi
  audio="$AUDIO_DIR/$file"
  if [ ! -f "$audio" ]; then echo "MISSING $audio (run bench/tools/fetch.sh)" >&2; fail=1; continue; fi
  start=$(date +%s)
  if ! "$BEAT_THIS" "$audio" -o "$out" >"$TMP/log" 2>&1; then
    # decoder fallback: convert to a temporary 16-bit wav outside the repo and retry
    echo "note  $set_id: direct read failed, retrying via afconvert wav" >&2
    wav="$TMP/$set_id.wav"
    afconvert -f WAVE -d LEI16@44100 "$audio" "$wav"
    "$BEAT_THIS" "$wav" -o "$out" >"$TMP/log" 2>&1 || { tail -5 "$TMP/log" >&2; fail=1; rm -f "$wav"; continue; }
    rm -f "$wav"
  fi
  echo "done  $set_id ($(( $(date +%s) - start )) s, $(wc -l < "$out" | tr -d ' ') beats)"
done < "$SOURCES"
exit $fail
