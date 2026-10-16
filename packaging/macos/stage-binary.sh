#!/bin/bash
# Builds Colophon in release on this Mac and stages what a bundle needs from it in a folder:
# the binary, pointing at the SDL3 library beside the app's Frameworks folder, and that
# library: packaging/macos/stage-binary.sh <folder>. It builds for the architecture it runs
# on: the release builds it on an Apple silicon runner and on an Intel one, and
# build-dmg.sh joins the two. SDL3 is found as the build finds it (SDL3_LIB_DIR).

set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/common.sh

# The oldest macOS Info.plist says the app runs on.
OLDEST_MACOS=11

# Fails unless the file runs from macOS $OLDEST_MACOS on and loads nothing outside the
# system and the bundle.
check_file() {
	local file=$1 minos
	minos=$(otool -l "$file" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { print $2; exit }')
	if [[ -z $minos || ${minos%%.*} -gt $OLDEST_MACOS ]]; then
		echo "$file asks for macOS ${minos:-?}, newer than $OLDEST_MACOS" >&2
		exit 1
	fi
	if otool -L "$file" | tail -n +2 | awk '{ print $1 }' |
		grep -v -E '^(/System/|/usr/lib/|@executable_path/|@rpath/libSDL3)'; then
		echo "$file loads libraries from outside the system and the bundle" >&2
		exit 1
	fi
}

out=${1:?usage: stage-binary.sh <folder>}
./scripts/build.sh release
rm -rf "$out"
mkdir -p "$out"
cp build/colophon "$out/colophon"
# The SDL3 library the binary loads, found by name in SDL3's folder.
loaded=$(otool -L "$out/colophon" | sed -n 's/^[[:space:]]*\(.*libSDL3[^ ]*\) (.*/\1/p' | head -n 1)
if [[ -z $loaded ]]; then
	echo "colophon does not load SDL3 dynamically" >&2
	exit 1
fi
if [[ $loaded == /* ]]; then
	library=$loaded
else
	library="$(sdl3_lib_dir)/$(basename "$loaded")"
fi
cp -L "$library" "$out/libSDL3.0.dylib"
chmod u+w "$out/libSDL3.0.dylib"
install_name_tool -id @rpath/libSDL3.0.dylib "$out/libSDL3.0.dylib"
install_name_tool -change "$loaded" @executable_path/../Frameworks/libSDL3.0.dylib "$out/colophon"
check_file "$out/colophon"
check_file "$out/libSDL3.0.dylib"
