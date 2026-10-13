package ui

import "core:math"

// Straight RGBA, each channel from 0 to 1.
Color :: [4]f32

// Draw lists are drawn in this order, so an overlay covers the base.
Layer :: enum u8 {
	Base,
	Overlay,
	Top,
}

// A texture the backend owns: the atlas, always there, or one that
// sdl_backend_create_texture made, such as a cover.
Texture_Id :: distinct u32

ATLAS_TEXTURE :: Texture_Id(0)

// The layout of SDL_Vertex, so a draw list goes to SDL without a copy.
Vertex :: struct {
	position: [2]f32,
	color:    Color,
	uv:       [2]f32,
}

// A rectangle in pixels.
Pixel_Rect :: struct {
	x, y, w, h: i32,
}

// A run of triangles sharing a texture and a clip rectangle (in pixels). Its
// vertex_count vertices start at first_vertex, and its indices count from there.
Draw_Command :: struct {
	texture:      Texture_Id,
	clip:         Maybe(Pixel_Rect),
	first_vertex: int,
	vertex_count: int,
	first_index:  int,
	index_count:  int,
}

Draw_List :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]i32,
	commands: [dynamic]Draw_Command,
}

// Turns drawing calls in points into draw lists in pixels. Every shape, glyph and
// icon samples the one alpha atlas, tinted by the vertex colour; covers are the
// only other textures.
Renderer :: struct {
	scale:      f32,
	layer:      Layer,
	lists:      [Layer]Draw_List,
	clips:      [dynamic]Rect,
	atlas:      Atlas,
	// The atlas size when the frame began: see atlas_grew.
	atlas_size: [2]int,
}

// Loads the fonts and icons into the atlas. Every list, and the atlas when it
// grows, uses allocator. Free with renderer_destroy.
renderer_init :: proc(r: ^Renderer, allocator := context.allocator) {
	r.scale = 1
	for &list in r.lists {
		list.vertices = make([dynamic]Vertex, allocator)
		list.indices = make([dynamic]i32, allocator)
		list.commands = make([dynamic]Draw_Command, allocator)
	}
	r.clips = make([dynamic]Rect, allocator)
	atlas_init(&r.atlas, allocator)
	r.atlas_size = {r.atlas.fonts.width, r.atlas.fonts.height}
}

renderer_destroy :: proc(r: ^Renderer) {
	for &list in r.lists {
		delete(list.vertices)
		delete(list.indices)
		delete(list.commands)
	}
	delete(r.clips)
	atlas_destroy(&r.atlas)
}

// Starts a frame: renderer_begin_frame for drawing alone, ui_begin_frame for a Ui.
begin_frame :: proc {
	renderer_begin_frame,
	ui_begin_frame,
}

// Starts a frame drawn at scale pixels per point, emptying the lists.
renderer_begin_frame :: proc(r: ^Renderer, scale: f32) {
	r.scale = scale > 0 ? scale : 1
	r.layer = .Base
	for &list in r.lists {
		clear(&list.vertices)
		clear(&list.indices)
		clear(&list.commands)
	}
	clear(&r.clips)
	r.atlas_size = {r.atlas.fonts.width, r.atlas.fonts.height}
}

// True when new glyphs made the atlas grow during this frame. The texture
// coordinates drawn before the growth are then wrong: draw the frame again.
atlas_grew :: proc(r: ^Renderer) -> bool {
	return r.atlas_size != {r.atlas.fonts.width, r.atlas.fonts.height}
}

// Draws on layer from now on, and returns the layer drawn on before.
set_layer :: proc(r: ^Renderer, layer: Layer) -> (previous: Layer) {
	previous = r.layer
	r.layer = layer
	return
}

// Clips what follows to rect, in points, within the current clip.
push_clip :: proc(r: ^Renderer, rect: Rect, inside_current := true) {
	clip := rect
	if current, ok := current_clip(r); ok && inside_current do clip = rect_intersect(clip, current)
	append(&r.clips, clip)
}

pop_clip :: proc(r: ^Renderer) {
	if len(r.clips) > 0 do pop(&r.clips)
}

// The current clip in points, if any.
current_clip :: proc(r: ^Renderer) -> (Rect, bool) {
	if len(r.clips) == 0 do return {}, false
	return r.clips[len(r.clips) - 1], true
}

// Fills rect with color. radius, in points, rounds the corners; it is clamped to
// half the shorter side.
fill_rect :: proc(r: ^Renderer, rect: Rect, color: Color, radius: f32 = 0) {
	if color.a <= 0 do return
	emit_rounded_rect(r, rect, radius, color, color)
}

