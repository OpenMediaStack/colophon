package ui

import "core:math"
import "core:strings"
import fs "vendor:fontstash"

Font :: enum u8 {
	Inter_Regular,
	Inter_Medium,
	Inter_Semibold,
	Mono_Regular,
	Mono_Medium,
}

@(private, rodata)
FONT_FILES := [Font][]u8 {
	.Inter_Regular  = #load("../../assets/fonts/Inter-Regular.ttf"),
	.Inter_Medium   = #load("../../assets/fonts/Inter-Medium.ttf"),
	.Inter_Semibold = #load("../../assets/fonts/Inter-SemiBold.ttf"),
	.Mono_Regular   = #load("../../assets/fonts/JetBrainsMono-Regular.ttf"),
	.Mono_Medium    = #load("../../assets/fonts/JetBrainsMono-Medium.ttf"),
}

// The type styles of the brief.
Text_Style :: enum u8 {
	Body,
	Body_Strong,
	Small,
	Label,
	Title,
	Numeric,
	Numeric_Strong,
}

Text_Style_Info :: struct {
	font:      Font,
	size:      f32,
	// Extra space between letters, in em.
	tracking:  f32,
	uppercase: bool,
}

@(rodata)
TEXT_STYLES := [Text_Style]Text_Style_Info {
	.Body           = {.Inter_Regular, 13, 0, false},
	.Body_Strong    = {.Inter_Medium, 13, 0, false},
	.Small          = {.Inter_Regular, 12, 0, false},
	.Label          = {.Inter_Medium, 11, 0.06, true},
	.Title          = {.Inter_Semibold, 15, 0, false},
	.Numeric        = {.Mono_Regular, 12, 0, false},
	.Numeric_Strong = {.Mono_Medium, 12, 0, false},
}

Align :: enum u8 {
	Left,
	Center,
	Right,
}

ELLIPSIS :: "…"

// Draws text with its vertical middle on y, aligned on x. Returns its width in points.
draw_text :: proc(
	r: ^Renderer,
	text: string,
	x, y: f32,
	style: Text_Style,
	color: Color,
	align := Align.Left,
) -> f32 {
	if len(text) == 0 do return 0
	// fontstash grows the atlas with the context allocator: make it the atlas's.
	context.allocator = r.atlas.allocator
	shown := styled_text(text, style)
	set_font_state(r, style)
	width := fs.TextBounds(&r.atlas.fonts, shown) / r.scale
	left := x
	switch align {
	case .Left:
	case .Center:
		left = x - width / 2
	case .Right:
		left = x - width
	}
	list := begin_command(r, ATLAS_TEXTURE)
	iter := fs.TextIterInit(
		&r.atlas.fonts,
		math.round(left * r.scale),
		math.round(y * r.scale),
		shown,
	)
	quad: fs.Quad
	for fs.TextIterNext(&r.atlas.fonts, &iter, &quad) {
		if quad.x1 <= quad.x0 do continue
		first := vertex_count(list)
		push_vertex(list, {quad.x0, quad.y0}, color, {quad.s0, quad.t0})
		push_vertex(list, {quad.x1, quad.y0}, color, {quad.s1, quad.t0})
		push_vertex(list, {quad.x1, quad.y1}, color, {quad.s1, quad.t1})
		push_vertex(list, {quad.x0, quad.y1}, color, {quad.s0, quad.t1})
		push_quad(list, first)
	}
	return width
}

// Draws text cut with an ellipsis to fit width, aligned within it.
draw_text_fit :: proc(
	r: ^Renderer,
	text: string,
	x, y, width: f32,
	style: Text_Style,
	color: Color,
	align := Align.Left,
) {
	shown := styled_text(text, style)
	length, cut := text_fit(r, shown, style, width)
	if cut do shown = strings.concatenate({shown[:length], ELLIPSIS}, context.temp_allocator)
	switch align {
	case .Left:
		draw_text(r, shown, x, y, style, color)
	case .Center:
		draw_text(r, shown, x + width / 2, y, style, color, .Center)
	case .Right:
		draw_text(r, shown, x + width, y, style, color, .Right)
	}
}

// The width of text in points.
text_width :: proc(r: ^Renderer, text: string, style: Text_Style) -> f32 {
	if len(text) == 0 do return 0
	context.allocator = r.atlas.allocator
	set_font_state(r, style)
	return fs.TextBounds(&r.atlas.fonts, styled_text(text, style)) / r.scale
}

// How many bytes of text fit width: all of it (cut is false), or the longest
// start, on a character boundary, that leaves room for an ellipsis after it.
text_fit :: proc(
	r: ^Renderer,
	text: string,
	style: Text_Style,
	width: f32,
) -> (
	length: int,
	cut: bool,
) {
	if width <= 0 do return 0, len(text) > 0
	if text_width(r, text, style) <= width do return len(text), false
	room := width - text_width(r, ELLIPSIS, style)
	for advance in text_advances(r, text, style) {
		if advance.x > room do break
		length = advance.end
	}
	return length, true
}

// The x of every byte boundary of text, in points from its start: the caret
// positions of a text field. The slice is allocated with allocator; free it with
// delete.
caret_positions :: proc(
	r: ^Renderer,
	text: string,
	style: Text_Style,
	allocator := context.allocator,
) -> []f32 {
	xs := make([]f32, len(text) + 1, allocator)
	previous := 0
	for advance in text_advances(r, text, style) {
		for k in previous + 1 ..= advance.end do xs[k] = advance.x
		previous = advance.end
	}
	return xs
}

// The end of a character of a text, as a byte offset, and the x after it in points.
@(private = "file")
Advance :: struct {
	end: int,
	x:   f32,
}

// Where each character of text ends, in order, measured in one pass. Allocated
// with context.temp_allocator.
@(private = "file")
text_advances :: proc(r: ^Renderer, text: string, style: Text_Style) -> []Advance {
	advances := make([dynamic]Advance, 0, len(text), context.temp_allocator)
	if len(text) == 0 do return advances[:]
	context.allocator = r.atlas.allocator
	set_font_state(r, style)
	iter := fs.TextIterInit(&r.atlas.fonts, 0, 0, text)
	quad: fs.Quad
	for fs.TextIterNext(&r.atlas.fonts, &iter, &quad) {
		append(&advances, Advance{iter.next, iter.nextx / r.scale})
	}
	return advances[:]
}

// The text a style shows: in uppercase for labels, in context.temp_allocator.
@(private)
styled_text :: proc(text: string, style: Text_Style) -> string {
	if !TEXT_STYLES[style].uppercase do return text
	return strings.to_upper(text, context.temp_allocator)
}

@(private)
set_font_state :: proc(r: ^Renderer, style: Text_Style) {
	info := TEXT_STYLES[style]
	size := info.size * r.scale
	fs.SetFont(&r.atlas.fonts, r.atlas.font_ids[info.font])
	fs.SetSize(&r.atlas.fonts, size)
	fs.SetSpacing(&r.atlas.fonts, info.tracking * size)
	fs.SetAlignHorizontal(&r.atlas.fonts, .LEFT)
	fs.SetAlignVertical(&r.atlas.fonts, .MIDDLE)
}
