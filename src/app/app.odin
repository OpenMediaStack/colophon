package main

import "core:os"
import "core:strings"

import "../engine"
import lib "../library"
import ui "../ui"

// What the engine remembers between launches, named here where the App's own field
// called engine hides the package.
Preferences :: engine.Preferences

// Colophon's state above the engine: what the screens need between frames that the
// engine does not already know. Make it with app_init, free it with app_destroy.
App :: struct {
	engine:           engine.Engine,
	dialogs:          Dialogs,
	drop:             Drop,
	// What the track table keeps between frames: its scroll, a drag of a column.
	table:            ui.Table_State,
	// What it keeps beside that: the cell edited, a click waiting to shrink the
	// selection, the track whose menu is open.
	tracks:           Tracks,
	genres:           Genres,
	warnings:         Warnings_Cache,
	thumbnails:       Thumbnails,
	waveform:         Waveform_State,
	palette:          Palette,
	settings_open:    bool,
	about:            About,
	// Where the preferences are kept, empty to keep none, what was last written, what
	// was last tried (a write that fails is not retried at every frame), and what was
	// last seen changing, since when.
	preferences_path: string,
	kept:             Preferences,
	tried:            Preferences,
	seen:             Preferences,
	seen_at:          f64,
	// The window's size in points, as the last frame drew it.
	window_size:      [2]f32,
	// A removal waiting for the user's answer.
	removal:          Maybe(Removal),
	// The cover read for the save dialog, until it answers.
	cover_to_write:   Maybe(lib.Cover),
	sidebar:          Sidebar,
	inspector:        Inspector,
	// How many commands ran: a frame in which one ran is followed by another at once,
	// so that what it changed shows.
	commands:         int,
	// Whose conventions the screens follow, the shortcuts they write and the order of
	// a dialog's buttons: the system's, unless a test pins one so that its captures
	// are the same everywhere.
	platform:         ui.Platform,
	// Shown by About; a capture pins it so that a release does not change them.
	version:          string,
	// The user's home folder, without a trailing separator, which the table shows as
	// a tilde; empty when the system does not say.
	home:             string,
	// The toast shown, if one is.
	notice:           Maybe(Notice),
	// How many saves had ended when the last one was told of.
	shown_saves:      int,
	// How many failed plays the app has told.
	told_failures:    int,
	// What the window does about quitting with changes that are not saved.
	departure:        Maybe(Departure),
	// A choice made in the system's menu bar, waiting for the frame that runs it, and
	// the event type its choices travel in (nil: no system menu bar, as in tests and
	// screenshots).
	menu_choice:      Maybe(int),
	menu_event_type:  Maybe(u32),
	native_menu:      Native_Menu,
	// The window closes: the loop ends after the frame.
	quit:             bool,
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
	// Asks for an image, which take_image makes the selected tracks' cover.
	pick_image:  proc(app: ^App, data: rawptr),
	// Asks where to write the cover, suggesting a path, which extract_cover_to writes.
	save_cover:  proc(app: ^App, data: rawptr, suggested: string),
	// Shows a file in the system's file manager.
	reveal:      proc(app: ^App, data: rawptr, path: string),
	// Opens an address in the browser.
	open_url:    proc(app: ^App, data: rawptr, url: string),
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
	init_thumbnails(&app.thumbnails, wake, allocator)
	init_waveform_state(&app.waveform, wake, allocator)
	app.platform = ui.PLATFORM
	app.version = VERSION
	init_inspector(&app.inspector)
	app.drop.paths = make([dynamic]string, allocator)
	home := os.get_env("HOME", context.temp_allocator)
	app.home = strings.clone(strings.trim_right(home, "/\\"), allocator)
}

app_destroy :: proc(app: ^App) {
	delete(app.home, app.engine.allocator)
	destroy_sidebar(&app.sidebar)
	destroy_native_menu(&app.native_menu)
	destroy_tracks(&app.tracks)
	forget_notice(app)
	delete(app.genres.list, app.engine.allocator)
	delete(app.warnings.found)
	forget_cover_to_write(app)
	forget_layout(app)
	forget_removal(app)
	delete(app.preferences_path, app.engine.allocator)
	destroy_thumbnails(&app.thumbnails)
	destroy_waveform_state(&app.waveform)
	delete(app.palette.query, app.engine.allocator)
	forget_dropped(app)
	delete(app.drop.paths)
	engine.destroy(&app.engine)
}

