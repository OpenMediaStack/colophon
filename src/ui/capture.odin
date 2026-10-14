package ui

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

// The reference captures of the repository, and where a capture that differs is
// written, from this file's folder.
REFERENCES :: #directory + "/../../tests/references"
FAILED_CAPTURES :: #directory + "/../../build/captures"

// A channel may differ by this much without counting, and this many pixels may
// differ more: rasterizing is not bit for bit the same on every system.
CHANNEL_TOLERANCE :: 8
DIFFERING_PIXELS_ALLOWED :: 64

// A frame drawn without a window, for the reference captures: what a Renderer holds
// goes to a surface through SDL's software renderer, which needs no SDL_Init, window
// or hint, so captures may be taken on any thread, side by side. Make it with
// capture_init, free it with capture_destroy.
Capture :: struct {
	surface: ^sdl.Surface,
	sdl:     ^sdl.Renderer,
	backend: Sdl_Backend,
}

// Starts a capture of size points at scale pixels per point. ok is false when SDL
// fails: sdl.GetError says why.
capture_init :: proc(cap: ^Capture, size: [2]f32, scale: f32) -> (ok: bool) {
	cap.surface = sdl.CreateSurface(c.int(size.x * scale), c.int(size.y * scale), .RGBA32)
	if cap.surface == nil do return false
	cap.sdl = sdl.CreateSoftwareRenderer(cap.surface)
	if cap.sdl == nil {
		sdl.DestroySurface(cap.surface)
		cap.surface = nil
		return false
	}
	sdl_backend_init(&cap.backend, cap.sdl)
	return true
}

// Makes the capture's textures of the images a harness kept, with the ids the Ui
// drew them by: a forgotten image leaves a clear texel in its place.
capture_textures :: proc(cap: ^Capture, h: ^Harness) -> bool {
	clear := [4]u8{0, 0, 0, 0}
	for image in h.images {
		rgba, w, hh := image.rgba, image.w, image.h
		if rgba == nil do rgba, w, hh = clear[:], 1, 1
		sdl_backend_create_texture(&cap.backend, rgba, w, hh) or_return
	}
	return true
}

// Draws what r holds into the capture's surface, over black.
capture_draw :: proc(cap: ^Capture, r: ^Renderer) -> bool {
	sdl.RenderClear(cap.sdl) or_return
	sdl_backend_draw(&cap.backend, r) or_return
	return sdl.RenderPresent(cap.sdl)
}

capture_destroy :: proc(cap: ^Capture) {
	sdl_backend_destroy(&cap.backend)
	if cap.sdl != nil do sdl.DestroyRenderer(cap.sdl)
	if cap.surface != nil do sdl.DestroySurface(cap.surface)
	cap^ = {}
}

// What comparing a capture with its reference found.
Reference_Result :: enum u8 {
	Matches,
	// The reference was written: it did not exist, or update asked for it. A test
	// fails on a reference written without asking, so that it is looked at.
	Written,
	Differs,
}

// Compares capture with the reference of that name in REFERENCES, within the
// tolerances, or writes the reference when update is set or when it does not exist
// yet. A capture that differs is written to FAILED_CAPTURES. message says what
// happened, allocated with the temporary allocator.
check_reference :: proc(
	capture: ^sdl.Surface,
	name: string,
	update: bool,
) -> (
	result: Reference_Result,
	message: string,
) {
	path := fmt.tprintf("%s/%s", REFERENCES, name)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if update || !os.exists(path) {
		if !sdl.SavePNG(capture, cpath) {
			return .Differs, fmt.tprintf("SDL_SavePNG %s: %s", path, sdl.GetError())
		}
		return .Written, fmt.tprintf(
			"%s did not exist: it was written, check it and commit it",
			path,
		)
	}
	reference := sdl.LoadPNG(cpath)
	if reference == nil do return .Differs, fmt.tprintf("SDL_LoadPNG %s: %s", path, sdl.GetError())
	defer sdl.DestroySurface(reference)
	want := sdl.ConvertSurface(reference, .RGBA32)
	got := sdl.ConvertSurface(capture, .RGBA32)
	defer sdl.DestroySurface(want)
	defer sdl.DestroySurface(got)
	if want == nil || got == nil do return .Differs, fmt.tprintf("SDL_ConvertSurface: %s", sdl.GetError())
	if want.w != got.w || want.h != got.h {
		return .Differs, fmt.tprintf(
			"%s is %dx%d, the capture %dx%d",
			name,
			want.w,
			want.h,
			got.w,
			got.h,
		)
	}
	differing := count_differing_pixels(want, got)
	if differing <= DIFFERING_PIXELS_ALLOWED do return .Matches, ""
	_ = os.make_directory_all(FAILED_CAPTURES)
	failed := fmt.tprintf("%s/%s", FAILED_CAPTURES, name)
	sdl.SavePNG(got, strings.clone_to_cstring(failed, context.temp_allocator))
	return .Differs, fmt.tprintf(
		"%d pixels differ from %s: the capture is in %s",
		differing,
		name,
		failed,
	)
}

// Whether the UPDATE_REFERENCES variable asks for the references to be written again.
update_references_asked :: proc() -> bool {
	return len(os.get_env("UPDATE_REFERENCES", context.temp_allocator)) > 0
}

// How many pixels of two RGBA32 surfaces of the same size differ by more than the
// tolerance in a channel.
@(private = "file")
count_differing_pixels :: proc(want, got: ^sdl.Surface) -> (differing: int) {
	a := ([^]u8)(want.pixels)
	b := ([^]u8)(got.pixels)
	for y in 0 ..< int(want.h) {
		row_a := a[y * int(want.pitch):]
		row_b := b[y * int(got.pitch):]
		for x in 0 ..< int(want.w) {
			for channel in 0 ..< 4 {
				i := x * 4 + channel
				if abs(int(row_a[i]) - int(row_b[i])) > CHANNEL_TOLERANCE {
					differing += 1
					break
				}
			}
		}
	}
	return
}
