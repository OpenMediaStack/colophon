package ui

import "base:runtime"
import fs "vendor:fontstash"

Icon :: enum u8 {
	Check,
	Chevron_Down,
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
ICON_SIZE :: 64

@(rodata)
ICON_MASKS := [Icon][]u8 {
	.Check          = #load("../../assets/icons/masks/check.a8"),
	.Chevron_Down   = #load("../../assets/icons/masks/chevron-down.a8"),
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

ATLAS_SIZE :: 2048

// One alpha texture for glyphs, icons and solid shapes. fontstash packs the glyphs
// and keeps a 2 by 2 white rect at the origin, which solid shapes sample; the icons
// are packed beside the glyphs when the atlas is made.
Atlas :: struct {
	allocator: runtime.Allocator,
	fonts:     fs.FontContext,
	font_ids:  [Font]int,
	icons:     [Icon][2]int,
}

@(private)
atlas_init :: proc(a: ^Atlas, allocator := context.allocator) {
	a.allocator = allocator
	context.allocator = allocator
	fs.Init(&a.fonts, ATLAS_SIZE, ATLAS_SIZE, .TOPLEFT)
	for font in Font {
		a.font_ids[font] = fs.AddFontMem(&a.fonts, "colophon", FONT_FILES[font], false)
	}
	for icon in Icon {
		// One pixel of empty border keeps a neighbour from bleeding in when sampled.
		x, y, ok := fs.__AtlasAddRect(&a.fonts, ICON_SIZE + 2, ICON_SIZE + 2)
		if !ok do continue
		a.icons[icon] = {x + 1, y + 1}
		mask := ICON_MASKS[icon]
		for row in 0 ..< ICON_SIZE {
			start := row * ICON_SIZE
			if start + ICON_SIZE > len(mask) do break
			dst := (y + 1 + row) * a.fonts.width + x + 1
			copy(a.fonts.textureData[dst:dst + ICON_SIZE], mask[start:start + ICON_SIZE])
		}
	}
	// Everything changed: the backend uploads the whole atlas once.
	a.fonts.dirtyRect = {0, 0, f32(a.fonts.width), f32(a.fonts.height)}
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

@(private)
icon_uv :: proc(a: ^Atlas, icon: Icon) -> (u0, v0, u1, v1: f32) {
	p := a.icons[icon]
	w := f32(a.fonts.width)
	h := f32(a.fonts.height)
	return f32(p.x) / w, f32(p.y) / h, f32(p.x + ICON_SIZE) / w, f32(p.y + ICON_SIZE) / h
}
