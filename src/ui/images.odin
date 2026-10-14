package ui

import "core:c"
import "core:slice"
import stbi "vendor:stb/image"

// How a Ui makes textures of decoded images, for draw_image: the window's backend, or
// a test's store of images. Nothing is made while create is nil.
Images :: struct {
	data:    rawptr,
	create:  proc(data: rawptr, rgba: []u8, w, h: int) -> (Texture_Id, bool),
	destroy: proc(data: rawptr, id: Texture_Id),
}

// The largest image decoded, by side: a picture past this is refused rather than
// decoded into hundreds of megabytes.
MAX_IMAGE_SIDE :: 8192

// Decodes a JPEG, a PNG or another image stb_image reads into RGBA pixels, w by h,
// allocated with allocator. ok is false for bytes that are no image, or one too
// large; a damaged image gives false, never a panic.
decode_image :: proc(
	bytes: []u8,
	allocator := context.allocator,
) -> (
	rgba: []u8,
	w, h: int,
	ok: bool,
) {
	if len(bytes) == 0 || len(bytes) > int(max(c.int)) do return
	width, height, channels: c.int
	if stbi.info_from_memory(raw_data(bytes), c.int(len(bytes)), &width, &height, &channels) == 0 do return
	if width <= 0 || height <= 0 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE do return
	pixels := stbi.load_from_memory(
		raw_data(bytes),
		c.int(len(bytes)),
		&width,
		&height,
		&channels,
		4,
	)
	if pixels == nil do return
	defer stbi.image_free(pixels)
	w, h = int(width), int(height)
	rgba = slice.clone(pixels[:w * h * 4], allocator)
	return rgba, w, h, true
}

// A texture of RGBA pixels through the Ui's images; false when none can be made.
create_image :: proc(ui: ^Ui, rgba: []u8, w, h: int) -> (id: Texture_Id, ok: bool) {
	if ui.images.create == nil do return
	return ui.images.create(ui.images.data, rgba, w, h)
}

// Destroys a texture of create_image; its id draws nothing after.
destroy_image :: proc(ui: ^Ui, id: Texture_Id) {
	if ui.images.destroy != nil && id != ATLAS_TEXTURE do ui.images.destroy(ui.images.data, id)
}
