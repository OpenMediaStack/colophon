package ui

import "core:strings"
import "core:testing"
import "core:unicode/utf8"

@(test)
text_that_fits_is_kept_whole :: proc(t: ^testing.T) {
	r := new(Renderer)
	defer free(r)
	renderer_init(r)
	defer renderer_destroy(r)
	begin_frame(r, 2)
	defer free_all(context.temp_allocator)
	title := "Paper Satellites"
	testing.expect_value(t, text_fit(r, title, .Body, 1000), title)
	cut := text_fit(r, title, .Body, text_width(r, title, .Body) - 1)
	testing.expect(t, strings.has_suffix(cut, ELLIPSIS), cut)
	testing.expect(t, text_width(r, cut, .Body) <= text_width(r, title, .Body) - 1, cut)
	testing.expect_value(t, text_fit(r, title, .Body, 0), "")
}

@(test)
a_cut_never_splits_a_character :: proc(t: ^testing.T) {
	r := new(Renderer)
	defer free(r)
	renderer_init(r)
	defer renderer_destroy(r)
	begin_frame(r, 1)
	defer free_all(context.temp_allocator)
	text := "Été à Évian"
	for width in 1 ..< 80 {
		cut := text_fit(r, text, .Body, f32(width))
		testing.expect(t, utf8.valid_string(cut), cut)
	}
}

@(test)
caret_positions_grow_with_the_text :: proc(t: ^testing.T) {
	r := new(Renderer)
	defer free(r)
	renderer_init(r)
	defer renderer_destroy(r)
	begin_frame(r, 2)
	defer free_all(context.temp_allocator)
	xs := caret_positions(r, "Año 2024", .Body)
	testing.expect_value(t, len(xs), len("Año 2024") + 1)
	testing.expect_value(t, xs[0], 0)
	for i in 1 ..< len(xs) do testing.expect(t, xs[i] >= xs[i - 1])
}

@(test)
a_label_is_uppercase_and_tracked :: proc(t: ^testing.T) {
	r := new(Renderer)
	defer free(r)
	renderer_init(r)
	defer renderer_destroy(r)
	begin_frame(r, 1)
	defer free_all(context.temp_allocator)
	testing.expect(t, text_width(r, "tags", .Label) > text_width(r, "TAGS", .Body_Strong) * 0.8)
	testing.expect_value(t, text_width(r, "tags", .Label), text_width(r, "TAGS", .Label))
}
