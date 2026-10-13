package ui

import "core:testing"

@(private = "file")
with_renderer :: proc(t: ^testing.T, scale: f32 = 2) -> ^Renderer {
	r := new(Renderer)
	renderer_init(r)
	begin_frame(r, scale)
	return r
}

@(private = "file")
free_renderer :: proc(r: ^Renderer) {
	renderer_destroy(r)
	free(r)
}

@(test)
a_square_rect_is_two_triangles_in_pixels :: proc(t: ^testing.T) {
	r := with_renderer(t)
	defer free_renderer(r)
	fill_rect(r, {10, 20, 30, 40}, {1, 0, 0, 1})
	list := r.lists[.Base]
	testing.expect_value(t, len(list.vertices), 4)
	testing.expect_value(t, len(list.indices), 6)
	testing.expect_value(t, list.vertices[0].position, [2]f32{20, 40})
	testing.expect_value(t, list.vertices[2].position, [2]f32{80, 120})
}

@(test)
a_rounded_rect_has_a_feather_ring :: proc(t: ^testing.T) {
	r := with_renderer(t)
	defer free_renderer(r)
	fill_rect(r, {0, 0, 100, 40}, {1, 1, 1, 1}, radius = 6)
	list := r.lists[.Base]
	testing.expect_value(t, len(list.vertices), 1 + 2 * RING_POINTS)
	transparent := 0
	for v in list.vertices do if v.color.a == 0 do transparent += 1
	testing.expect_value(t, transparent, RING_POINTS)
}

@(test)
nothing_is_drawn_for_an_empty_or_transparent_rect :: proc(t: ^testing.T) {
	r := with_renderer(t)
	defer free_renderer(r)
	fill_rect(r, {0, 0, 0, 10}, {1, 1, 1, 1})
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 0})
	stroke_rect(r, {0, 0, 10, 0}, {1, 1, 1, 1})
	testing.expect_value(t, len(r.lists[.Base].vertices), 0)
}

@(test)
a_clip_starts_a_new_command :: proc(t: ^testing.T) {
	r := with_renderer(t, 1)
	defer free_renderer(r)
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1})
	push_clip(r, {5, 5, 100, 100})
	push_clip(r, {0, 0, 20, 20})
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1})
	pop_clip(r)
	pop_clip(r)
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1})
	commands := r.lists[.Base].commands
	testing.expect_value(t, len(commands), 3)
	testing.expect_value(t, commands[0].clip, nil)
	testing.expect_value(t, commands[1].clip, Pixel_Rect{5, 5, 15, 15})
	testing.expect_value(t, commands[2].clip, nil)
	testing.expect_value(t, commands[2].first_vertex, 8)
}

@(test)
layers_keep_their_own_lists :: proc(t: ^testing.T) {
	r := with_renderer(t)
	defer free_renderer(r)
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1})
	previous := set_layer(r, .Overlay)
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1})
	set_layer(r, previous)
	testing.expect_value(t, previous, Layer.Base)
	testing.expect_value(t, len(r.lists[.Base].vertices), 4)
	testing.expect_value(t, len(r.lists[.Overlay].vertices), 4)
	begin_frame(r, 1)
	testing.expect_value(t, len(r.lists[.Overlay].vertices), 0)
}

@(test)
a_square_stroke_is_four_rects :: proc(t: ^testing.T) {
	r := with_renderer(t, 1)
	defer free_renderer(r)
	stroke_rect(r, {0, 0, 40, 20}, {1, 1, 1, 1})
	testing.expect_value(t, len(r.lists[.Base].vertices), 16)
}

@(test)
an_icon_turns_by_quarters :: proc(t: ^testing.T) {
	r := with_renderer(t, 1)
	defer free_renderer(r)
	draw_icon(r, .Chevron_Down, {0, 0, 16, 16}, {1, 1, 1, 1})
	draw_icon(r, .Chevron_Down, {0, 0, 16, 16}, {1, 1, 1, 1}, quarter_turns = 1)
	v := r.lists[.Base].vertices
	testing.expect_value(t, v[4].uv, v[3].uv)
	testing.expect_value(t, v[5].uv, v[0].uv)
}
