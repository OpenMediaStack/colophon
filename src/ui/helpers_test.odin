package ui

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

// A renderer for a test, drawing at scale. Free it with destroy_test_renderer.
@(private)
test_renderer :: proc(scale: f32 = 2) -> ^Renderer {
	r := new(Renderer)
	renderer_init(r)
	begin_frame(r, scale)
	return r
}

@(private)
destroy_test_renderer :: proc(r: ^Renderer) {
	renderer_destroy(r)
	free(r)
	free_all(context.temp_allocator)
}

// The reference captures of the repository, and where a capture that differs is
// written, from this file's folder.
@(private)
REFERENCES :: #directory + "/../../tests/references"
@(private)
FAILED_CAPTURES :: #directory + "/../../build/captures"

// A channel may differ by this much without counting, and this many pixels may
// differ more: rasterizing is not bit for bit the same on every system.
@(private)
CHANNEL_TOLERANCE :: 8
@(private)
DIFFERING_PIXELS_ALLOWED :: 64

// A capture in progress: what the renderer draws goes to a surface through SDL's
// software renderer, which needs no SDL_Init, window or hint, so capture tests may
// run on any thread, side by side.
@(private)
Capture :: struct {
	surface:  ^sdl.Surface,
	sdl:      ^sdl.Renderer,
	backend:  Sdl_Backend,
	renderer: ^Renderer,
}

// Starts a capture of size points at scale pixels per point. Free it with end_capture.
@(private)
begin_capture :: proc(t: ^testing.T, size: [2]f32, scale: f32) -> (cap: Capture, ok: bool) {
	cap.surface = sdl.CreateSurface(c.int(size.x * scale), c.int(size.y * scale), .RGBA32)
	if !testing.expectf(t, cap.surface != nil, "SDL_CreateSurface: %s", sdl.GetError()) do return
	cap.sdl = sdl.CreateSoftwareRenderer(cap.surface)
	if !testing.expectf(t, cap.sdl != nil, "SDL_CreateSoftwareRenderer: %s", sdl.GetError()) {
		sdl.DestroySurface(cap.surface)
		return
	}
	cap.renderer = test_renderer(scale)
	sdl_backend_init(&cap.backend, cap.sdl)
	return cap, true
}

// Draws what the renderer holds and compares it with the reference name.
@(private)
finish_capture :: proc(t: ^testing.T, cap: ^Capture, name: string) {
	testing.expect(t, !atlas_grew(cap.renderer))
	testing.expect(t, sdl.RenderClear(cap.sdl))
	testing.expectf(t, sdl_backend_draw(&cap.backend, cap.renderer), "drawing: %s", sdl.GetError())
	testing.expect(t, sdl.RenderPresent(cap.sdl))
	expect_reference(t, cap.surface, name)
}

@(private)
end_capture :: proc(cap: ^Capture) {
	sdl_backend_destroy(&cap.backend)
	destroy_test_renderer(cap.renderer)
	sdl.DestroyRenderer(cap.sdl)
	sdl.DestroySurface(cap.surface)
}

// Compares capture with the reference of that name, or writes the reference when
// UPDATE_REFERENCES is set or when it does not exist yet (and fails, to be looked
// at). A capture that differs is written to build/captures.
@(private)
expect_reference :: proc(t: ^testing.T, capture: ^sdl.Surface, name: string) {
	path := fmt.tprintf("%s/%s", REFERENCES, name)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	update := len(os.get_env("UPDATE_REFERENCES", context.temp_allocator)) > 0
	if update || !os.exists(path) {
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
	differing := count_differing_pixels(want, got)
	if differing > DIFFERING_PIXELS_ALLOWED {
		_ = os.make_directory_all(FAILED_CAPTURES)
		failed := fmt.tprintf("%s/%s", FAILED_CAPTURES, name)
		sdl.SavePNG(got, strings.clone_to_cstring(failed, context.temp_allocator))
		testing.expectf(
			t,
			false,
			"%d pixels differ from %s: the capture is in %s",
			differing,
			name,
			failed,
		)
	}
}

@(private)
count_differing_pixels :: proc(want, got: ^sdl.Surface) -> (differing: int) {
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
	return
}
