package ui

import "core:testing"

// The masks fill their 24 unit view box, as the SVGs are drawn at any size: panel-left's
// strokes run from 2 to 22 units, so from 5 to 58 of 64 pixels, along both axes (a
// thumbnail that is drawn smaller than its size once gave 5 to 49).
@(test)
an_icon_mask_fills_its_view_box :: proc(t: ^testing.T) {
	mask := ICON_MASKS[.Panel_Left]
	testing.expect_value(t, len(mask), ICON_SIZE * ICON_SIZE)
	left, top, right, bottom := ICON_SIZE, ICON_SIZE, -1, -1
	for value, i in mask {
		if value < 128 do continue
		x, y := i % ICON_SIZE, i / ICON_SIZE
		left, right = min(left, x), max(right, x)
		top, bottom = min(top, y), max(bottom, y)
	}
	testing.expectf(t, left >= 5 && left <= 6, "the ink starts at %d", left)
	testing.expectf(t, top >= 5 && top <= 6, "the ink starts at %d from the top", top)
	testing.expectf(t, right >= 57 && right <= 58, "the ink ends at %d", right)
	testing.expectf(t, bottom >= 57 && bottom <= 58, "the ink ends at %d from the top", bottom)
}

// The right chevron is the down chevron turned a quarter, an icon of its own: SDL's software
// renderer would draw a turned texture flipped (see draw_icon).
@(test)
the_right_chevron_is_the_down_chevron_turned :: proc(t: ^testing.T) {
	down, right := ICON_MASKS[.Chevron_Down], ICON_MASKS[.Chevron_Right]
	testing.expect_value(t, len(right), ICON_SIZE * ICON_SIZE)
	// Turning the down chevron a quarter anticlockwise gives the right one: the pixel at
	// (x, y) of the right mask is the pixel at (ICON_SIZE - 1 - y, x) of the down mask, to
	// within the anti-aliasing of two renderings.
	differing := 0
	for y in 0 ..< ICON_SIZE {
		for x in 0 ..< ICON_SIZE {
			a := int(right[y * ICON_SIZE + x])
			b := int(down[x * ICON_SIZE + (ICON_SIZE - 1 - y)])
			if abs(a - b) > 64 do differing += 1
		}
	}
	testing.expectf(t, differing == 0, "%d pixels differ from the turned down chevron", differing)
}
