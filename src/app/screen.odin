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
	l := layout_of(app, window)
	// The lines between the regions: the window shows through the point between them.
	ui.fill_rect(ctx.renderer, window, th.border_subtle)
	toolbar(ctx, app, l.toolbar)
	// The toolbar's toggles change the view: the panels follow in the same frame.
	l = layout_of(app, window)
	if l.sidebar_shown do sidebar(ctx, app, l.sidebar)
	if folder_open(app) {
		tracks(ctx, app, l.centre)
	} else {
		empty_state(ctx, app, l.centre)
	}
	if l.inspector_shown do inspector(ctx, app, l.inspector)
	status_bar(ctx, app, l.status)
	shortcuts(ctx, app)
}

// The sidebar's panel. Its sources come with slice 31.
@(private = "file")
sidebar :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	_ = app
	ui.fill_rect(ctx.renderer, rect, ctx.theme.surface_0)
	ui.declare(
		ctx,
		{id = ui.widget_id("Sidebar"), role = .Group, label = ui.tr("Sidebar"), rect = rect},
	)
}

// The inspector's panel. Its fields come with slice 32.
@(private = "file")
inspector :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	_ = app
	ui.fill_rect(ctx.renderer, rect, ctx.theme.surface_1)
	ui.declare(
		ctx,
		{id = ui.widget_id("Inspector"), role = .Group, label = ui.tr("Inspector"), rect = rect},
	)
}

// The centre column once something is open. The track table comes with slice 30.
@(private = "file")
tracks :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	_ = app
	ui.fill_rect(ctx.renderer, rect, ctx.theme.surface_1)
}