// Fills rect with a gradient from c0 at the top left to c1 at the bottom right.
fill_gradient :: proc(r: ^Renderer, rect: Rect, c0, c1: Color, radius: f32 = 0) {
	emit_rounded_rect(r, rect, radius, c0, c1)
}

// Draws texture, from sdl_backend_create_texture, stretched over rect, with
// rounded corners as fill_rect has them.
draw_image :: proc(
	r: ^Renderer,
	texture: Texture_Id,
	rect: Rect,
	radius: f32 = 0,
	tint := Color{1, 1, 1, 1},
) {
	emit_rounded_rect(r, rect, radius, tint, tint, texture)
}

// Strokes the inside of rect with a line width points wide.
stroke_rect :: proc(r: ^Renderer, rect: Rect, color: Color, radius: f32 = 0, width: f32 = 1) {
	if color.a <= 0 do return
	x0, y0, x1, y1 := snap(r, rect)
	if x1 <= x0 || y1 <= y0 do return
	line := min(max(math.round(width * r.scale), 1), (x1 - x0) / 2, (y1 - y0) / 2)
	outer_radius := min(radius * r.scale, (x1 - x0) / 2, (y1 - y0) / 2)
	if outer_radius <= 0.5 {
		stroke_square(r, x0, y0, x1, y1, line, color)
		return
	}
	// The outer edge follows the rect, the inner edge the rect inset by the line;
	// each edge has one pixel of feather, transparent on its outer side.
	inner_radius := max(outer_radius - line, 0)
	rings := [4][RING_POINTS][2]f32 {
		ring(x0, y0, x1, y1, outer_radius, 0.5),
		ring(x0, y0, x1, y1, outer_radius, -0.5),
		ring(x0 + line, y0 + line, x1 - line, y1 - line, inner_radius, 0.5),
		ring(x0 + line, y0 + line, x1 - line, y1 - line, inner_radius, -0.5),
	}
	alphas := [4]f32{0, color.a, color.a, 0}
	list := begin_command(r, ATLAS_TEXTURE)
	uv := white_uv(&r.atlas)
	first: [4]i32
	for points, k in rings {
		first[k] = vertex_count(list)
		for p in points {
			push_vertex(list, p, {color.r, color.g, color.b, alphas[k]}, uv)
		}
	}
	for k in 0 ..< 3 {
		stitch_rings(list, first[k], first[k + 1])
	}
}

