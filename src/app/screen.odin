package main

import ui "../ui"

// The brief's sizes: the toolbar and the status bar across the window, the panels on
// each side of the centre column.
TOOLBAR_HEIGHT :: 40
STATUS_BAR_HEIGHT :: 24
SIDEBAR_WIDTH :: 220
INSPECTOR_WIDTH :: 320
// The sidebar gives way when the centre column would get narrower than this.
CENTRE_MIN_WIDTH :: 560

// Where each region of the window goes, and which panels show. The regions are one
// point apart, for the line between them.
Layout :: struct {
	toolbar, sidebar, centre, inspector, status: ui.Rect,
	sidebar_shown, inspector_shown:              bool,
}

// The panels wait for something open. The sidebar gives way on its own when the centre
// column would get too narrow; the inspector never does, since hiding it in the middle
// of an edit would be confusing: only the user hides it.
layout_of :: proc(app: ^App, window: ui.Rect) -> (l: Layout) {
	open := folder_open(app)
	view := app.engine.view
	l.inspector_shown = open && view.inspector_visible
	inspector_width: f32 = l.inspector_shown ? INSPECTOR_WIDTH : 0
	l.sidebar_shown =
		open &&
		view.sidebar_visible &&
		window.w - SIDEBAR_WIDTH - inspector_width >= CENTRE_MIN_WIDTH
	l.toolbar = {window.x, window.y, window.w, TOOLBAR_HEIGHT}
	l.status = {window.x, window.y + window.h - STATUS_BAR_HEIGHT, window.w, STATUS_BAR_HEIGHT}
	top := l.toolbar.y + l.toolbar.h + 1
	height := max(l.status.y - 1 - top, 0)
	left := window.x
	if l.sidebar_shown {
		l.sidebar = {left, top, SIDEBAR_WIDTH, height}
		left += SIDEBAR_WIDTH + 1
	}
	right := window.x + window.w
	if l.inspector_shown {
		right -= INSPECTOR_WIDTH
		l.inspector = {right, top, INSPECTOR_WIDTH, height}
		right -= 1
	}
	l.centre = {left, top, max(right - left, 0), height}
	return
}

// The main screen in window: the toolbar, the panels around the centre column, the
// status bar, and the shortcuts no widget took.
main_screen :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	th := ctx.theme
	follow_save(app, ctx.input.time)
	poll_thumbnails(ctx, app)
	l := layout_of(app, window)
	// The lines between the regions: the window shows through the point between them.
	ui.fill_rect(ctx.renderer, window, th.border_subtle)
	toolbar(ctx, app, l.toolbar)
	// The toolbar's toggles change the view: the panels follow in the same frame.
	l = layout_of(app, window)
	if l.sidebar_shown do sidebar(ctx, app, l.sidebar)
	if folder_open(app) {
		track_table(ctx, app, l.centre)
	} else {
		empty_state(ctx, app, l.centre)
	}
	if l.inspector_shown do inspector(ctx, app, l.inspector)
	status_bar(ctx, app, l.status)
	if app.drop.hovering do drop_target(ctx, window)
	toasts(ctx, app, window)
	palette(ctx, app, window)
	settings_dialog(ctx, app, window)
	removal_dialog(ctx, app, window)
	unsaved_changes(ctx, app, window)
	shortcuts(ctx, app)
}

// Over the whole window while files are dragged over it: a scrim, a frame in the
// accent colour, and what a drop does.
@(private = "file")
drop_target :: proc(ctx: ^ui.Ui, window: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	previous := ui.set_layer(r, .Top)
	defer ui.set_layer(r, previous)
	ui.block_mouse(ctx, window)
	ui.fill_rect(r, window, th.scrim)
	ui.stroke_rect(r, ui.rect_inset(window, 12, 12), th.accent, 8, 2)
	label := ui.tr("Drop to open these folders and files")
	width := ui.text_width(r, label, .Title) + 32
	box := ui.centered(window, width, 44)
	ui.draw_shadow(r, box, 8, 8, 24, th.shadow_menu)
	ui.fill_rect(r, box, th.surface_2, 8)
	ui.draw_text(r, label, box.x + 16, box.y + box.h / 2, .Title, th.text_primary)
	ui.declare(ctx, {id = ui.widget_id("Drop target"), role = .Label, label = label, rect = box})
}
