package engine_tests

import "core:testing"

import "../../engine"

@(private = "file")
changed :: proc() -> (p: engine.Preferences) {
	p = engine.DEFAULT_PREFERENCES
	p.view.sidebar_visible = false
	p.view.columns = {.Artist, .Tags}
	p.view.column_widths = #partial engine.Column_Widths {
		.Title  = 240,
		.Artist = 120,
	}
	p.view.column_order = engine.order_starting_with({.Album, .Title})
	p.view.developer_mode = true
	p.view.window_size = engine.Window_Size{1440, 900}
	p.volume = 35
	p.writing = {.V2_3, .Never}
	return
}

@(test)
preferences_read_back_as_written :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for p in ([]engine.Preferences{changed(), engine.DEFAULT_PREFERENCES}) {
		text := engine.preferences_to_toml(p, context.temp_allocator)
		testing.expect_value(t, engine.preferences_from_toml(text), p)
	}
}

@(test)
what_the_file_lacks_keeps_its_default :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	want := engine.DEFAULT_PREFERENCES
	want.view.sidebar_visible = false
	testing.expect_value(t, engine.preferences_from_toml("sidebar = false\n"), want)
}

@(test)
a_file_that_is_not_one_gives_the_defaults :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for text in ([]string{"sidebar = [", "volume = \"loud\"", "volume = 300", "[window]\nwidth = 1440\n"}) {
		testing.expect_value(t, engine.preferences_from_toml(text), engine.DEFAULT_PREFERENCES)
	}
}

@(test)
unknown_columns_are_left_out_and_the_volume_kept_in_range :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := engine.preferences_from_toml(
		"columns = [\"album\", \"mood\"]\ncolumn_order = [\"mood\", \"year\"]\nvolume = 250\n",
	)
	testing.expect_value(t, p.view.columns, engine.Columns{.Album})
	testing.expect_value(t, p.volume, 100)
	testing.expect_value(t, p.view.column_order[0], engine.Table_Column.Year)
}

// What 1.0.0 wrote: Colophon reads it, and writes the same text back.
@(test)
the_file_of_1_0_reads_and_writes_back_the_same :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	text := `sidebar = false
inspector = true
columns = ["artist", "tags"]
volume = 35
id3v2 = "2.3"
id3v1 = "never"
developer_mode = true
column_order = ["album", "title", "artist", "year", "genre", "time", "bitrate", "tags", "file", "folder"]

[window]
width = 1440
height = 900

[column_widths]
title = 240
artist = 120
album = 0
year = 0
genre = 0
time = 0
bitrate = 0
tags = 0
file = 0
folder = 0
`
	p := engine.preferences_from_toml(text)
	testing.expect_value(t, p, changed())
	testing.expect_value(t, engine.preferences_to_toml(p, context.temp_allocator), text)
}

@(test)
a_window_written_inline_or_dotted_reads_as_1_0_read_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for text in ([]string{"window = { width = 1440, height = 900 }\nratio = 1.5\n", "window.width = 1440\nwindow.height = 900\n[[recent]]\npath = \"a\"\n"}) {
		p := engine.preferences_from_toml(text)
		testing.expectf(t, p.view.window_size == engine.Window_Size{1440, 900}, "%q: %v", text, p)
	}
}

@(test)
values_the_file_cannot_hold_are_kept_within_its_range :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	widths := #partial engine.Column_Widths {
		.Title = -5,
	}
	engine.execute(&e, engine.Resize_Columns{widths})
	engine.execute(&e, engine.Resize_Window{{-1, 1 << 40}})
	p := engine.preferences(&e)
	p.volume = 300
	read := engine.preferences_from_toml(engine.preferences_to_toml(p, context.temp_allocator))
	read_widths, resized := read.view.column_widths.?
	testing.expect(t, resized && read_widths[.Title] == 0)
	testing.expect_value(t, read.view.window_size, engine.Window_Size{0, int(max(u32))})
	testing.expect_value(t, read.volume, 100)
}

@(test)
view_commands_keep_the_ids_of_1_0 :: proc(t: ^testing.T) {
	ids := [?][2]string {
		{engine.command_id(engine.Toggle_Sidebar{}), "view.toggle_sidebar"},
		{engine.command_id(engine.Toggle_Inspector{}), "view.toggle_inspector"},
		{engine.command_id(engine.Toggle_Developer_Mode{}), "view.toggle_developer_mode"},
		{engine.command_id(engine.Toggle_Column{}), "view.toggle_column"},
		{engine.command_id(engine.Resize_Columns{}), "view.resize_columns"},
		{engine.command_id(engine.Reset_Columns{}), "view.reset_columns"},
		{engine.command_id(engine.Move_Column{}), "view.move_column"},
		{engine.command_id(engine.Set_Write_Policy{}), "settings.write_policy"},
		{engine.command_id(engine.Set_Volume{}), "playback.volume"},
		{engine.command_id(engine.Resize_Window{}), "view.resize_window"},
	}
	for id in ids do testing.expect_value(t, id[0], id[1])
}
