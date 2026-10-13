package ui

import "core:math"
import "core:strings"
import "core:unicode/utf8"
import fs "vendor:fontstash"

Font :: enum u8 {
	Inter_Regular,
	Inter_Medium,
	Inter_Semibold,
	Mono_Regular,
	Mono_Medium,
}

@(rodata)
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
	shown := text_fit(r, text, style, width)
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
	set_font_state(r, style)
	return fs.TextBounds(&r.atlas.fonts, styled_text(text, style)) / r.scale
}

// text, or its longest start followed by an ellipsis that fits width. A cut string
// is allocated with context.temp_allocator.
text_fit :: proc(r: ^Renderer, text: string, style: Text_Style, width: f32) -> string {
	if width <= 0 do return ""
	if text_width(r, text, style) <= width do return text
	room := width - text_width(r, ELLIPSIS, style)
	end := 0
	for i := 0; i < len(text); {
		_, size := utf8.decode_rune_in_string(text[i:])
		next := i + size
		if text_width(r, text[:next], style) > room do break
		end = next
		i = next
	}
	return strings.concatenate({text[:end], ELLIPSIS}, context.temp_allocator)
}

// The x of every byte boundary of text, in points from its start: the caret
// positions of a text field. Allocated with context.temp_allocator.
caret_positions :: proc(r: ^Renderer, text: string, style: Text_Style) -> []f32 {
	xs := make([]f32, len(text) + 1, context.temp_allocator)
	for i := 0; i < len(text); {
		_, size := utf8.decode_rune_in_string(text[i:])
		width := text_width(r, text[:i + size], style)
		for k in i + 1 ..= i + size do xs[k] = width
		i += size
	}
	return xs
}

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
