package main

import "core:os"
import "core:strings"

import "../engine"
import lib "../library"
import ui "../ui"

// Colophon's state above the engine: what the screens need between frames that the
// engine does not already know. Make it with app_init, free it with app_destroy.
App :: struct {
	engine:   engine.Engine,
	dialogs:  Dialogs,
	drop:     Drop,
	// What the track table keeps between frames: its scroll, a drag of a column.
	table:    ui.Table_State,
	sidebar:  Sidebar,
	// How many commands ran: a frame in which one ran is followed by another at once,
	// so that what it changed shows.
	commands: int,
	// Whose conventions the screens follow, the shortcuts they write and the order of
	// a dialog's buttons: the system's, unless a test pins one so that its captures
	// are the same everywhere.
	platform: ui.Platform,
	// The user's home folder, without a trailing separator, which the table shows as
	// a tilde; empty when the system does not say.
	home:     string,
}

// Runs a command of the engine, counting it for the loop.
execute :: proc(app: ^App, command: engine.Command) {
	app.commands += 1
	engine.execute(&app.engine, command)
}

// How the app asks the user for folders and files: the system's dialogs, which the
// window shows and which answer later from the loop, or a test's answers. Both answer
// through the engine's Open_Folder and Open_Files commands, on the UI thread.
Dialogs :: struct {
	data:        rawptr,
	open_folder: proc(app: ^App, data: rawptr),
	open_files:  proc(app: ^App, data: rawptr),
}

// Files dragged over the window, until they are dropped or the drag leaves.
Drop :: struct {
	// Something is dragged over the window: the drop target shows.
	hovering: bool,
	// The paths dropped so far, taken in together when the drop completes.
	paths:    [dynamic]string,
}

// wake is called from the engine's threads when they have news for the loop.
app_init :: proc(app: ^App, wake := lib.Wake{}, allocator := context.allocator) {
	engine.init(&app.engine, wake, allocator)
	app.platform = ui.PLATFORM
	app.drop.paths = make([dynamic]string, allocator)
	home := os.get_env("HOME", context.temp_allocator)
	app.home = strings.clone(strings.trim_right(home, "/\\"), allocator)
}

app_destroy :: proc(app: ^App) {
	delete(app.home, app.engine.allocator)
	destroy_sidebar(&app.sidebar)
	forget_dropped(app)
	delete(app.drop.paths)
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

// Asks the user for a folder to open.
open_folder :: proc(app: ^App) {
	if app.dialogs.open_folder != nil do app.dialogs.open_folder(app, app.dialogs.data)
}

// Asks the user for files to open.
open_files :: proc(app: ^App) {
	if app.dialogs.open_files != nil do app.dialogs.open_files(app, app.dialogs.data)
}

// A drag of files came over the window: the drop target shows.
drop_begin :: proc(app: ^App) {
	app.drop.hovering = true
}

// A file of the drag was dropped; the others may follow.
drop_file :: proc(app: ^App, path: string) {
	append(&app.drop.paths, strings.clone(path, app.engine.allocator))
}

// The drag ended, dropped or gone: what was dropped is opened together, folders and
// audio files alike. Anything else is left alone; an image dropped on the inspector
// becomes a cover with slice 32.
drop_end :: proc(app: ^App) {
	app.drop.hovering = false
	defer forget_dropped(app)
	files := make([dynamic]string, context.temp_allocator)
	for path in app.drop.paths {
		switch {
		case os.is_directory(path):
			execute(app, engine.Open_Folder{path})
		case lib.is_audio_file(path):
			append(&files, path)
		}
	}
	if len(files) > 0 do execute(app, engine.Open_Files{files[:]})
}

@(private = "file")
forget_dropped :: proc(app: ^App) {
	for path in app.drop.paths do delete(path, app.engine.allocator)
	clear(&app.drop.paths)
}

// How a shortcut is written for the user: Command on macOS, Control elsewhere.
shortcut_hint :: proc(app: ^App, key: string) -> string {
	return app.platform == .Mac ? ui.fill("⌘{}", key) : ui.fill("Ctrl+{}", key)
}
