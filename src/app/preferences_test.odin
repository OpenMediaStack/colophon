package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen keeping its preferences in a temporary folder, as 1.0.0's tests kept
// them: the file does not exist yet, and its folder neither.
@(private = "file")
screen_keeping :: proc(s: ^Screen) -> (path, folder: string) {
	screen_init(s, {1280, 720})
	made, _ := os.make_directory_temp("", "colophon-preferences-*", context.allocator)
	folder = made
	path, _ = filepath.join({folder, "Colophon", "preferences.toml"})
	use_preferences(&s.app, path)
	return
}

@(private = "file")
widths_with_title :: proc(title: int) -> (widths: engine.Column_Widths) {
	for &width in widths do width = 150
	widths[.Title] = title
	return
}

@(private = "file")
read_kept :: proc(path: string) -> (preferences: engine.Preferences, found: bool) {
	text, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return
	return engine.preferences_from_toml(string(text)), true
}

@(test)
a_change_of_the_preferences_is_kept :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	_, kept := read_kept(path)
	testing.expect(t, !kept)
	execute(&s.app, engine.Toggle_Sidebar{})
	ui.run_frame(&s.h)
	// Not at once: a change waits to see whether others follow.
	_, early := read_kept(path)
	testing.expect(t, !early)
	ui.wait(&s.h, 0.6)
	preferences, found := read_kept(path)
	testing.expect(t, found)
	testing.expect(t, !preferences.view.sidebar_visible)
	// Written next to the file, then moved over it: nothing is left beside.
	testing.expect(t, !os.exists(fmt.tprintf("%s.new", path)))
}

@(test)
closing_the_window_keeps_its_size :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	ui.run_frame(&s.h)
	testing.expect(t, request_close(&s.app))
	remember_before_closing(&s.app)
	preferences, found := read_kept(path)
	testing.expect(t, found)
	testing.expect_value(t, preferences.view.window_size, engine.Window_Size{1280, 720})
}

@(test)
the_preferences_of_the_last_launch_are_restored :: proc(t: ^testing.T) {
	first: Screen
	path, folder := screen_keeping(&first)
	defer remove_folder(folder)
	defer delete(path)
	execute(&first.app, engine.Toggle_Inspector{})
	execute(&first.app, engine.Set_Write_Policy{{.V2_3, .Always}})
	ui.run_frame(&first.h)
	ui.wait(&first.h, 0.6)
	screen_destroy(&first)

	second: Screen
	screen_init(&second, {1280, 720})
	defer screen_destroy(&second)
	use_preferences(&second.app, path)
	testing.expect(t, !second.app.engine.view.inspector_visible)
	testing.expect_value(t, second.app.engine.edits.policy, lib.Write_Policy{.V2_3, .Always})
	// What was restored is not kept again as if it had changed.
	testing.expect_value(t, second.app.kept, engine.preferences(&second.app.engine))
	testing.expect_value(t, second.app.tried, second.app.kept)
}

@(test)
a_file_that_is_not_preferences_gives_the_defaults :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	testing.expect(t, os.make_directory_all(filepath.dir(path)) == nil)
	testing.expect(
		t,
		os.write_entire_file(path, transmute([]u8)string("this is = not [valid")) == nil,
	)
	use_preferences(&s.app, path)
	testing.expect_value(t, s.app.engine.view, engine.DEFAULT_VIEW)
	testing.expect_value(t, s.app.engine.edits.policy, lib.DEFAULT_WRITE_POLICY)
	testing.expect_value(
		t,
		engine.preferences(&s.app.engine).volume,
		engine.DEFAULT_PREFERENCES.volume,
	)
}

@(test)
nothing_is_kept_without_a_path :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1280, 720})
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Sidebar{})
	ui.run_frame(&s.h)
	ui.wait(&s.h, 0.6)
	remember_before_closing(&s.app)
	testing.expect_value(t, len(s.app.preferences_path), 0)
}

@(test)
the_preferences_live_in_a_folder_named_for_the_app :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Joined as the system joins paths: with its own separator.
	linux, _ := filepath.join(
		{"/home/me/.config", "colophon", "preferences.toml"},
		context.temp_allocator,
	)
	testing.expect_value(
		t,
		preferences_path("/home/me/.config", .Linux, context.temp_allocator),
		linux,
	)
	mac, _ := filepath.join(
		{"/Users/me/Library/Application Support", "Colophon", "preferences.toml"},
		context.temp_allocator,
	)
	testing.expect_value(
		t,
		preferences_path("/Users/me/Library/Application Support", .Mac, context.temp_allocator),
		mac,
	)
}

@(test)
the_window_opens_at_the_size_it_had_unless_one_is_asked :: proc(t: ^testing.T) {
	options, _ := parse_options({})
	testing.expect(t, !options.size_asked)
	asked, err := parse_options({"--size=1000x700"})
	testing.expect_value(t, err, Option_Error.None)
	testing.expect(t, asked.size_asked)

	saved := engine.Window_Size{1500, 900}
	testing.expect_value(t, opening_size(options, nil), DEFAULT_WINDOW_SIZE)
	testing.expect_value(t, opening_size(options, saved), [2]i32{1500, 900})
	testing.expect_value(t, opening_size(asked, saved), [2]i32{1000, 700})
}

