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

# Quick Look draws a thumbnail smaller than its size and from the top left corner (about
# 85 per cent of it), so where the 24 by 24 view box lands is measured on a black square
# of that size, and each icon is cut out of it.
cat >"$tmp/square.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 24 24"><rect width="24" height="24" fill="#000000"/></svg>
SVG
qlmanage -t -s 256 -o "$tmp" "$tmp/square.svg" >/dev/null 2>&1
view_box=$(magick "$tmp/square.svg.png" -alpha off -colorspace gray -negate -threshold 50% -format '%@' info:)
for svg in assets/icons/*.svg; do
	name=$(basename "$svg" .svg)
	# Black strokes on Quick Look's white background, drawn at 256 pixels.
	sed -e 's/currentColor/#000000/g' -e 's/width="24"/width="256"/' -e 's/height="24"/height="256"/' \
		"$svg" >"$tmp/$name.svg"
	qlmanage -t -s 256 -o "$tmp" "$tmp/$name.svg" >/dev/null 2>&1
	magick "$tmp/$name.svg.png" -crop "$view_box" +repage -alpha off -colorspace gray -negate \
		-resize "${size}x${size}" -depth 8 "gray:assets/icons/masks/$name.a8"
done
ls assets/icons/masks
