package main

import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../engine"
import ui "../ui"

// How long the preferences stay still before they are written: dragging a column's
// edge changes them at every frame.
@(private = "file")
KEEP_DELAY :: 0.5
// A preferences file larger than this is not one: it is not read.
@(private = "file")
MAX_PREFERENCES_BYTES :: 1 << 20

// Where Colophon keeps its preferences: the preferences.toml of a folder named for the
// app, in lowercase on Linux, inside config_dir, the system's folder for application
// settings, as 1.0.0 did. Allocated with allocator.
preferences_path :: proc(
	config_dir: string,
	platform: ui.Platform,
	allocator := context.allocator,
) -> string {
	folder := platform == .Linux ? "colophon" : "Colophon"
	path, _ := filepath.join({config_dir, folder, "preferences.toml"}, allocator)
	return path
}

// Starts from the preferences kept at path, or the defaults when there are none or the
// file is not one, and keeps them there from now on. The path is copied.
use_preferences :: proc(app: ^App, path: string) {
	delete(app.preferences_path, app.engine.allocator)
	app.preferences_path = strings.clone(path, app.engine.allocator)
	preferences := engine.DEFAULT_PREFERENCES
	if info, err := os.stat(path, context.temp_allocator);
	   err == nil && info.size <= MAX_PREFERENCES_BYTES {
		if text, read_err := os.read_entire_file(path, context.temp_allocator); read_err == nil {
			preferences = engine.preferences_from_toml(string(text))
		}
	}
	engine.restore(&app.engine, preferences)
	restored := engine.preferences(&app.engine)
	app.kept, app.tried, app.seen = restored, restored, restored
}

// Writes the preferences once they have stopped changing for a moment. Without a path,
// or without a folder to write in, Colophon works the same: it only forgets them. A
// write that fails is not tried again until the preferences change, or the window
// closes.
keep_preferences :: proc(ctx: ^ui.Ui, app: ^App) {
	if len(app.preferences_path) == 0 do return
	now := engine.preferences(&app.engine)
	if now == app.tried do return
	if now != app.seen do app.seen, app.seen_at = now, ctx.input.time
	due := app.seen_at + KEEP_DELAY
	if ctx.input.time < due {
		ui.wake_at(ctx, due)
		return
	}
	app.tried = now
	if write_preferences(app.preferences_path, now) do app.kept = now
}

// Writes preferences next to their file, then moves them over it, so that quitting
// halfway never leaves half a file. False when it could not.
@(private = "file")
write_preferences :: proc(path: string, preferences: engine.Preferences) -> (written: bool) {
	if err := os.make_directory_all(filepath.dir(path)); err != nil && err != .Exist do return false
	text := engine.preferences_to_toml(preferences, context.temp_allocator)
	temporary := strings.concatenate({path, ".new"}, context.temp_allocator)
	defer if !written {
		_ = os.remove(temporary)
	}
	if os.write_entire_file(temporary, transmute([]u8)text) != nil do return false
	return os.rename(temporary, path) == nil
}

// What the app does as the window closes: remembers its size, to open at it next time,
// and writes the preferences that are not yet.
remember_before_closing :: proc(app: ^App) {
	if size := app.window_size; size.x > 0 && size.y > 0 {
		execute(app, engine.Resize_Window{{int(math.round(size.x)), int(math.round(size.y))}})
	}
	if len(app.preferences_path) == 0 do return
	now := engine.preferences(&app.engine)
	if now == app.kept do return
	app.tried = now
	if write_preferences(app.preferences_path, now) do app.kept = now
}

// The size the window opens at: the one it had when it last closed, unless a size was
// asked for, kept within what a window can be.
opening_size :: proc(options: Options, saved: Maybe(engine.Window_Size)) -> [2]i32 {
	size, had := saved.?
	if !had || options.size_asked do return options.window_size
	minimum, maximum := MINIMUM_WINDOW_SIZE, MAXIMUM_WINDOW_SIZE
	return {
		i32(clamp(size.width, int(minimum.x), int(maximum.x))),
		i32(clamp(size.height, int(minimum.y), int(maximum.y))),
	}
}
