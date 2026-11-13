#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Downloads every audio file listed in bench/sources.tsv that is missing from the bench audio folder
# (${VCHAIN_BENCH_AUDIO:-~/Music/vChainBench/audio}) and verifies its sha256. Fails loudly on a mismatch.
# The audio is CC-licensed for private use only: never copy it into the repo or share it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCES="$ROOT/bench/sources.tsv"
AUDIO_DIR="${VCHAIN_BENCH_AUDIO:-$HOME/Music/vChainBench/audio}"
mkdir -p "$AUDIO_DIR"

# Column 10 (download_url) is the direct file URL; column 4 (source_url) is the item's page.
bad=0
while IFS=$'\t' read -r set_id kind genre source_url licence_url attribution sha256 file duration_s download_url _rest; do
  [ "$set_id" = "set_id" ] && continue
  [ -z "$set_id" ] && continue
  dest="$AUDIO_DIR/$file"
  if [ ! -s "$dest" ]; then
    [ -n "${download_url:-}" ] || { echo "ERROR $set_id: no download_url" >&2; bad=1; continue; }
    echo "get   $set_id"
    curl -gfL --retry 3 --progress-bar -o "$dest.part" "$download_url"
    mv "$dest.part" "$dest"
  fi
  got="$(shasum -a 256 "$dest" | cut -d' ' -f1)"
  if [ "$got" != "$sha256" ]; then
    echo "ERROR sha256 mismatch for $set_id ($dest): expected $sha256, got $got" >&2
    bad=1
  else
    echo "ok    $set_id"
  fi
done < "$SOURCES"

if [ "$bad" != 0 ]; then echo "fetch: FAILED (see errors above)" >&2; exit 1; fi
echo "fetch: all files present and verified in $AUDIO_DIR"
