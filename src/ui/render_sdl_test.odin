package ui

import "core:testing"

@(test)
the_test_card_matches_its_reference :: proc(t: ^testing.T) {
	size := [2]f32{480, 270}
	c, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&c)
	r := c.renderer
	draw_test_card(r, {0, 0, size.x / 2, size.y}, theme(.Dark))
	draw_test_card(r, {size.x / 2, 0, size.x / 2, size.y}, theme(.Light))
	finish_capture(t, &c, "test-card.png")
}

// Every shape, every text style and every icon, on the theme's surfaces.
@(private = "file")
draw_test_card :: proc(r: ^Renderer, area: Rect, th: Theme) {
	area := area
	fill_rect(r, area, th.surface_1)
	toolbar := cut_top(&area, 40)
	fill_rect(r, toolbar, th.surface_2)
	fill_rect(r, {toolbar.x, toolbar.y + toolbar.h - 1, toolbar.w, 1}, th.border_subtle)
	row := rect_inset(toolbar, 8, 6)
	draw_icon_centered(r, .Folder, cut_left(&row, 28), th.text_secondary)
	cut_left(&row, 6)
	primary := cut_left(&row, 104)
	fill_rect(r, primary, th.accent, 4)
	draw_icon(r, .Save, {primary.x + 10, primary.y + 6, 16, 16}, th.on_accent)
	draw_text(
		r,
		"Save 3 files",
		primary.x + 32,
		primary.y + primary.h / 2,
		.Body_Strong,
		th.on_accent,
	)
	cut_left(&row, 8)
	secondary := cut_left(&row, 64)
	fill_rect(r, secondary, th.surface_2, 4)
	stroke_rect(r, secondary, th.border_strong, 4)
	draw_text(
		r,
		"Revert",
		secondary.x + secondary.w / 2,
		secondary.y + secondary.h / 2,
		.Body_Strong,
		th.text_primary,
		.Center,
	)

	body := rect_inset(area, 12, 10)
	draw_text(r, "Tags", body.x, body.y + 6, .Label, th.text_tertiary)
	y := body.y + 22
	styles := [?]Text_Style{.Title, .Body, .Body_Strong, .Small, .Numeric, .Numeric_Strong}
	samples := [?]string {
		"3 tracks selected",
		"Neon Overpass, Été",
		"Cassette Bloom",
		"248 tracks",
		"4:08  320  VBR 245",
		"2.4",
	}
	for style, i in styles {
		color := i == 0 ? th.text_primary : th.text_secondary
		draw_text_fit(r, samples[i], body.x, y + 9, body.w - 132, style, color)
		y += 20
	}

	right := body.x + body.w - 120
	fill_gradient(r, {right, body.y, 40, 40}, hex(0xF59E0B), hex(0xDB2777), 8)
	fill_rect(r, {right + 52, body.y + 2, 36, 36}, th.accent, 18)
	draw_icon_centered(r, .Pause, {right + 52, body.y + 2, 36, 36}, th.on_accent)
	field := Rect{right, body.y + 52, 120, 28}
	fill_rect(r, field, th.surface_2, 4)
	stroke_rect(r, field, th.focus_ring, 4, 2)
	push_clip(r, rect_inset(field, 8, 0))
	draw_text(
		r,
		"Remastered from the original tapes",
		field.x + 8,
		field.y + 14,
		.Body,
		th.text_primary,
	)
	pop_clip(r)
	draw_text_fit(r, "Midnight Lithography", right, body.y + 98, 120, .Body, th.text_primary)

	icons := Rect{body.x, body.y + body.h - 40, body.w, 16}
	for icon in Icon {
		if int(icon) == len(Icon) / 2 do icons = {body.x, body.y + body.h - 18, body.w, 16}
		draw_icon(r, icon, cut_left(&icons, 16), th.text_secondary)
		cut_left(&icons, 6)
	}
}
