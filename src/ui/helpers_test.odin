package ui

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

// A capture in progress, with the renderer the test draws into.
@(private)
Test_Capture :: struct {
	using capture: Capture,
	renderer:      ^Renderer,
}

// Starts a capture of size points at scale pixels per point. Free it with end_capture.
@(private)
begin_capture :: proc(t: ^testing.T, size: [2]f32, scale: f32) -> (cap: Test_Capture, ok: bool) {
	if !testing.expectf(t, capture_init(&cap.capture, size, scale), "capture: %s", sdl.GetError()) do return
	cap.renderer = test_renderer(scale)
	return cap, true
}

// Draws what the renderer holds and compares it with the reference name.
@(private)
finish_capture :: proc(t: ^testing.T, cap: ^Test_Capture, name: string) {
	testing.expect(t, !atlas_grew(cap.renderer))
	testing.expectf(t, capture_draw(&cap.capture, cap.renderer), "drawing: %s", sdl.GetError())
	expect_reference(t, cap.surface, name)
}

@(private)
end_capture :: proc(cap: ^Test_Capture) {
	destroy_test_renderer(cap.renderer)
	capture_destroy(&cap.capture)
}

// Compares capture with the reference of that name, or writes the reference when
// UPDATE_REFERENCES is set or when it does not exist yet (and fails, to be looked
// at). A capture that differs is written to build/captures.
@(private)
expect_reference :: proc(t: ^testing.T, capture: ^sdl.Surface, name: string) {
	update := update_references_asked()
	result, message := check_reference(capture, name, update)
	testing.expectf(t, result == .Matches || (update && result == .Written), "%s", message)
}
