package main

import "../engine"
import ui "../ui"

// The toolbar: open folder, save, undo and redo, the filter, then the command palette
// and the panel toggles at the right end.
toolbar :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	BUTTON :: ui.TOOLBAR_BUTTON_SIZE
	GAP :: 4
	FILTER_WIDEST :: 440
	r := ctx.renderer
	th := ctx.theme
	e := &app.engine
	open := folder_open(app)
	ui.fill_rect(r, rect, th.surface_2)
	toolbar_id := ui.widget_id("Toolbar")
	ui.declare(ctx, {id = toolbar_id, role = .Group, label = ui.tr("Toolbar"), rect = rect})
	ui.push_parent(ctx, toolbar_id)
	defer ui.pop_parent(ctx)
	y := rect.y + (rect.h - BUTTON) / 2
	x := rect.x + 8

	if ui.toolbar_button(
		ctx,
		ui.widget_id("Open folder"),
		{x, y, BUTTON, BUTTON},
		.Folder,
		ui.tr("Open folder"),
	) {
		open_folder(app)
	}
	x += BUTTON + GAP
	x += save_button(ctx, app, {x, y}) + GAP
	// A line between the file actions and the edit ones.
	ui.fill_rect(r, {x + 4, rect.y + (rect.h - 18) / 2, 1, 18}, th.border_subtle)
	x += 9 + GAP
	if ui.toolbar_button(
		ctx,
		ui.widget_id("Undo"),
		{x, y, BUTTON, BUTTON},
		.Undo,
		ui.tr("Undo"),
		disabled = !engine.can_undo(e),
	) {
		execute(app, engine.Undo{})
	}
	x += BUTTON + GAP
	if ui.toolbar_button(
		ctx,
		ui.widget_id("Redo"),
		{x, y, BUTTON, BUTTON},
		.Redo,
		ui.tr("Redo"),
		disabled = !engine.can_redo(e),
	) {
		execute(app, engine.Redo{})
	}
	// The filter starts after the 4 points of spacing around a gap of 8.
	x += BUTTON + GAP + 8 + GAP

	// The right end, from the right: the panel toggles, then the command palette.
	right := rect.x + rect.w - 8
	inspector_rect := ui.Rect{right - BUTTON, y, BUTTON, BUTTON}
	sidebar_rect := ui.Rect{inspector_rect.x - GAP - BUTTON, y, BUTTON, BUTTON}
	palette_options := ui.Button_Options {
		kind  = .Secondary,
		name  = ui.tr("Command palette"),
		small = true,
	}
	palette_key := shortcut_hint(app, "K")
	palette_width := ui.button_width(r, palette_key, palette_options)
	palette_rect := ui.Rect{sidebar_rect.x - GAP - palette_width, y, palette_width, BUTTON}
	if ui.button(ctx, ui.widget_id("Command palette"), palette_rect, palette_key, palette_options) do open_palette(app)
	view := e.view
	if ui.toolbar_button(
		ctx,
		ui.widget_id("Toggle sidebar"),
		sidebar_rect,
		.Panel_Left,
		ui.tr("Toggle sidebar"),
		checked = view.sidebar_visible && open,
		disabled = !open,
	) {
		execute(app, engine.Toggle_Sidebar{})
	}
	if ui.toolbar_button(
		ctx,
		ui.widget_id("Toggle inspector"),
		inspector_rect,
		.Panel_Right,
		ui.tr("Toggle inspector"),
		checked = view.inspector_visible && open,
		disabled = !open,
	) {
		execute(app, engine.Toggle_Inspector{})
	}

	// The filter shares the room left with the space after it, up to its widest.
	room := palette_rect.x - GAP - x
	filter_width := clamp(room / 2, min(room, 160), FILTER_WIDEST)
	filter_field(ctx, app, {x, y, filter_width, BUTTON})
}

// The save button, in the accent colour, which says how many files it saves. Gives
// its width.
@(private = "file")
save_button :: proc(ctx: ^ui.Ui, app: ^App, at: [2]f32) -> f32 {
	e := &app.engine
	pending := len(e.edits.pending)
	saving := engine.saving(e) != nil
	label: string
	switch {
	case saving:
		label = ui.tr("Saving…")
	case pending == 0:
		label = ui.tr("Save")
	case:
		label = ui.tr_n("Save {n} file", "Save {n} files", pending)
	}
	options := ui.Button_Options {
		kind     = .Primary,
		icon     = .Save,
		disabled = !engine.can_save(e),
	}
	width := ui.button_width(ctx.renderer, label, options)
	rect := ui.Rect{at.x, at.y, width, ui.BUTTON_HEIGHT}
	if ui.button(ctx, ui.widget_id("Save"), rect, label, options) do request_save(app)
	return width
}

// Narrows the table to the tracks whose title, artist, album or file name hold the
// text typed, as it is typed. Escape empties it and gives the keyboard back; so does
// its clear button, which keeps the keyboard. Enter does nothing, as in 1.0.0.
@(private = "file")
filter_field :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	ICON :: 14
	r := ctx.renderer
	th := ctx.theme
	e := &app.engine
	hint := shortcut_hint(app, "F")
	empty := len(e.filter) == 0
	options := ui.Text_Field_Options {
		placeholder   = ui.tr("Filter by title, artist, album"),
		flags         = {.Toolbar},
		leading       = ICON + 6,
		trailing      = empty ? ui.text_width(r, hint, .Hint) + 6 : 24,
		clearable     = true,
		clear_label   = ui.tr("Clear the filter"),
		stay_on_enter = true,
	}
	result := ui.text_field(ctx, ui.widget_id("Filter"), rect, e.filter, ui.tr("Filter"), options)
	if result.changed do execute(app, engine.Filter{result.text})
	if result.cancelled do execute(app, engine.Filter{""})
	middle := rect.y + rect.h / 2
	ui.draw_icon(r, .Search, {rect.x + 8, middle - ICON / 2, ICON, ICON}, th.text_tertiary)
	if empty do ui.draw_text(r, hint, rect.x + rect.w - 8, middle, .Hint, th.text_tertiary, .Right)
}
