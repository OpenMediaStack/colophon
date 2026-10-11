#!/bin/bash
# Builds Colophon for Linux and packs it as an AppImage with linuxdeploy, which brings the
# libraries a distribution may lack: target/appimage/Colophon-<version>-x86_64.AppImage.
# Run from anywhere: ./packaging/linux/build-appimage.sh
#
# An AppImage runs where the glibc is at least as recent as the one it was built against, so the
# release builds it on the oldest Ubuntu GitHub offers.

set -euo pipefail
cd "$(dirname "$0")/../.."

version=$(sed -n 's/^version = "\(.*\)"$/\1/p' Cargo.toml | head -n 1)
linuxdeploy_release=1-alpha-20251107-1

cargo build --release --locked -p colophon

out=target/appimage
rm -rf "$out"
mkdir -p "$out"
linuxdeploy=target/tools/linuxdeploy-$linuxdeploy_release-x86_64.AppImage
if [[ ! -x $linuxdeploy ]]; then
	mkdir -p target/tools
	curl -fsSL -o "$linuxdeploy" \
		"https://github.com/linuxdeploy/linuxdeploy/releases/download/$linuxdeploy_release/linuxdeploy-x86_64.AppImage"
	chmod +x "$linuxdeploy"
fi
# linuxdeploy names the icon after the desktop file's Icon key.
cp assets/icon/png/colophon-256.png "$out/colophon.png"

# Extracting rather than mounting spares the need for FUSE, which containers and CI lack.
(
	cd "$out"
	APPIMAGE_EXTRACT_AND_RUN=1 LINUXDEPLOY_OUTPUT_VERSION="$version" "../../$linuxdeploy" \
		--appdir AppDir \
		--executable ../release/Colophon \
		--desktop-file ../../packaging/linux/colophon.desktop \
		--icon-file colophon.png \
		--output appimage
)