// Draws the main screen in the window's area: a frame of the harness and of the loop.
app_frame :: proc(ctx: ^ui.Ui, data: rawptr) {
	main_screen(ctx, (^App)(data), ctx.viewport)
}

// The genres of the library, which the genre fields of the inspector and the table
// suggest, made again when the library changes: they come from the files' tags, and a
// genre only typed so far is not one of them.
Genres :: struct {
	list:             []string,
	made:             bool,
	library_revision: u64,
}

// The genres of the library, in alphabetical order, valid until the library changes.
genres :: proc(app: ^App) -> []string {
	g := &app.genres
	e := &app.engine
	if !g.made || g.library_revision != e.library_revision {
		delete(g.list, e.allocator)
		g.list = engine.genres(e, e.allocator)
		g.made, g.library_revision = true, e.library_revision
	}
	return g.list
}

// What looks wrong in the tracks beside the rest of their albums, for the table's
// marks and the inspector's warnings, made again when the library or the edits
// change: the engine walks the whole library for them, 4 to 6 ms for 10,000 tracks.
Warnings_Cache :: struct {
	found:    map[engine.Track_Id]engine.Warnings,
	made:     bool,
	revision: u64,
}

// The tracks whose tags look wrong, with what does. The cache owns the map, which is
// valid until the next command, or the next poll with a scan's or a save's news.
warnings :: proc(app: ^App) -> map[engine.Track_Id]engine.Warnings {
	w := &app.warnings
	e := &app.engine
	if !w.made || w.revision != e.revision {
		delete(w.found)
		w.found = engine.warnings(e, e.allocator)
		w.made, w.revision = true, e.revision
	}
	return w.found
}

// What looks wrong in any of the selected tracks.
selection_warnings :: proc(app: ^App) -> (found: engine.Warnings) {
	all := warnings(app)
	for track in app.engine.selection.tracks do found += all[track]
	return
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

// Asks the user for an image to make the selected tracks' cover.
pick_image :: proc(app: ^App) {
	if app.dialogs.pick_image != nil do app.dialogs.pick_image(app, app.dialogs.data)
}

// Asks the user where to write the selected tracks' cover, suggesting a path.
pick_save :: proc(app: ^App, suggested: string) {
	if app.dialogs.save_cover != nil do app.dialogs.save_cover(app, app.dialogs.data, suggested)
}

// Shows a file in the system's file manager.
reveal_file :: proc(app: ^App, path: string) {
	if app.dialogs.reveal != nil do app.dialogs.reveal(app, app.dialogs.data, path)
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
// audio files alike. Without any, an image becomes the cover of the selected tracks,
// as 1.0.0 took it; anything else is left alone. now is the frame's time, for a
// toast.
drop_end :: proc(app: ^App, now: f64) {
	app.drop.hovering = false
	defer forget_dropped(app)
	files := make([dynamic]string, context.temp_allocator)
	opened := false
	for path in app.drop.paths {
		switch {
		case os.is_directory(path):
			execute(app, engine.Open_Folder{path})
			opened = true
		case lib.is_audio_file(path):
			append(&files, path)
		}
	}
	if len(files) > 0 do execute(app, engine.Open_Files{files[:]})
	if opened || len(files) > 0 do return
	if _, tracks := engine.inspect(&app.engine).(engine.Summary); !tracks do return
	for path in app.drop.paths do if is_image_file(path) {
		take_image(app, path, now)
		return
	}
}

@(private = "file")
forget_dropped :: proc(app: ^App) {
	for path in app.drop.paths do delete(path, app.engine.allocator)
	clear(&app.drop.paths)
}

// How a shortcut is written for the user: Command on macOS, with the symbols of the
// Finder for Shift and Option, Control elsewhere, with their names.
shortcut_hint :: proc(app: ^App, key: string, shift := false, alt := false) -> string {
	if app.platform == .Mac {
		return ui.fill("{}{}⌘{}", alt ? "⌥" : "", shift ? "⇧" : "", key)
	}
	return ui.fill("Ctrl+{}{}{}", alt ? "Alt+" : "", shift ? "Shift+" : "", key)
}
