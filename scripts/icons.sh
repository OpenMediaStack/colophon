#!/usr/bin/env bash
# Rasterizes the Lucide icons of assets/icons/*.svg into the alpha masks the renderer
# embeds: assets/icons/masks/<name>.a8, 64 by 64 bytes of coverage, row by row.
# macOS only (Quick Look renders the SVG), with ImageMagick. Run it after adding an icon
# and commit the masks, so building Colophon needs neither tool.
set -euo pipefail
cd "$(dirname "$0")/.."

size=64
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p assets/icons/masks
for svg in assets/icons/*.svg; do
	name=$(basename "$svg" .svg)
	# Black strokes on Quick Look's white background, drawn at 256 pixels.
	sed -e 's/currentColor/#000000/g' -e 's/width="24"/width="256"/' -e 's/height="24"/height="256"/' \
		"$svg" >"$tmp/$name.svg"
	qlmanage -t -s 256 -o "$tmp" "$tmp/$name.svg" >/dev/null 2>&1
	magick "$tmp/$name.svg.png" -crop 256x256+0+0 +repage -alpha off -colorspace gray -negate \
		-resize "${size}x${size}" -depth 8 "gray:assets/icons/masks/$name.a8"
done
ls assets/icons/masks
