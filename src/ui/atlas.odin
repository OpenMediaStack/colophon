package ui

import "base:runtime"
import "core:c"
import fs "vendor:fontstash"
import stbtt "vendor:stb/truetype"

Icon :: enum u8 {
	Check,
	Chevron_Down,
	Chevron_Right,
	Chevron_Up,
	Circle_Alert,
	Columns,
	Folder,
	Music,
	Panel_Left,
	Panel_Right,
	Pause,
	Play,
	Redo,
	Save,
	Search,
	Skip_Back,
	Skip_Forward,
	Triangle_Alert,
	Undo,
	Volume,
	X,
}

// The side of an icon mask, in pixels. scripts/icons.sh makes the masks.
@(private)
ICON_SIZE :: 64

@(private, rodata)
ICON_MASKS := [Icon][]u8 {
	.Check          = #load("../../assets/icons/masks/check.a8"),
	.Chevron_Down   = #load("../../assets/icons/masks/chevron-down.a8"),
	.Chevron_Right  = #load("../../assets/icons/masks/chevron-right.a8"),
	.Chevron_Up     = #load("../../assets/icons/masks/chevron-up.a8"),
	.Circle_Alert   = #load("../../assets/icons/masks/circle-alert.a8"),
	.Columns        = #load("../../assets/icons/masks/columns.a8"),
	.Folder         = #load("../../assets/icons/masks/folder.a8"),
	.Music          = #load("../../assets/icons/masks/music.a8"),
	.Panel_Left     = #load("../../assets/icons/masks/panel-left.a8"),
	.Panel_Right    = #load("../../assets/icons/masks/panel-right.a8"),
	.Pause          = #load("../../assets/icons/masks/pause.a8"),
	.Play           = #load("../../assets/icons/masks/play.a8"),
	.Redo           = #load("../../assets/icons/masks/redo.a8"),
	.Save           = #load("../../assets/icons/masks/save.a8"),
	.Search         = #load("../../assets/icons/masks/search.a8"),
	.Skip_Back      = #load("../../assets/icons/masks/skip-back.a8"),
	.Skip_Forward   = #load("../../assets/icons/masks/skip-forward.a8"),
	.Triangle_Alert = #load("../../assets/icons/masks/triangle-alert.a8"),
	.Undo           = #load("../../assets/icons/masks/undo.a8"),
	.Volume         = #load("../../assets/icons/masks/volume.a8"),
	.X              = #load("../../assets/icons/masks/x.a8"),
}

@(private)
ATLAS_SIZE :: 2048

// Each icon is kept at 64, 32 and 16 pixels, each halved from the one before, so
// one drawn at 16 or 32 pixels is not sampled from a mask four times its size.
@(private)
ICON_LEVELS :: [3]int{64, 32, 16}

// One alpha texture for glyphs, icons and solid shapes. fontstash packs the glyphs
// and keeps a 2 by 2 white rect at the origin, which solid shapes sample; the icons
// are packed beside the glyphs when the atlas is made.
Atlas :: struct {
	allocator: runtime.Allocator,
	fonts:     fs.FontContext,
	font_ids:  [Font]int,
	// What a size of the styles is multiplied by for fontstash, which takes the height of a
	// line (ascent to descent) where the brief and 1.0.0's 13 px are the em: Inter's lines
	// are 1.21 em, so 13 would draw 10.7 px.
	em_scale:  [Font]f32,
	// Where each size of each icon starts in the atlas.
	icons:     [Icon][len(ICON_LEVELS)][2]int,
}

@(private)
atlas_init :: proc(a: ^Atlas, allocator := context.allocator) {
	a.allocator = allocator
	context.allocator = allocator
	fs.Init(&a.fonts, ATLAS_SIZE, ATLAS_SIZE, .TOPLEFT)
	for font in Font {
		a.font_ids[font] = fs.AddFontMem(&a.fonts, "colophon", FONT_FILES[font], false)
		a.em_scale[font] = line_height_in_em(&a.fonts.fonts[a.font_ids[font]].info)
	}
	levels := ICON_LEVELS
	for icon in Icon {
		mask := ICON_MASKS[icon]
		if len(mask) < ICON_SIZE * ICON_SIZE do continue
		pixels := make([]u8, ICON_SIZE * ICON_SIZE)
		defer delete(pixels)
		copy(pixels, mask)
		for size, level in levels {
			if level > 0 do halve(pixels, size * 2)
			// One pixel of empty border keeps a neighbour from bleeding in when sampled.
			x, y, ok := fs.__AtlasAddRect(&a.fonts, size + 2, size + 2)
			if !ok do break
			a.icons[icon][level] = {x + 1, y + 1}
			for row in 0 ..< size {
				dst := (y + 1 + row) * a.fonts.width + x + 1
				copy(a.fonts.textureData[dst:dst + size], pixels[row * size:][:size])
			}
		}
	}
	// Everything changed: the backend uploads the whole atlas once.
	a.fonts.dirtyRect = {0, 0, f32(a.fonts.width), f32(a.fonts.height)}
}

// Halves a square mask side by side in place: each pixel becomes the average of
// the 2 by 2 block it covered, and the result fills the start of pixels.
@(private = "file")
halve :: proc(pixels: []u8, side: int) {
	half := side / 2
	for y in 0 ..< half {
		for x in 0 ..< half {
			sum := int(pixels[2 * y * side + 2 * x]) + int(pixels[2 * y * side + 2 * x + 1])
			sum +=
				int(pixels[(2 * y + 1) * side + 2 * x]) +
				int(pixels[(2 * y + 1) * side + 2 * x + 1])
			pixels[y * half + x] = u8((sum + 2) / 4)
		}
	}
}

@(private)
atlas_destroy :: proc(a: ^Atlas) {
	context.allocator = a.allocator
	fs.Destroy(&a.fonts)
}

@(private)
white_uv :: proc(a: ^Atlas) -> [2]f32 {
	return {1 / f32(a.fonts.width), 1 / f32(a.fonts.height)}
}

// The texture coordinates of the size of icon best drawn pixels wide: the
// smallest at least that big.
@(private)
icon_uv :: proc(a: ^Atlas, icon: Icon, pixels: f32) -> (u0, v0, u1, v1: f32) {
	levels := ICON_LEVELS
	level := 0
	for size, i in levels do if f32(size) >= pixels do level = i
	size := levels[level]
	p := a.icons[icon][level]
	w := f32(a.fonts.width)
	h := f32(a.fonts.height)
	return f32(p.x) / w, f32(p.y) / h, f32(p.x + size) / w, f32(p.y + size) / h
}

// How many ems a line of the font is high, from its ascent to its descent: what a size in
// ems must be multiplied by for fontstash to draw that em.
@(private = "file")
line_height_in_em :: proc(info: ^stbtt.fontinfo) -> f32 {
	ascent, descent, gap: c.int
	stbtt.GetFontVMetrics(info, &ascent, &descent, &gap)
	return f32(ascent - descent) * stbtt.ScaleForMappingEmToPixels(info, 1)
}
