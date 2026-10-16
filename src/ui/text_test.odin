package ui

import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import fs "vendor:fontstash"

@(test)
text_that_fits_is_kept_whole :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	title := "Paper Satellites"
	length, cut := text_fit(r, title, .Body, 1000)
	testing.expect_value(t, length, len(title))
	testing.expect(t, !cut)
	width := text_width(r, title, .Body) - 1
	length, cut = text_fit(r, title, .Body, width)
	testing.expect(t, cut)
	shown := strings.concatenate({title[:length], ELLIPSIS}, context.temp_allocator)
	testing.expect(t, text_width(r, shown, .Body) <= width, shown)
	length, cut = text_fit(r, title, .Body, 0)
	testing.expect_value(t, length, 0)
	testing.expect(t, cut)
}

@(test)
a_cut_never_splits_a_character :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	text := "Été à Évian"
	for width in 1 ..< 80 {
		length, _ := text_fit(r, text, .Body, f32(width))
		testing.expect(t, utf8.valid_string(text[:length]), text[:length])
	}
}

@(test)
caret_positions_grow_with_the_text :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	text := "Año 2024"
	xs := caret_positions(r, text, .Body)
	defer delete(xs)
	testing.expect_value(t, len(xs), len(text) + 1)
	testing.expect_value(t, xs[0], 0)
	for i in 1 ..< len(xs) do testing.expect(t, xs[i] >= xs[i - 1])
	testing.expect(t, abs(xs[len(text)] - text_width(r, text, .Body)) < 0.5)
}

@(test)
a_label_is_uppercase_and_tracked :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	testing.expect_value(t, text_width(r, "tags", .Label), text_width(r, "TAGS", .Label))
	set_font_state(r, .Label)
	fs.SetSpacing(&r.atlas.fonts, 0)
	untracked := fs.TextBounds(&r.atlas.fonts, "TAGS")
	testing.expect(t, text_width(r, "TAGS", .Label) > untracked)
}

// A style's size is the em: fontstash draws a line that high, so the sizes it is given are
// scaled by each font's line height in ems (Inter's 1984 and 494 units of 2048, JetBrains
// Mono's 1020 and 300 of 1000), and ten digits of the 12 point mono style are ten
// advances of 0.6 em.
@(test)
a_text_styles_size_is_its_em :: proc(t: ^testing.T) {
	r := test_renderer(2)
	defer destroy_test_renderer(r)
	for font in ([]Font{.Inter_Regular, .Inter_Medium, .Inter_Semibold}) {
		testing.expectf(
			t,
			abs(r.atlas.em_scale[font] - 1.21) < 0.01,
			"%v: %v",
			font,
			r.atlas.em_scale[font],
		)
	}
	for font in ([]Font{.Mono_Regular, .Mono_Medium}) {
		testing.expectf(
			t,
			abs(r.atlas.em_scale[font] - 1.32) < 0.01,
			"%v: %v",
			font,
			r.atlas.em_scale[font],
		)
	}
	width := text_width(r, "0000000000", .Numeric)
	testing.expectf(t, abs(width - 72) <= 3, "ten digits are %v points wide", width)
}