// A size read from a file can be anything: it is kept within what a window can be,
// before it is narrowed, so that a huge one does not wrap around.
@(test)
a_saved_size_is_kept_within_what_a_window_can_be :: proc(t: ^testing.T) {
	options, _ := parse_options({})
	Case :: struct {
		saved:    engine.Window_Size,
		expected: [2]i32,
	}
	maximum := MAXIMUM_WINDOW_SIZE
	minimum := MINIMUM_WINDOW_SIZE
	cases := [?]Case {
		{{0, 0}, minimum},
		{{1, 2}, minimum},
		{{1 << 31, 1 << 31}, maximum},
		{{int(max(u32)), 3_000_000_000}, maximum},
		{{1280, int(max(u32))}, {1280, maximum.y}},
	}
	for c in cases {
		testing.expect_value(t, opening_size(options, c.saved), c.expected)
	}
}

// The size to remember is rounded, not cut, so that a fractional scale does not make
// the window a point smaller at every launch.
@(test)
the_size_of_the_window_is_rounded_when_it_is_kept :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	s.app.window_size = {1000.4, 600.6}
	remember_before_closing(&s.app)
	preferences, found := read_kept(path)
	testing.expect(t, found)
	testing.expect_value(t, preferences.view.window_size, engine.Window_Size{1000, 601})
}

@(test)
a_drag_is_kept_once_it_stops_not_at_every_frame :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	for step in 0 ..< 5 {
		execute(&s.app, engine.Resize_Columns{widths_with_title(300 + step * 10)})
		ui.wait(&s.h, 0.1)
	}
	_, early := read_kept(path)
	testing.expect(t, !early)
	testing.expect(t, s.h.ui.wake_at < max(f64))
	ui.wait(&s.h, 0.6)
	preferences, found := read_kept(path)
	testing.expect(t, found)
	if kept, resized := preferences.view.column_widths.?; testing.expect(t, resized) {
		testing.expect_value(t, kept[.Title], 340)
	}
}

// A second write replaces the first file, the move over an existing file the Windows
// CI exercises.
@(test)
a_second_change_replaces_the_file :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Sidebar{})
	ui.run_frame(&s.h)
	ui.wait(&s.h, 0.6)
	execute(&s.app, engine.Toggle_Inspector{})
	ui.run_frame(&s.h)
	ui.wait(&s.h, 0.6)
	preferences, found := read_kept(path)
	testing.expect(t, found)
	testing.expect(t, !preferences.view.sidebar_visible)
	testing.expect(t, !preferences.view.inspector_visible)
	testing.expect(t, !os.exists(fmt.tprintf("%s.new", path)))
}

@(test)
columns_and_their_order_are_restored :: proc(t: ^testing.T) {
	first: Screen
	path, folder := screen_keeping(&first)
	defer remove_folder(folder)
	defer delete(path)
	execute(&first.app, engine.Toggle_Column{.Year})
	execute(&first.app, engine.Move_Column{.Album, .Title})
	execute(&first.app, engine.Resize_Columns{widths_with_title(321)})
	ui.run_frame(&first.h)
	ui.wait(&first.h, 0.6)
	columns, order := first.app.engine.view.columns, first.app.engine.view.column_order
	screen_destroy(&first)

	second: Screen
	screen_init(&second, {1280, 720})
	defer screen_destroy(&second)
	use_preferences(&second.app, path)
	testing.expect_value(t, second.app.engine.view.columns, columns)
	testing.expect_value(t, second.app.engine.view.column_order, order)
	if restored, resized := second.app.engine.view.column_widths.?; testing.expect(t, resized) {
		testing.expect_value(t, restored[.Title], 321)
	}
}

// A closed window that never drew has no size to remember, and changed nothing.
@(test)
a_window_that_never_drew_keeps_nothing :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	s.app.window_size = {}
	remember_before_closing(&s.app)
	_, found := read_kept(path)
	testing.expect(t, !found)
}

// Preferences that cannot be written, here because the folder is a file, do not stop
// anything, and are not tried again until they change or the window closes.
@(test)
a_write_that_fails_is_not_retried_at_every_frame :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1280, 720})
	defer screen_destroy(&s)
	folder, _ := os.make_directory_temp("", "colophon-preferences-*", context.allocator)
	defer remove_folder(folder)
	blocker, _ := filepath.join({folder, "blocker"})
	defer delete(blocker)
	testing.expect(t, os.write_entire_file(blocker, transmute([]u8)string("a file")) == nil)
	path, _ := filepath.join({blocker, "preferences.toml"})
	defer delete(path)
	use_preferences(&s.app, path)
	execute(&s.app, engine.Toggle_Sidebar{})
	ui.run_frame(&s.h)
	ui.wait(&s.h, 0.6)
	changed := engine.preferences(&s.app.engine)
	testing.expect_value(t, s.app.tried, changed)
	testing.expect(t, s.app.kept != changed)
	// Nothing more is due: no frame is asked for.
	s.h.ui.wake_at = max(f64)
	ui.wait(&s.h, 5)
	testing.expect_value(t, s.h.ui.wake_at, max(f64))
	remember_before_closing(&s.app)
	testing.expect(t, s.app.kept != changed)
}

@(test)
a_file_too_large_to_be_preferences_is_not_read :: proc(t: ^testing.T) {
	s: Screen
	path, folder := screen_keeping(&s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	testing.expect(t, os.make_directory_all(filepath.dir(path)) == nil)
	// A valid file, padded with comments past the limit.
	text := fmt.tprintf("[view]\nsidebar = false\n%s", strings_repeat("# padding\n", 150_000))
	testing.expect(t, os.write_entire_file(path, transmute([]u8)text) == nil)
	use_preferences(&s.app, path)
	testing.expect_value(t, s.app.engine.view, engine.DEFAULT_VIEW)
}

@(private = "file")
strings_repeat :: proc(text: string, count: int) -> string {
	return strings.repeat(text, count, context.temp_allocator)
}
