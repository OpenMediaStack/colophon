#!/bin/bash
# Builds Colophon in release on this Mac and stages what a bundle needs from it in a folder:
# the binary, pointing at the SDL3 library beside the app's Frameworks folder, and that
# library: packaging/macos/stage-binary.sh <folder>. It builds for the architecture it runs
# on: the release builds it on an Apple silicon runner and on an Intel one, and
# build-dmg.sh joins the two.

set -euo pipefail
cd "$(dirname "$0")/../.."

out=${1:?usage: stage-binary.sh <folder>}
./scripts/build.sh release
rm -rf "$out"
mkdir -p "$out"
cp build/colophon "$out/colophon"
# The SDL3 library the binary loads, wherever Homebrew or SDL3_LIB_DIR put it.
loaded=$(otool -L "$out/colophon" | sed -n 's/^[[:space:]]*\(.*libSDL3[^ ]*\) (.*/\1/p' | head -n 1)
if [[ -z $loaded ]]; then
	echo "colophon does not load SDL3 dynamically" >&2
	exit 1
fi
cp -L "$loaded" "$out/libSDL3.0.dylib"
chmod u+w "$out/libSDL3.0.dylib"
install_name_tool -id @rpath/libSDL3.0.dylib "$out/libSDL3.0.dylib"
install_name_tool -change "$loaded" @executable_path/../Frameworks/libSDL3.0.dylib "$out/colophon"
