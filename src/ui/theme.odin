package ui

// The colour tokens of docs/design/brief.md, with the same names.
Theme :: struct {
	surface_0, surface_1, surface_2, surface_3:  Color,
	border_subtle, border_row, border_strong:    Color,
	text_primary, text_secondary, text_tertiary: Color,
	text_disabled:                               Color,
	accent, accent_hover, accent_text:           Color,
	accent_selection, on_accent:                 Color,
	focus_ring, modified_border:                 Color,
	error, on_error, warning:                    Color,
	scrim, shadow_menu, shadow_dialog:           Color,
	menu_bar:                                    Color,
}

// A colour from its 0xRRGGBB value and an opacity from 0 to 1.
hex :: proc "contextless" (rgb: u32, alpha: f32 = 1) -> Color {
	return {
		f32((rgb >> 16) & 0xff) / 255,
		f32((rgb >> 8) & 0xff) / 255,
		f32(rgb & 0xff) / 255,
		alpha,
	}
}

Theme_Kind :: enum u8 {
	Dark,
	Light,
}

// The tokens of a theme.
theme :: proc(kind: Theme_Kind) -> Theme {
	switch kind {
	case .Dark:
		return dark_theme()
	case .Light:
		return light_theme()
	}
	return dark_theme()
}

@(private = "file")
dark_theme :: proc() -> Theme {
	return {
		surface_0 = hex(0x121214),
		surface_1 = hex(0x18181B),
		surface_2 = hex(0x202024),
		surface_3 = hex(0x2A2A2F),
		border_subtle = hex(0x2C2C31),
		border_row = hex(0x1F1F23),
		border_strong = hex(0x3A3A40),
		text_primary = hex(0xECECEE),
		text_secondary = hex(0xA1A1AA),
		text_tertiary = hex(0x8A8A93),
		text_disabled = hex(0x52525B),
		accent = hex(0xEAB308),
		accent_hover = hex(0xFACC15),
		accent_text = hex(0xEAB308),
		accent_selection = hex(0x3A3118),
		on_accent = hex(0x1A1405),
		focus_ring = hex(0xEAB308, 0.6),
		modified_border = hex(0xEAB308, 0.55),
		error = hex(0xF87171),
		on_error = hex(0x2A0A0A),
		warning = hex(0xFB923C),
		scrim = hex(0x000000, 0.45),
		shadow_menu = hex(0x000000, 0.45),
		shadow_dialog = hex(0x000000, 0.55),
		menu_bar = hex(0x1C1C1F),
	}
}

@(private = "file")
light_theme :: proc() -> Theme {
	return {
		surface_0 = hex(0xF2F2F4),
		surface_1 = hex(0xFFFFFF),
		surface_2 = hex(0xF7F7F8),
		surface_3 = hex(0xE8E8EB),
		border_subtle = hex(0xE4E4E7),
		border_row = hex(0xF1F1F3),
		border_strong = hex(0xD4D4D8),
		text_primary = hex(0x18181B),
		text_secondary = hex(0x52525B),
		text_tertiary = hex(0x6B6B74),
		text_disabled = hex(0xA1A1AA),
		accent = hex(0xEAB308),
		accent_hover = hex(0xFACC15),
		accent_text = hex(0x8F5A06),
		accent_selection = hex(0xFCF0C8),
		on_accent = hex(0x1A1405),
		focus_ring = hex(0xCA8A04, 0.7),
		modified_border = hex(0xCA8A04, 0.7),
		error = hex(0xC62828),
		on_error = hex(0xFFFFFF),
		warning = hex(0xC2410C),
		scrim = hex(0x18181B, 0.18),
		shadow_menu = hex(0x000000, 0.12),
		shadow_dialog = hex(0x000000, 0.18),
		menu_bar = hex(0xF0F0F2),
	}
}

with_alpha :: proc(c: Color, alpha: f32) -> Color {
	return {c.r, c.g, c.b, c.a * alpha}
}
