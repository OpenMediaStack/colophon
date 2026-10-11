#!/bin/bash
# Builds Colophon for Apple silicon and Intel, bundles both in one Colophon.app, and puts it in
# a disk image beside a link to Applications: target/dmg/Colophon-<version>.dmg.
# Run from anywhere: ./packaging/macos/build-dmg.sh
#
# Without a Developer ID, the app is signed ad hoc: Apple silicon runs nothing unsigned, and
# macOS asks once before opening it.

set -euo pipefail
cd "$(dirname "$0")/../.."

version=$(sed -n 's/^version = "\(.*\)"$/\1/p' Cargo.toml | head -n 1)
targets=(aarch64-apple-darwin x86_64-apple-darwin)
export MACOSX_DEPLOYMENT_TARGET=11.0

rustup target add "${targets[@]}"
for target in "${targets[@]}"; do
	cargo build --release --locked -p colophon --target "$target"
done

out=target/dmg
app="$out/image/Colophon.app"
rm -rf "$out"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create -output "$app/Contents/MacOS/Colophon" \
	target/aarch64-apple-darwin/release/Colophon target/x86_64-apple-darwin/release/Colophon
cp assets/icon/Colophon.icns "$app/Contents/Resources/"
sed "s/@VERSION@/$version/g" packaging/macos/Info.plist >"$app/Contents/Info.plist"
codesign --force --sign - "$app"
ln -s /Applications "$out/image/Applications"

hdiutil create -volname Colophon -srcfolder "$out/image" -fs HFS+ -format UDZO -ov \
	"$out/Colophon-$version.dmg"
