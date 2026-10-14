package main

import ui "../ui"

// What the centre of the window shows before anything is open: an invitation to open
// a folder.
empty_state :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	WELL :: 72
	SPACING :: 16
	LINE :: 18
	WIDEST_TEXT :: 400
	r := ctx.renderer
	th := ctx.theme
	ui.fill_rect(r, rect, th.surface_1)
	title := ui.tr("Open your music folder")
	words := ui.tr(
		"Colophon reads the tags of every MP3 in a folder and its subfolders. Nothing is written to your files until you save.",
	)
	lines := ui.wrap_text(r, words, .Body, min(WIDEST_TEXT, rect.w - 48), context.temp_allocator)
	open_label := ui.tr("Open folder…")
	open_options := ui.Button_Options {
		kind     = .Primary,
		shortcut = shortcut_hint(app, "O"),
	}
	open_width := ui.button_width(r, open_label, open_options)
	height: f32 =
		WELL + SPACING + 22 + SPACING + f32(len(lines)) * LINE + SPACING + ui.BUTTON_HEIGHT
	centre_x := rect.x + rect.w / 2
	y := rect.y + (rect.h - height) / 2

	well := ui.Rect{centre_x - WELL / 2, y, WELL, WELL}
	ui.fill_rect(r, well, th.surface_2, 8)
	ui.stroke_rect(r, well, th.border_subtle, 8)
	ui.draw_icon_centered(r, .Folder, well, th.text_tertiary, 32)
	y += WELL + SPACING

	title_width := ui.draw_text(r, title, centre_x, y + 11, .Heading, th.text_primary, .Center)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Open your music folder"),
			role = .Label,
			label = title,
			rect = {centre_x - title_width / 2, y, title_width, 22},
		},
	)
	y += 22 + SPACING

	for line, i in lines {
		width := ui.draw_text(r, line, centre_x, y + LINE / 2, .Body, th.text_secondary, .Center)
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Empty state line", i),
				role = .Label,
				label = line,
				rect = {centre_x - width / 2, y, width, LINE},
			},
		)
		y += LINE
	}
	y += SPACING

	open := ui.Rect{centre_x - open_width / 2, y, open_width, ui.BUTTON_HEIGHT}
	if ui.button(ctx, ui.widget_id("Open folder…"), open, open_label, open_options) do open_folder(app)
}
