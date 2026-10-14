package main

import "core:fmt"
import "core:strings"

import "../engine"
import ui "../ui"

// The bottom bar: what the library holds, the reading of a folder, the files it could
// not read, the changes waiting to be saved, and the developer mode's marker.
status_bar :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	GAP :: 16
	r := ctx.renderer
	th := ctx.theme
	e := &app.engine
	ui.fill_rect(r, rect, th.surface_0)
	middle := rect.y + rect.h / 2
	x := rect.x + 12
	x += note(ctx, status_text(e), x, rect, th.text_secondary, 0) + GAP
	if e.library.status == .Scanning {
		options := ui.Button_Options {
			kind    = .Secondary,
			padding = 8,
		}
		label := ui.tr("Stop")
		stop := ui.Rect{x, middle - 10, ui.button_width(r, label, options), 20}
		if ui.button(ctx, ui.widget_id("Stop"), stop, label, options) do engine.execute(e, engine.Stop_Scan{})
		x += stop.w + GAP
	}
	if progress, saving := engine.saving(e).?; saving {
		done := fmt.tprint(progress.done)
		total := fmt.tprint(progress.total)
		text := ui.fill(ui.tr("Saving… {} of {}"), done, total)
		x += note(ctx, text, x, rect, th.text_secondary, 1) + GAP
	}
	if failures := len(e.save_failures); failures > 0 {
		text := ui.tr_n("{n} file could not be saved", "{n} files could not be saved", failures)
		x += note(ctx, text, x, rect, th.error, 2) + GAP
	}
	if pending := len(e.edits.pending); pending > 0 && engine.saving(e) == nil {
		text := ui.tr_n("{n} file with unsaved changes", "{n} files with unsaved changes", pending)
		x += note(ctx, text, x, rect, th.accent_text, 3) + GAP
	}
	if unreadable := len(e.library.unreadable); unreadable > 0 {
		text := ui.tr_n("{n} file could not be read", "{n} files could not be read", unreadable)
		x += note(ctx, text, x, rect, th.error, 4) + GAP
	}
	// Developer mode is on: its marker makes it impossible to forget.
	if e.view.developer_mode {
		label := ui.tr("Developer mode")
		w := ui.text_width(r, label, .Numeric) + 12
		box := ui.Rect{rect.x + rect.w - 12 - w, middle - 9, w, 18}
		ui.stroke_rect(r, box, th.border_strong, 3)
		ui.draw_text(r, label, box.x + 6, middle, .Numeric, th.text_tertiary)
		ui.declare(
			ctx,
			{id = ui.widget_id("Developer mode"), role = .Label, label = label, rect = box},
		)
	}
}

// One of the status bar's texts, declared for assistive technologies and tests. Gives
// its width.
@(private = "file")
note :: proc(ctx: ^ui.Ui, text: string, x: f32, bar: ui.Rect, color: ui.Color, index: int) -> f32 {
	width := ui.draw_text(ctx.renderer, text, x, bar.y + bar.h / 2, .Small, color)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Status", index),
			role = .Label,
			label = text,
			rect = {x, bar.y, width, bar.h},
		},
	)
	return width
}

// What the library holds, as the status bar says it: the reading in progress, or the
// tracks found, and how many are selected. Temporary.
@(private = "file")
status_text :: proc(e: ^engine.Engine) -> string {
	count := len(e.library.tracks)
	text: string
	switch e.library.status {
	case .Idle:
		text = ui.tr("No folder open")
	case .Scanning:
		text = ui.tr_n("Reading… {n} track found", "Reading… {n} tracks found", count)
	case .Stopped:
		text = ui.tr_n("Reading stopped, {n} track", "Reading stopped, {n} tracks", count)
	case .Failed:
		text = ui.tr("Could not read this folder")
	case .Completed:
		text = ui.tr_n("{n} track", "{n} tracks", count)
	}
	if selected := len(e.selection.tracks); selected > 0 {
		chosen := ui.tr_n("{n} selected", "{n} selected", selected)
		text = strings.concatenate({text, " · ", chosen}, context.temp_allocator)
	}
	return text
}
