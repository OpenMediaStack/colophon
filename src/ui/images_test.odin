package ui

import "core:testing"

// A 2 by 2 PNG, red on the left and blue on the right, as stb_image reads it.
@(private = "file")
TINY_PNG :: #load("../../testdata/tiny.png")

@(test)
damaged_images_are_refused_without_a_panic :: proc(t: ^testing.T) {
	_, _, _, ok := decode_image(nil)
	testing.expect(t, !ok)
	_, _, _, ok = decode_image(transmute([]u8)string("not an image at all"))
	testing.expect(t, !ok)
	png: []u8 = TINY_PNG
	_, _, _, ok = decode_image(png[:len(png) / 2])
	testing.expect(t, !ok)
	// A header that claims 100000 pixels a side: refused before any decoding.
	huge := make([]u8, len(TINY_PNG))
	defer delete(huge)
	copy(huge, TINY_PNG)
	huge[16], huge[17], huge[18], huge[19] = 0, 1, 0x86, 0xA0
	huge[20], huge[21], huge[22], huge[23] = 0, 1, 0x86, 0xA0
	_, _, _, ok = decode_image(huge)
	testing.expect(t, !ok)
}

@(test)
an_image_decodes_and_shrinks_to_a_square :: proc(t: ^testing.T) {
	rgba, w, h, ok := decode_image(TINY_PNG)
	defer delete(rgba)
	testing.expect(t, ok && w == 2 && h == 2)
	if !ok do return
	testing.expect(t, rgba[0] == 255 && rgba[1] == 0 && rgba[2] == 0)
	small, shrunk := shrink_image(rgba, w, h, 1)
	defer delete(small)
	testing.expect(t, shrunk && len(small) == 4)
	// The mean of red and blue over the square: half of each.
	testing.expect(t, shrunk && small[0] == 127 && small[2] == 127 && small[3] == 255)
	_, bad := shrink_image(rgba, 2, 3, 1)
	testing.expect(t, !bad)
}
