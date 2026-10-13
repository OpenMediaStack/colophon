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
