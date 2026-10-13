package ui

import "core:testing"

@(test)
a_square_rect_is_two_triangles_in_pixels :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	fill_rect(r, {10, 20, 30, 40}, {1, 0, 0, 1})
	list := r.lists[.Base]
	testing.expect_value(t, len(list.vertices), 4)
	testing.expect_value(t, len(list.indices), 6)
	testing.expect_value(t, list.vertices[0].position, [2]f32{20, 40})
	testing.expect_value(t, list.vertices[2].position, [2]f32{80, 120})
}

@(test)
edges_snap_to_whole_pixels :: proc(t: ^testing.T) {
	r := test_renderer(1.5)
	defer destroy_test_renderer(r)
	fill_rect(r, {1, 1, 3, 3}, {1, 1, 1, 1})
	v := r.lists[.Base].vertices
	testing.expect_value(t, v[0].position, [2]f32{2, 2})
	testing.expect_value(t, v[2].position, [2]f32{6, 6})
}

@(test)
a_rounded_rect_has_a_feather_ring :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	fill_rect(r, {0, 0, 100, 40}, {1, 1, 1, 1}, radius = 6)
	list := r.lists[.Base]
	testing.expect_value(t, len(list.vertices), 1 + 2 * RING_POINTS)
	transparent := 0
	for v in list.vertices do if v.color.a == 0 do transparent += 1
	testing.expect_value(t, transparent, RING_POINTS)
}

@(test)
a_rounded_stroke_is_transparent_at_both_edges :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	stroke_rect(r, {0, 0, 100, 40}, {1, 1, 1, 0.8}, radius = 6, width = 2)
	v := r.lists[.Base].vertices
	testing.expect_value(t, len(v), 4 * RING_POINTS)
	want := [4]f32{0, 0.8, 0.8, 0}
	for ring_alpha, k in want {
		testing.expectf(
			t,
			v[k * RING_POINTS].color.a == ring_alpha,
			"ring %d has alpha %v",
			k,
			v[k * RING_POINTS].color.a,
		)
	}
}

@(test)
a_gradient_runs_from_the_top_left_to_the_bottom_right :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	c0 := Color{1, 0, 0, 1}
	c1 := Color{0, 0, 1, 1}
	fill_gradient(r, {0, 0, 10, 10}, c0, c1)
	v := r.lists[.Base].vertices
	testing.expect_value(t, v[0].color, c0)
	testing.expect_value(t, v[2].color, c1)
	testing.expect_value(t, v[1].color, Color{0.5, 0, 0.5, 1})
}

@(test)
an_image_gets_its_own_command_and_stays_inside_its_texture :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1})
	draw_image(r, Texture_Id(1), {0, 0, 64, 64}, radius = 8)
	commands := r.lists[.Base].commands
	testing.expect_value(t, len(commands), 2)
	testing.expect_value(t, commands[1].texture, Texture_Id(1))
	for v in r.lists[.Base].vertices[commands[1].first_vertex:] {
		testing.expectf(t, v.uv.x >= 0 && v.uv.x <= 1 && v.uv.y >= 0 && v.uv.y <= 1, "uv %v", v.uv)
	}
}

@(test)
every_index_stays_inside_its_command :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 1}, 4)
	push_clip(r, {0, 0, 50, 50})
	stroke_rect(r, {0, 0, 40, 20}, {1, 1, 1, 1}, 4)
	draw_text(r, "Paper Satellites", 0, 10, .Body, {1, 1, 1, 1})
	pop_clip(r)
	draw_image(r, Texture_Id(1), {0, 0, 32, 32}, 6)
	draw_icon(r, .Play, {0, 0, 16, 16}, {1, 1, 1, 1})
	list := r.lists[.Base]
	total := 0
	for command in list.commands {
		total += command.vertex_count
		for index in list.indices[command.first_index:][:command.index_count] {
			testing.expect(t, index >= 0 && int(index) < command.vertex_count)
		}
	}
	testing.expect_value(t, total, len(list.vertices))
}

@(test)
nothing_is_drawn_for_an_empty_or_transparent_rect :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	fill_rect(r, {0, 0, 0, 10}, {1, 1, 1, 1})
	fill_rect(r, {0, 0, 10, 10}, {1, 1, 1, 0})
	stroke_rect(r, {0, 0, 10, 0}, {1, 1, 1, 1})
	testing.expect_value(t, len(r.lists[.Base].vertices), 0)
}

@(test)
a_clip_starts_a_new_command :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
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
	r := test_renderer()
	defer destroy_test_renderer(r)
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
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	stroke_rect(r, {0, 0, 40, 20}, {1, 1, 1, 1})
	testing.expect_value(t, len(r.lists[.Base].vertices), 16)
}

@(test)
an_icon_turns_by_quarters :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	draw_icon(r, .Chevron_Down, {0, 0, 16, 16}, {1, 1, 1, 1})
	draw_icon(r, .Chevron_Down, {0, 0, 16, 16}, {1, 1, 1, 1}, quarter_turns = 1)
	v := r.lists[.Base].vertices
	testing.expect_value(t, v[4].uv, v[3].uv)
	testing.expect_value(t, v[5].uv, v[0].uv)
}

@(test)
an_icon_is_sampled_at_the_size_it_is_drawn :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	w := f32(r.atlas.fonts.width)
	for pixels, i in ([3]f32{16, 32, 64}) {
		begin_frame(r, 1)
		draw_icon(r, .Play, {0, 0, pixels, pixels}, {1, 1, 1, 1})
		v := r.lists[.Base].vertices
		testing.expectf(
			t,
			(v[1].uv.x - v[0].uv.x) * w == pixels,
			"icon %d sampled %v texels wide",
			i,
			(v[1].uv.x - v[0].uv.x) * w,
		)
	}
}

@(test)
the_atlas_does_not_grow_for_a_frame_of_ordinary_text :: proc(t: ^testing.T) {
	r := test_renderer()
	defer destroy_test_renderer(r)
	for style in Text_Style do draw_text(r, "Neon Overpass, Été 2024 4:08", 0, 0, style, {1, 1, 1, 1})
	testing.expect(t, !atlas_grew(r))
}