// Draws an icon of the atlas in rect, turned clockwise by quarter_turns.
draw_icon :: proc(r: ^Renderer, icon: Icon, rect: Rect, color: Color, quarter_turns := 0) {
	x0, y0, x1, y1 := snap(r, rect)
	if x1 <= x0 || y1 <= y0 do return
	u0, v0, u1, v1 := icon_uv(&r.atlas, icon, max(x1 - x0, y1 - y0))
	uvs := [4][2]f32{{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}
	corners := [4][2]f32{{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}
	list := begin_command(r, ATLAS_TEXTURE)
	first := vertex_count(list)
	for corner, i in corners {
		push_vertex(list, corner, color, uvs[(i - quarter_turns) %% 4])
	}
	push_quad(list, first)
}

// Draws an icon size points wide (16 by default) centred in rect.
draw_icon_centered :: proc(r: ^Renderer, icon: Icon, rect: Rect, color: Color, size: f32 = 16) {
	draw_icon(
		r,
		icon,
		{rect.x + (rect.w - size) / 2, rect.y + (rect.h - size) / 2, size, size},
		color,
	)
}

// The vertices of the corners of a rounded rect: 17 per corner, from the top right
// clockwise, enough for a 36 point circle to look round.
@(private)
CORNER_SEGMENTS :: 16
@(private)
RING_POINTS :: 4 * (CORNER_SEGMENTS + 1)

// Points of the outline of a rounded rect, moved outward by offset pixels.
@(private)
ring :: proc(x0, y0, x1, y1, radius, offset: f32) -> (points: [RING_POINTS][2]f32) {
	centers := [4][2]f32 {
		{x1 - radius, y0 + radius},
		{x1 - radius, y1 - radius},
		{x0 + radius, y1 - radius},
		{x0 + radius, y0 + radius},
	}
	start_angles := [4]f32{-math.PI / 2, 0, math.PI / 2, math.PI}
	distance := max(radius + offset, 0)
	i := 0
	for corner in 0 ..< 4 {
		for step in 0 ..= CORNER_SEGMENTS {
			angle := start_angles[corner] + f32(step) / CORNER_SEGMENTS * (math.PI / 2)
			points[i] = centers[corner] + [2]f32{math.cos(angle), math.sin(angle)} * distance
			i += 1
		}
	}
	return
}

// The four sides of a square cornered stroke, line pixels wide.
@(private = "file")
stroke_square :: proc(r: ^Renderer, x0, y0, x1, y1, line: f32, color: Color) {
	s := r.scale
	fill_rect(r, {x0 / s, y0 / s, (x1 - x0) / s, line / s}, color)
	fill_rect(r, {x0 / s, (y1 - line) / s, (x1 - x0) / s, line / s}, color)
	fill_rect(r, {x0 / s, (y0 + line) / s, line / s, (y1 - y0 - 2 * line) / s}, color)
	fill_rect(r, {(x1 - line) / s, (y0 + line) / s, line / s, (y1 - y0 - 2 * line) / s}, color)
}

// Rounded rect in pixels, solid or textured, with a feather ring when rounded.
@(private)
emit_rounded_rect :: proc(
	r: ^Renderer,
	rect: Rect,
	radius: f32,
	c0, c1: Color,
	texture := ATLAS_TEXTURE,
) {
	x0, y0, x1, y1 := snap(r, rect)
	if x1 <= x0 || y1 <= y0 do return
	box := [4]f32{x0, y0, x1, y1}
	shape := Shape_Uv {
		textured = texture != ATLAS_TEXTURE,
		white    = white_uv(&r.atlas),
		box      = box,
	}
	list := begin_command(r, texture)
	rad := min(radius * r.scale, (x1 - x0) / 2, (y1 - y0) / 2)
	if rad <= 0.5 {
		first := vertex_count(list)
		for p in ([4][2]f32{{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}) {
			push_vertex(list, p, gradient_at(p, box, c0, c1), shape_uv(shape, p))
		}
		push_quad(list, first)
		return
	}
	inner := ring(x0, y0, x1, y1, rad, -0.5)
	outer := ring(x0, y0, x1, y1, rad, 0.5)
	center := [2]f32{(x0 + x1) / 2, (y0 + y1) / 2}
	center_index := vertex_count(list)
	push_vertex(list, center, gradient_at(center, box, c0, c1), shape_uv(shape, center))
	first_inner := vertex_count(list)
	for p in inner {
		push_vertex(list, p, gradient_at(p, box, c0, c1), shape_uv(shape, p))
	}
	first_outer := vertex_count(list)
	for p in outer {
		c := gradient_at(p, box, c0, c1)
		push_vertex(list, p, {c.r, c.g, c.b, 0}, shape_uv(shape, p))
	}
	for i in 0 ..< i32(RING_POINTS) {
		j := (i + 1) % RING_POINTS
		push_triangle(list, center_index, first_inner + i, first_inner + j)
	}
	stitch_rings(list, first_inner, first_outer)
}

// How a shape samples its texture: the atlas's white texel, or an image
// stretched over box.
@(private = "file")
Shape_Uv :: struct {
	textured: bool,
	white:    [2]f32,
	box:      [4]f32,
}

// The texture coordinate of point p; the feather ring, which reaches half a
// pixel outside the box, samples the image's edge.
@(private = "file")
shape_uv :: proc(s: Shape_Uv, p: [2]f32) -> [2]f32 {
	if !s.textured do return s.white
	u := (p.x - s.box[0]) / (s.box[2] - s.box[0])
	v := (p.y - s.box[1]) / (s.box[3] - s.box[1])
	return {clamp(u, 0, 1), clamp(v, 0, 1)}
}

@(private)
gradient_at :: proc(p: [2]f32, box: [4]f32, c0, c1: Color) -> Color {
	if c0 == c1 do return c0
	t := ((p.x - box[0]) / max(box[2] - box[0], 1) + (p.y - box[1]) / max(box[3] - box[1], 1)) / 2
	return c0 + (c1 - c0) * clamp(t, 0, 1)
}

// The edges of rect in whole pixels, so straight edges stay sharp.
@(private)
snap :: proc(r: ^Renderer, rect: Rect) -> (x0, y0, x1, y1: f32) {
	s := r.scale
	x0 = math.round(rect.x * s)
	y0 = math.round(rect.y * s)
	x1 = math.round((rect.x + rect.w) * s)
	y1 = math.round((rect.y + rect.h) * s)
	return
}

// The list of the current layer, ready to take triangles with texture under the
// current clip.
@(private)
begin_command :: proc(r: ^Renderer, texture: Texture_Id) -> ^Draw_List {
	list := &r.lists[r.layer]
	clip: Maybe(Pixel_Rect)
	if rect, ok := current_clip(r); ok {
		x0, y0, x1, y1 := snap(r, rect)
		clip = Pixel_Rect{i32(x0), i32(y0), i32(max(x1 - x0, 0)), i32(max(y1 - y0, 0))}
	}
	if n := len(list.commands); n > 0 {
		last := list.commands[n - 1]
		if last.texture == texture && last.clip == clip do return list
	}
	append(
		&list.commands,
		Draw_Command {
			texture = texture,
			clip = clip,
			first_vertex = len(list.vertices),
			first_index = len(list.indices),
		},
	)
	return list
}

// The index the next vertex gets, counted from the current command's first vertex.
@(private)
vertex_count :: proc(list: ^Draw_List) -> i32 {
	return i32(list.commands[len(list.commands) - 1].vertex_count)
}

@(private)
push_vertex :: proc(list: ^Draw_List, position: [2]f32, color: Color, uv: [2]f32) {
	append(&list.vertices, Vertex{position, color, uv})
	list.commands[len(list.commands) - 1].vertex_count += 1
}

@(private)
push_triangle :: proc(list: ^Draw_List, a, b, c: i32) {
	append(&list.indices, a, b, c)
	list.commands[len(list.commands) - 1].index_count += 3
}

// Two triangles over the four vertices from first, in drawing order.
@(private)
push_quad :: proc(list: ^Draw_List, first: i32) {
	push_triangle(list, first, first + 1, first + 2)
	push_triangle(list, first, first + 2, first + 3)
}

// Triangles between two rings of RING_POINTS vertices each.
@(private)
stitch_rings :: proc(list: ^Draw_List, a, b: i32) {
	for i in 0 ..< i32(RING_POINTS) {
		j := (i + 1) % RING_POINTS
		push_triangle(list, a + i, b + i, b + j)
		push_triangle(list, a + i, b + j, a + j)
	}
}

// The soft shadow of a floating layer of rect, cast offset_y down and blurred over
// blur points, as CSS's box-shadow draws it: rings of fading alpha around the shape.
draw_shadow :: proc(r: ^Renderer, rect: Rect, radius, offset_y, blur: f32, color: Color) {
	if color.a <= 0 do return
	x0, y0, x1, y1 := snap(r, {rect.x, rect.y + offset_y, rect.w, rect.h})
	if x1 <= x0 || y1 <= y0 do return
	b := blur * r.scale
	rad := min(radius * r.scale, (x1 - x0) / 2, (y1 - y0) / 2)
	// A gaussian blur's falloff in steps, half its strength at the shape's edge. The
	// rings inside the shape keep a radius of a pixel at least: a ring of points all in
	// one place makes triangles of no area, which SDL's software renderer mishandles.
	Step :: struct {
		offset, alpha: f32,
	}
	steps := [?]Step{{-b / 2, 0.9}, {-b / 4, 0.75}, {0, 0.5}, {b / 4, 0.25}, {b / 2, 0.09}, {b, 0}}
	list := begin_command(r, ATLAS_TEXTURE)
	uv := white_uv(&r.atlas)
	first := make([dynamic]i32, 0, len(steps), context.temp_allocator)
	previous_offset := min(f32)
	for step in steps {
		offset := max(step.offset, 1 - rad)
		if offset <= previous_offset do continue
		previous_offset = offset
		append(&first, vertex_count(list))
		for p in ring(x0, y0, x1, y1, rad, offset) {
			push_vertex(list, p, {color.r, color.g, color.b, color.a * step.alpha}, uv)
		}
	}
	// The middle, filled from the innermost ring, as a fan around its centre.
	center := [2]f32{(x0 + x1) / 2, (y0 + y1) / 2}
	center_index := vertex_count(list)
	push_vertex(list, center, {color.r, color.g, color.b, color.a * steps[0].alpha}, uv)
	for i in 0 ..< i32(RING_POINTS) {
		push_triangle(list, center_index, first[0] + i, first[0] + (i + 1) % RING_POINTS)
	}
	for k in 0 ..< len(first) - 1 do stitch_rings(list, first[k], first[k + 1])
}
