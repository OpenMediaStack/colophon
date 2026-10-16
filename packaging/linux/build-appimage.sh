#!/bin/bash
# Builds Colophon for Linux and packs it as an AppImage with linuxdeploy, which brings the
# libraries a distribution may lack, SDL3 among them: build/appimage/Colophon-<version>-x86_64.AppImage.
# Run from anywhere: ./packaging/linux/build-appimage.sh
#
# SDL3 is found as the build finds it, through SDL3_LIB_DIR and LD_LIBRARY_PATH. An AppImage
# runs where the glibc is at least as recent as the one it was built against, so the release
# builds it on the oldest Ubuntu GitHub offers.

set -euo pipefail
cd "$(dirname "$0")/../.."

version=$(sed -n 's/^VERSION :: "\(.*\)"$/\1/p' src/app/window.odin | head -n 1)
linuxdeploy_release=1-alpha-20251107-1

./scripts/build.sh release

out=build/appimage
rm -rf "$out"
mkdir -p "$out"
linuxdeploy=build/tools/linuxdeploy-$linuxdeploy_release-x86_64.AppImage
if [[ ! -x $linuxdeploy ]]; then
	mkdir -p build/tools
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
		--executable ../colophon \
		--desktop-file ../../packaging/linux/colophon.desktop \
		--icon-file colophon.png \
		--output appimage
)
