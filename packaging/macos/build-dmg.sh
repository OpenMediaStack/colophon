#!/bin/bash
# Bundles Colophon as Colophon.app and puts it in a disk image beside a link to
# Applications: build/dmg/Colophon-<version>.dmg. Give it the folders stage-binary.sh made,
# one for each architecture: two (Apple silicon and Intel) make one universal app with lipo;
# one makes an app for that architecture alone.
#
#   packaging/macos/build-dmg.sh <folder> [<folder>]
#
# Without a Developer ID, the app is signed ad hoc: Apple silicon runs nothing unsigned, and
# macOS asks once before opening it.

set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ $# -lt 1 || $# -gt 2 ]]; then
	echo "usage: build-dmg.sh <folder> [<folder>]" >&2
	exit 2
fi
version=$(sed -n 's/^VERSION :: "\(.*\)"$/\1/p' src/app/window.odin | head -n 1)
out=build/dmg
app="$out/image/Colophon.app"
rm -rf "$out"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
if [[ $# -eq 2 ]]; then
	lipo -create -output "$app/Contents/MacOS/Colophon" "$1/colophon" "$2/colophon"
	lipo -create -output "$app/Contents/Frameworks/libSDL3.0.dylib" "$1/libSDL3.0.dylib" "$2/libSDL3.0.dylib"
else
	cp "$1/colophon" "$app/Contents/MacOS/Colophon"
	cp "$1/libSDL3.0.dylib" "$app/Contents/Frameworks/libSDL3.0.dylib"
fi
cp assets/icon/Colophon.icns "$app/Contents/Resources/"
sed "s/@VERSION@/$version/g" packaging/macos/Info.plist >"$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
ln -s /Applications "$out/image/Applications"

hdiutil create -volname Colophon -srcfolder "$out/image" -fs HFS+ -format UDZO -ov \
	"$out/Colophon-$version.dmg"
echo "$out/Colophon-$version.dmg"
