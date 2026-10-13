package ui

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
