package ui

import "core:c"
import fs "vendor:fontstash"
import sdl "vendor:sdl3"

#assert(size_of(Vertex) == size_of(sdl.Vertex))
#assert(offset_of(Vertex, color) == offset_of(sdl.Vertex, color))
#assert(offset_of(Vertex, uv) == offset_of(sdl.Vertex, tex_coord))

// Draws a Renderer's lists with an SDL renderer, and owns the textures they name.
// The lists are in pixels: keep the SDL renderer's scale at 1.
Sdl_Backend :: struct {
	renderer:   ^sdl.Renderer,
	atlas:      ^sdl.Texture,
	atlas_size: [2]int,
	// Indexed by Texture_Id minus one; a destroyed texture leaves nil, and its id
	// is never given again, so a stale id draws nothing rather than another image.
	textures:   [dynamic]^sdl.Texture,
}

// Free with sdl_backend_destroy, before the SDL renderer.
sdl_backend_init :: proc(
	b: ^Sdl_Backend,
	renderer: ^sdl.Renderer,
	allocator := context.allocator,
) {
	b.renderer = renderer
	b.textures = make([dynamic]^sdl.Texture, allocator)
}

sdl_backend_destroy :: proc(b: ^Sdl_Backend) {
	if b.atlas != nil do sdl.DestroyTexture(b.atlas)
	for texture in b.textures {
		if texture != nil do sdl.DestroyTexture(texture)
	}
	delete(b.textures)
}

// Makes a texture from RGBA pixels, w by h, for draw_image. ok is false when SDL
// fails.
sdl_backend_create_texture :: proc(
	b: ^Sdl_Backend,
	rgba: []u8,
	w, h: int,
) -> (
	id: Texture_Id,
	ok: bool,
) {
	if w <= 0 || h <= 0 || len(rgba) < w * h * 4 do return
	texture := sdl.CreateTexture(b.renderer, .RGBA32, .STATIC, c.int(w), c.int(h))
	if texture == nil do return
	if !sdl.UpdateTexture(texture, nil, raw_data(rgba), c.int(w * 4)) ||
	   !sdl.SetTextureBlendMode(texture, {.BLEND}) ||
	   !sdl.SetTextureScaleMode(texture, .LINEAR) {
		sdl.DestroyTexture(texture)
		return
	}
	append(&b.textures, texture)
	return Texture_Id(len(b.textures)), true
}

// Destroys a texture of sdl_backend_create_texture. Its id draws nothing after.
sdl_backend_destroy_texture :: proc(b: ^Sdl_Backend, id: Texture_Id) {
	index := int(id) - 1
	if index < 0 || index >= len(b.textures) || b.textures[index] == nil do return
	sdl.DestroyTexture(b.textures[index])
	b.textures[index] = nil
}

// Uploads what changed in the atlas and draws every layer. False when SDL fails.
sdl_backend_draw :: proc(b: ^Sdl_Backend, r: ^Renderer) -> bool {
	upload_atlas(b, &r.atlas) or_return
	// Texture coordinates stay inside each texture: an image's edge is not blended
	// with its opposite edge, and SDL need not check every vertex for wrapping.
	sdl.SetRenderTextureAddressMode(b.renderer, .CLAMP, .CLAMP) or_return
	defer sdl.SetRenderClipRect(b.renderer, nil)
	for &list in r.lists {
		for command in list.commands {
			draw_command(b, &list, command) or_return
		}
	}
	return true
}

@(private = "file")
draw_command :: proc(b: ^Sdl_Backend, list: ^Draw_List, command: Draw_Command) -> bool {
	if command.index_count == 0 do return true
	if clip, clipped := command.clip.?; clipped {
		rect := sdl.Rect{clip.x, clip.y, clip.w, clip.h}
		sdl.SetRenderClipRect(b.renderer, &rect) or_return
	} else {
		sdl.SetRenderClipRect(b.renderer, nil) or_return
	}
	texture := texture_of(b, command.texture)
	if texture == nil do return true
	vertices := list.vertices[command.first_vertex:][:command.vertex_count]
	indices := list.indices[command.first_index:][:command.index_count]
	return sdl.RenderGeometry(
		b.renderer,
		texture,
		cast([^]sdl.Vertex)raw_data(vertices),
		c.int(len(vertices)),
		raw_data(indices),
		c.int(len(indices)),
	)
}

@(private = "file")
texture_of :: proc(b: ^Sdl_Backend, id: Texture_Id) -> ^sdl.Texture {
	if id == ATLAS_TEXTURE do return b.atlas
	index := int(id) - 1
	if index < 0 || index >= len(b.textures) do return nil
	return b.textures[index]
}

// Makes the atlas texture again when fontstash grew it, else writes the region
// fontstash marked as changed into it.
@(private = "file")
upload_atlas :: proc(b: ^Sdl_Backend, a: ^Atlas) -> bool {
	size := [2]int{a.fonts.width, a.fonts.height}
	if b.atlas == nil || size != b.atlas_size {
		if b.atlas != nil do sdl.DestroyTexture(b.atlas)
		b.atlas = sdl.CreateTexture(b.renderer, .RGBA32, .STREAMING, c.int(size.x), c.int(size.y))
		if b.atlas == nil do return false
		sdl.SetTextureBlendMode(b.atlas, {.BLEND}) or_return
		sdl.SetTextureScaleMode(b.atlas, .LINEAR) or_return
		b.atlas_size = size
		a.fonts.dirtyRect = {0, 0, f32(size.x), f32(size.y)}
	}
	dirty: [4]f32
	if !fs.ValidateTexture(&a.fonts, &dirty) do return true
	x0 := clamp(int(dirty[0]), 0, size.x)
	y0 := clamp(int(dirty[1]), 0, size.y)
	x1 := clamp(int(dirty[2]), x0, size.x)
	y1 := clamp(int(dirty[3]), y0, size.y)
	if x1 == x0 || y1 == y0 do return true
	rect := sdl.Rect{c.int(x0), c.int(y0), c.int(x1 - x0), c.int(y1 - y0)}
	pixels: rawptr
	pitch: c.int
	sdl.LockTexture(b.atlas, &rect, &pixels, &pitch) or_return
	defer sdl.UnlockTexture(b.atlas)
	// The atlas holds coverage; the texture is white with that coverage as alpha.
	for y in y0 ..< y1 {
		row := ([^]u8)(pixels)[(y - y0) * int(pitch):]
		for x in x0 ..< x1 {
			i := (x - x0) * 4
			row[i + 0] = 255
			row[i + 1] = 255
			row[i + 2] = 255
			row[i + 3] = a.fonts.textureData[y * size.x + x]
		}
	}
	return true
}
