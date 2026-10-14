package main

import "core:strings"

import "../engine"
import ui "../ui"

// How long a toast stays, in seconds: a success goes on its own, an error waits to be
// read, as 1.0.0's.
@(private = "file")
SUCCESS_TOAST :: 4.0
@(private = "file")
ERROR_TOAST :: 10.0

// A toast shown until its time comes or the user closes it. The message is the app's.
Notice :: struct {
	kind:    ui.Toast_Kind,
	message: string,
	action:  Maybe(Notice_Action),
	until:   f64,
}

// What a toast's action does.
Notice_Action :: enum u8 {
	// Saves again the files a save could not write.
	Retry_Save,
}

// Shows a toast in place of the one shown, from now (the frame's time) for as long as
// its kind stays. The message is copied.
notify :: proc(
	app: ^App,
	kind: ui.Toast_Kind,
	message: string,
	action: Maybe(Notice_Action),
	now: f64,
) {
	forget_notice(app)
	stays := kind == .Success ? SUCCESS_TOAST : ERROR_TOAST
	app.notice = Notice{kind, strings.clone(message, app.engine.allocator), action, now + stays}
}

forget_notice :: proc(app: ^App) {
	if notice, shown := app.notice.?; shown do delete(notice.message, app.engine.allocator)
	app.notice = nil
}

// The toast over the window, until its time; its action, and its close button.
toasts :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	notice, shown := app.notice.?
	if !shown do return
	if ctx.input.time >= notice.until {
		forget_notice(app)
		return
	}
	ui.wake_at(ctx, notice.until)
	action_label := ""
	if action, has := notice.action.?; has {
		switch action {
		case .Retry_Save:
			action_label = ui.tr("Retry")
		}
	}
	id := ui.widget_id("Toast")
	switch ui.toast(ctx, id, window, notice.kind, notice.message, action_label) {
	case .None:
	case .Acted:
		if action, has := notice.action.?; has && action == .Retry_Save do execute(app, engine.Save{})
		forget_notice(app)
	case .Closed:
		forget_notice(app)
	}
}
