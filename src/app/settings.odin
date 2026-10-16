package main

import "core:slice"

import "../engine"
import lib "../library"
import ui "../ui"

@(private = "file")
LABEL_WIDTH :: 90
@(private = "file")
LABEL_GAP :: 12
@(private = "file")
ROW_GAP :: 8
// The checkbox's row: 20 high, as 1.0.0's, with its 16 point box centred in it.
@(private = "file")
CHECKBOX_ROW :: 20

// Opens the settings: the defaults for writing tags, and developer mode.
open_settings :: proc(app: ^App) {
	app.settings_open = true
	// The dialog shows at once, whatever asked for it: a key was taken, not a command.
	app.commands += 1
}

// What the settings menu item is called where it lives: Settings…, Preferences… on
// Linux and Options… on Windows, as 1.0.0 named it.
settings_label :: proc(app: ^App) -> string {
	switch app.platform {
	case .Linux:
		return ui.tr("Preferences…")
	case .Windows:
		return ui.tr("Options…")
	case .Mac:
	}
	return ui.tr("Settings…")
}

// The settings dialog, while open. A choice applies at once; Done and Escape close it.
settings_dialog :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	if !app.settings_open do return
	r := ctx.renderer
	e := &app.engine
	policy := e.edits.policy
	id3v2_3 := policy.id3v2 == .V2_3
	hints := [3]string {
		id3v2_3 ? ui.tr("Read by every player, the oldest included.") : ui.tr("The current version, with UTF-8 text."),
		policy.id3v1 == .Keep ? ui.tr("Rewritten in the files that have one, added to none.") : policy.id3v1 == .Always ? ui.tr("Written in every file saved.") : ui.tr("Removed from the files saved, after asking."),
		ui.tr("Choose the tag versions of each file in the inspector, ID3v2.2 included."),
	}
	width := f32(440)
	options := ui.Dialog_Options {
		title    = ui.tr("Settings"),
		primary  = ui.tr("Done"),
		width    = width,
		platform = app.platform,
	}
	control_width := min(width, window.w - 32) - 40 - LABEL_WIDTH - LABEL_GAP
	hint_line := ui.line_height(r, .Small)
	controls := [3]f32{ui.BUTTON_HEIGHT, ui.BUTTON_HEIGHT, CHECKBOX_ROW}
	height: f32
	for hint, i in hints {
		lines := ui.wrap_text(r, hint, .Small, control_width, context.temp_allocator)
		height += controls[i] + ROW_GAP + f32(max(len(lines), 1)) * hint_line
		if i < len(hints) - 1 do height += ROW_GAP
	}
	options.content_height = height
	d := ui.begin_dialog(ctx, ui.widget_id("Settings"), window, options)
	x := d.content.x
	control_x := x + LABEL_WIDTH + LABEL_GAP
	y := d.content.y
	label :: proc(ctx: ^ui.Ui, text: string, x, y: f32, height: f32 = ui.BUTTON_HEIGHT) {
		ui.draw_text(ctx.renderer, text, x, y + height / 2, .Body, ctx.theme.text_secondary)
	}
	hint :: proc(ctx: ^ui.Ui, text: string, x, y, width: f32, index: int) -> f32 {
		lines := ui.wrap_text(ctx.renderer, text, .Small, width, context.temp_allocator)
		hint_line := ui.line_height(ctx.renderer, .Small)
		for line, i in lines {
			ui.draw_text(
				ctx.renderer,
				line,
				x,
				y + f32(i) * hint_line + hint_line / 2,
				.Small,
				ctx.theme.text_tertiary,
			)
		}
		height := f32(max(len(lines), 1)) * hint_line
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Setting hint", index),
				role = .Label,
				label = text,
				rect = {x, y, width, height},
			},
		)
		return height
	}

	label(ctx, ui.tr("ID3v2 version"), x, y)
	versions := [2]ui.Segment{{label = "2.3", numeric = true}, {label = "2.4", numeric = true}}
	if chosen, picked := ui.segmented(
		   ctx,
		   ui.widget_id("ID3v2 version"),
		   {control_x, y, control_width, ui.BUTTON_HEIGHT},
		   ui.tr("ID3v2 version"),
		   versions[:],
		   id3v2_3 ? 0 : 1,
	   ).?; picked {
		execute(app, engine.Set_Write_Policy{{chosen == 0 ? .V2_3 : .V2_4, policy.id3v1}})
	}
	y += ui.BUTTON_HEIGHT + ROW_GAP
	y += hint(ctx, hints[0], control_x, y, control_width, 0) + ROW_GAP

	label(ctx, ui.tr("ID3v1 tag"), x, y)
	policies := [lib.Id3v1_Policy]ui.Segment {
		.Keep = {label = ui.tr("Keep")},
		.Always = {label = ui.tr("Always")},
		.Never = {label = ui.tr("Never")},
	}
	if chosen, picked := ui.segmented(
		   ctx,
		   ui.widget_id("ID3v1 tag"),
		   {control_x, y, control_width, ui.BUTTON_HEIGHT},
		   ui.tr("ID3v1 tag"),
		   slice.enumerated_array(&policies),
		   int(policy.id3v1),
	   ).?; picked {
		execute(app, engine.Set_Write_Policy{{policy.id3v2, lib.Id3v1_Policy(chosen)}})
	}
	y += ui.BUTTON_HEIGHT + ROW_GAP
	y += hint(ctx, hints[1], control_x, y, control_width, 1) + ROW_GAP

	label(ctx, ui.tr("Developer"), x, y, CHECKBOX_ROW)
	if ui.checkbox(
		ctx,
		ui.child_id(d.id, "developer mode"),
		{control_x, y, control_width, CHECKBOX_ROW},
		ui.tr("Developer mode"),
		e.view.developer_mode,
	) {
		execute(app, engine.Toggle_Developer_Mode{})
	}
	y += CHECKBOX_ROW + ROW_GAP
	y += hint(ctx, hints[2], control_x, y, control_width, 2)

	switch ui.end_dialog(ctx, d) {
	case .None:
	case .Primary, .Cancel, .Discard:
		app.settings_open = false
	}
}
