package ui

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

// The reference captures of the repository, from this file's folder.
@(private = "file")
REFERENCES :: #directory + "/../../tests/references"

// Channels may differ by this much without counting as a difference, and this share
// of the pixels may differ more: rasterizing is not bit for bit the same everywhere.
@(private = "file")
CHANNEL_TOLERANCE :: 8
@(private = "file")
PIXEL_TOLERANCE :: 0.002

@(test)
the_test_card_matches_its_reference :: proc(t: ^testing.T) {
	ok :=
		sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "dummy") &&
		sdl.SetHint(sdl.HINT_RENDER_DRIVER, "software")
	if !testing.expect(t, ok) do return
	if !testing.expectf(t, sdl.Init({.VIDEO}), "SDL_Init: %s", sdl.GetError()) do return
	defer sdl.Quit()

	size := [2]f32{480, 270}
	scale: f32 = 2
	window := sdl.CreateWindow("test card", c.int(size.x * scale), c.int(size.y * scale), {})
	if !testing.expectf(t, window != nil, "SDL_CreateWindow: %s", sdl.GetError()) do return
	defer sdl.DestroyWindow(window)
	renderer := sdl.CreateRenderer(window, nil)
	if !testing.expectf(t, renderer != nil, "SDL_CreateRenderer: %s", sdl.GetError()) do return
	defer sdl.DestroyRenderer(renderer)

	r := new(Renderer)
	defer free(r)
	renderer_init(r)
	defer renderer_destroy(r)
	backend: Sdl_Backend
	sdl_backend_init(&backend, renderer)
	defer sdl_backend_destroy(&backend)

	begin_frame(r, scale)
	draw_test_card(r, {0, 0, size.x / 2, size.y}, theme(.Dark))
	draw_test_card(r, {size.x / 2, 0, size.x / 2, size.y}, theme(.Light))
	testing.expect(t, sdl.RenderClear(renderer))
	testing.expectf(t, sdl_backend_draw(&backend, r), "drawing: %s", sdl.GetError())
	free_all(context.temp_allocator)

	capture := sdl.RenderReadPixels(renderer, nil)
	if !testing.expectf(t, capture != nil, "SDL_RenderReadPixels: %s", sdl.GetError()) do return
	defer sdl.DestroySurface(capture)
	expect_reference(t, capture, "test-card.png")
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

// Compares capture with the reference of that name, or writes the reference when
// UPDATE_REFERENCES is set or when it does not exist yet (and fails, to be looked at).
@(private = "file")
expect_reference :: proc(t: ^testing.T, capture: ^sdl.Surface, name: string) {
	path := fmt.tprintf("%s/%s", REFERENCES, name)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	defer free_all(context.temp_allocator)
	update := len(os.get_env("UPDATE_REFERENCES", context.temp_allocator)) > 0
	if update || !os.exists(path) {
		os.make_directory_all(REFERENCES)
		testing.expectf(t, sdl.SavePNG(capture, cpath), "SDL_SavePNG: %s", sdl.GetError())
		testing.expectf(
			t,
			update,
			"%s did not exist: it was written, check it and commit it",
			path,
		)
		return
	}
	reference := sdl.LoadPNG(cpath)
	if !testing.expectf(t, reference != nil, "SDL_LoadPNG %s: %s", path, sdl.GetError()) do return
	defer sdl.DestroySurface(reference)
	want := sdl.ConvertSurface(reference, .RGBA32)
	got := sdl.ConvertSurface(capture, .RGBA32)
	defer sdl.DestroySurface(want)
	defer sdl.DestroySurface(got)
	if !testing.expect(t, want != nil && got != nil) do return
	if !testing.expectf(t, want.w == got.w && want.h == got.h, "%s is %dx%d, the capture %dx%d", name, want.w, want.h, got.w, got.h) do return
	differing := 0
	for y in 0 ..< int(got.h) {
		a := ([^]u8)(want.pixels)[y * int(want.pitch):][:got.w * 4]
		b := ([^]u8)(got.pixels)[y * int(got.pitch):][:got.w * 4]
		for i := 0; i < len(a); i += 4 {
			for k in 0 ..< 4 {
				if abs(int(a[i + k]) - int(b[i + k])) > CHANNEL_TOLERANCE {
					differing += 1
					break
				}
			}
		}
	}
	share := f64(differing) / f64(got.w * got.h)
	if share > PIXEL_TOLERANCE {
		failed := fmt.tprintf("%s/%s.failed.png", REFERENCES, name)
		sdl.SavePNG(got, strings.clone_to_cstring(failed, context.temp_allocator))
		testing.expectf(
			t,
			false,
			"%d pixels (%.2f%%) differ from %s: the capture is in %s",
			differing,
			share * 100,
			name,
			failed,
		)
	}
}
