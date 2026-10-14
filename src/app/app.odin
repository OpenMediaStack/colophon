package main

import "../engine"
import lib "../library"
import ui "../ui"

// Colophon's state above the engine: what the screens need between frames that the
// engine does not already know. Make it with app_init, free it with app_destroy.
App :: struct {
	engine:   engine.Engine,
	// How many commands ran: a frame in which one ran is followed by another at once,
	// so that what it changed shows.
	commands: int,
	// Whose conventions the screens follow, the shortcuts they write and the order of
	// a dialog's buttons: the system's, unless a test pins one so that its captures
	// are the same everywhere.
	platform: ui.Platform,
}

// Runs a command of the engine, counting it for the loop.
execute :: proc(app: ^App, command: engine.Command) {
	app.commands += 1
	engine.execute(&app.engine, command)
}

// wake is called from the engine's threads when they have news for the loop.
app_init :: proc(app: ^App, wake := lib.Wake{}, allocator := context.allocator) {
	engine.init(&app.engine, wake, allocator)
	app.platform = ui.PLATFORM
}

app_destroy :: proc(app: ^App) {
	engine.destroy(&app.engine)
}

// Draws the main screen in the window's area: a frame of the harness and of the loop.
app_frame :: proc(ctx: ^ui.Ui, data: rawptr) {
	main_screen(ctx, (^App)(data), ctx.viewport)
}

// Something was opened: a folder, or files. The panels wait for it.
folder_open :: proc(app: ^App) -> bool {
	return len(app.engine.library.roots) > 0
}

// Asks the user for a folder to open. The folder dialog comes with slice 29.
open_folder :: proc(app: ^App) {
	_ = app
}

// How a shortcut is written for the user: Command on macOS, Control elsewhere.
shortcut_hint :: proc(app: ^App, key: string) -> string {
	return app.platform == .Mac ? ui.fill("⌘{}", key) : ui.fill("Ctrl+{}", key)
}
