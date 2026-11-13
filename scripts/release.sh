#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds a release from the current commit into dist/:
#   vChain.dmg                    the app and an Applications link in the BitmapBabe frame, with the first-launch steps
#   vChain-<version>-source.zip   the complete source incl. the Ableton Link and aubio submodules (GPL)
#   appcast.xml                   the Sparkle update feed for this version, signed with the "vchain" EdDSA key in
#                                 the login keychain; the app reads it via bitmapbabe.com/vchain/appcast.xml,
#                                 which redirects to the latest release's copy
# Usage: scripts/release.sh                          build the current version only (nothing changes)
#        scripts/release.sh --publish [patch|minor|major|current]
#            asks for the release type (or takes it), sets CFBundleShortVersionString in Info.plist (patch 0.1.0 →
#            0.1.1, minor → 0.2.0, major → 1.0.0; "current" releases the version as it is, offered while it isn't
#            released yet), raises CFBundleVersion (the counter Sparkle compares) by one, commits "Release x.y.z",
#            builds, pushes and creates the GitHub release v<version> with the files
#            (visitors can only download it while the repo is public)
# The DMG's file name never changes, so https://github.com/nikinoldin/vchain/releases/latest/download/vChain.dmg
# always gets the newest one.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST=/usr/libexec/PlistBuddy
VERSION=$($PLIST -c "Print CFBundleShortVersionString" Info.plist)
PUBLISH=0; [ "${1:-}" = "--publish" ] && PUBLISH=1
LEVEL="${2:-}"
[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes: commit first, a release is built from HEAD." >&2; exit 1; }
MODEL="${VCHAIN_NN_MODEL:-$HOME/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage}"
[ -d "$MODEL" ] || { echo "No Beat This! model at $MODEL (bench/nn/make_model.sh): a release needs it." >&2; exit 1; }

if [ $PUBLISH = 1 ]; then
    [ "$(git branch --show-current)" = main ] || { echo "Release from main." >&2; exit 1; }
    git fetch -q origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main differs from origin/main: pull or push first." >&2; exit 1; }
    released() { git ls-remote --exit-code --tags origin "v$1" >/dev/null 2>&1; }
    IFS=. read -r MAJ MIN PAT <<< "$VERSION"
    PATCH_V="$MAJ.$MIN.$((PAT + 1))"; MINOR_V="$MAJ.$((MIN + 1)).0"; MAJOR_V="$((MAJ + 1)).0.0"
    if [ -z "$LEVEL" ]; then
        echo "Current version: $VERSION$(released "$VERSION" && echo " (released)" || echo " (not released yet)")"
        OPTIONS=("patch → $PATCH_V" "minor → $MINOR_V" "major → $MAJOR_V")
        released "$VERSION" || OPTIONS=("current → $VERSION" "${OPTIONS[@]}")
        PS3="Release type: "
        select choice in "${OPTIONS[@]}"; do [ -n "$choice" ] && { LEVEL="${choice%% *}"; break; }; done
    fi
    case "$LEVEL" in
        current) NEW="$VERSION" ;;
        patch) NEW="$PATCH_V" ;;
        minor) NEW="$MINOR_V" ;;
        major) NEW="$MAJOR_V" ;;
        *) echo "Release type: patch, minor, major or current" >&2; exit 1 ;;
    esac
    released "$NEW" && { echo "v$NEW is already released." >&2; exit 1; }
    if [ "$NEW" != "$VERSION" ]; then
        BUILD=$(( $($PLIST -c "Print CFBundleVersion" Info.plist) + 1 ))
        $PLIST -c "Set CFBundleShortVersionString $NEW" -c "Set CFBundleVersion $BUILD" Info.plist
        git commit -qm "Release $NEW" Info.plist
        echo "Version $NEW (build $BUILD), committed. If the build fails: git reset --hard HEAD~1"
        VERSION="$NEW"
    fi
fi

# Sparkle's tools (generate_appcast) from its release archive, same version as Package.swift.
SPARKLE_TOOLS=.cache/sparkle/bin
if [ ! -x "$SPARKLE_TOOLS/generate_appcast" ]; then
    mkdir -p .cache/sparkle
    curl -sSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz | tar -xJ -C .cache/sparkle
fi

# dmgbuild (writes the window layout without Finder) in a local venv.
VENV=.cache/release-venv
[ -x "$VENV/bin/dmgbuild" ] || { uv venv -q "$VENV" && uv pip install -q --python "$VENV/bin/python" dmgbuild; }

WORK=$(mktemp -d)
cleanup() { git worktree remove --force "$WORK/src" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
git worktree add -q --detach "$WORK/src" HEAD
rm -rf "$WORK/src/lib/link" "$WORK/src/lib/aubio"
cp -R lib/link lib/aubio "$WORK/src/lib/"

echo "== Source zip"
mkdir -p dist
SRC="vChain-$VERSION-source"
rsync -a --exclude .git --exclude .build --exclude build --exclude .cache "$WORK/src/" "$WORK/$SRC/"
rm -f "dist/$SRC.zip"
(cd "$WORK" && ditto -c -k --sequesterRsrc --keepParent "$SRC" "$OLDPWD/dist/$SRC.zip")

echo "== App"
(cd "$WORK/src" && UNIVERSAL=1 ./build.sh)
APP="$WORK/src/build/vChain.app"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/VChain" | grep -q "x86_64 arm64" || { echo "The app isn't universal" >&2; exit 1; }

echo "== DMG"
# The background PNGs come from scripts/dmg/background.py (the frame SVG plus arrow and captions).
tiffutil -cathidpicheck assets/dmg/background.png assets/dmg/background@2x.png -out "$WORK/background.tiff" 2>/dev/null
rm -f dist/vChain.dmg
"$VENV/bin/dmgbuild" -s scripts/dmg/settings.py -D app="$APP" \
    -D background="$WORK/background.tiff" "vChain" dist/vChain.dmg

echo "== Appcast"
mkdir -p "$WORK/updates"
cp dist/vChain.dmg "$WORK/updates/"
rm -f dist/appcast.xml   # one entry, written fresh from this build (an old file would keep stale details)
"$SPARKLE_TOOLS/generate_appcast" --account vchain \
    --download-url-prefix "https://github.com/nikinoldin/vchain/releases/download/v$VERSION/" \
    --link "https://github.com/nikinoldin/vchain" -o dist/appcast.xml "$WORK/updates"
ls -lh dist/

if [ $PUBLISH = 1 ]; then
    echo "== GitHub release v$VERSION"
    NOTES="$WORK/notes.md"
    {
        echo "Download **vChain.dmg**, open it and drag vChain into Applications."
        echo
        echo "vChain isn't registered with Apple, so macOS blocks it the first time: open it once, click Done, then"
        echo "System Settings › Privacy & Security › **Open Anyway**. Needs macOS 15 or later."
        echo
        echo "The source zip includes the Ableton Link and aubio submodules."
    } > "$NOTES"
    git push -q origin main
    gh release create "v$VERSION" dist/vChain.dmg "dist/$SRC.zip" dist/appcast.xml --title "vChain $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
fi
