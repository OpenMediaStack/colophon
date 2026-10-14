package main

import "core:fmt"
import "core:testing"

import "../engine"
import ui "../ui"

// The main screen over three tracks, all selected, as 1.0.0's palette tests.
@(private = "file")
screen_with_tracks :: proc(
	t: ^testing.T,
	s: ^Screen,
	kind := ui.Theme_Kind.Dark,
) -> (
	folder: string,
) {
	screen_init(s, {1440, 900}, kind)
	folder = folder_with_fixtures(
		t,
		{
			{"v23_full.mp3", "02 Glass Avenue.mp3"},
			{"v24_full.mp3", "03 Midnight Lithography.mp3"},
			{"v23_v1_long_title.mp3", "04 Paper Satellites.mp3"},
		},
	)
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "3 tracks")
	execute(&s.app, engine.Select_All{})
	ui.run_frame(&s.h)
	return
}

@(private = "file")
open_the_palette :: proc(t: ^testing.T, s: ^Screen) {
	testing.expect(t, ui.click(&s.h, "Command palette"))
	ui.run_frame(&s.h)
	testing.expect(t, s.app.palette.open)
}

@(test)
a_command_typed_runs_with_return :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "sidebar")
	testing.expect(t, shows(&s, "Hide Sidebar"))
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.palette.open)
	testing.expect(t, !s.app.engine.view.sidebar_visible)
}

@(test)
the_arrow_keys_choose_among_the_commands :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "inspector")
	ui.press_key(&s.h, .Down)
	ui.press_key(&s.h, .Up)
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.engine.view.inspector_visible)
}

@(test)
a_click_runs_a_command :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "tags col")
	testing.expect(t, ui.click(&s.h, "Show the Tags column (ID3 versions)"))
	ui.run_frame(&s.h)
	testing.expect(t, .Tags in s.app.engine.view.columns)
	testing.expect(t, !s.app.palette.open)
}

@(test)
escape_closes_the_palette_and_runs_nothing :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "sidebar")
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.palette.open)
	testing.expect(t, s.app.engine.view.sidebar_visible)
}

@(test)
commands_that_cannot_run_are_not_offered :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "id3v2.4")
	testing.expect(t, !shows(&s, "Write ID3v2.4 to the selected files"))
	testing.expect(t, shows(&s, "No command holds “id3v2.4”"))
}

@(test)
the_shortcut_opens_the_palette :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .K, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.palette.open)
	// A click beside the box closes it.
	ui.move_mouse(&s.h, {20, 800})
	ui.press(&s.h)
	ui.release(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.palette.open)
}

@(test)
the_palette_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		folder := screen_with_tracks(t, &s, kind)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		// The sidebar names the temporary folder: hidden, as 1.0.0's capture.
		execute(&s.app, engine.Toggle_Sidebar{})
		execute(&s.app, engine.Toggle_Developer_Mode{})
		open_the_palette(t, &s)
		ui.type_text(&s.h, "id3")
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "palette-dark.png" : "palette-light.png")
	}
}

// The arrow keys move through several commands, and Enter runs the one highlighted.
@(test)
the_arrow_keys_move_the_highlight_and_enter_runs_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "column")
	ui.press_key(&s.h, .Down)
	ui.press_key(&s.h, .Down)
	testing.expect_value(t, s.app.palette.current, 2)
	ui.press_key(&s.h, .Up)
	testing.expect_value(t, s.app.palette.current, 1)
	// The second of the columns' entries: Album.
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.palette.open)
	testing.expect(t, .Album not_in s.app.engine.view.columns)
	testing.expect(t, .Artist in s.app.engine.view.columns)
}

// A click runs the row clicked, not the one highlighted.
@(test)
a_click_runs_the_row_clicked :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "column")
	testing.expect(t, ui.click(&s.h, "Show the File column"))
	ui.run_frame(&s.h)
	testing.expect(t, .File in s.app.engine.view.columns)
	testing.expect(t, .Artist in s.app.engine.view.columns)
}

// Neither a click on the scrim nor Tab runs anything.
@(test)
the_scrim_and_tab_run_nothing :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	append(&s.answers.folders, folder)
	open_the_palette(t, &s)
	ui.press_key(&s.h, .Tab)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.palette.open)
	ui.move_mouse(&s.h, {20, 800})
	ui.press(&s.h)
	ui.release(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.palette.open)
	// The answer waiting for Open Folder was not used.
	testing.expect_value(t, len(s.answers.folders), 1)
}

// Enter with nothing found leaves the palette open and the field typed in; a click on
// a blank part of the box keeps it open.
@(test)
the_field_keeps_the_focus :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "zzz")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.palette.open)
	ui.type_text(&s.h, "q")
	testing.expect_value(t, s.app.palette.query, "zzzq")
	box := palette_box(&s)
	ui.move_mouse(&s.h, {box.rect.x + 4, box.rect.y + 60})
	ui.press(&s.h)
	ui.release(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.palette.open)
	ui.type_text(&s.h, "x")
	testing.expect_value(t, s.app.palette.query, "zzzqx")
}

// The wheel scrolls a long list, and the box follows the list as it is typed.
@(test)
the_list_scrolls_and_the_box_follows_the_matches :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_palette(t, &s)
	ui.type_text(&s.h, "column")
	ui.run_frame(&s.h)
	long := palette_box(&s)
	ui.type_text(&s.h, "zzz")
	ui.run_frame(&s.h)
	testing.expect(t, palette_box(&s).rect.h < long.rect.h)
}

// The matching of palette.rs's unit tests.
@(test)
a_match_ignores_case_and_keeps_the_text_as_written :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	start, end, found := find_ignoring_case("Write ID3v2.4", "id3")
	testing.expect(t, found && start == 6 && end == 9)
	start, end, found = find_ignoring_case("Réglages", "ÉGL")
	testing.expect(t, found && start == 1 && end == 5)
	_, _, found = find_ignoring_case("Save", "saved")
	testing.expect(t, !found)
	start, end, found = find_ignoring_case("Save", "")
	testing.expect(t, found && start == 0 && end == 0)
}

@(private = "file")
shown_matches :: proc(entries: []Entry, query: string) -> []string {
	found := matches(entries, query)
	out := make([]string, len(found), context.temp_allocator)
	for m, i in found {
		out[i] = fmt.tprintf(
			"%s[%s]%s",
			m.entry.label[:m.start],
			m.entry.label[m.start:m.end],
			m.entry.label[m.end:],
		)
	}
	return out
}

@(test)
names_with_a_word_that_starts_with_the_text_come_first :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	entries := []Entry {
		{label = "Overview", category = "Help", enabled = true},
		{label = "Remove ID3v1 from the selected files…", category = "Tags", enabled = true},
		{label = "Show the Tags column (ID3 versions)", category = "View", enabled = true},
		{label = "ID3v1 policy: keep where it exists", category = "Settings", enabled = true},
		{label = "Save", category = "File", enabled = true},
	}
	got := shown_matches(entries, "id3")
	want := []string {
		"Remove [ID3]v1 from the selected files…",
		"Show the Tags column ([ID3] versions)",
		"[ID3]v1 policy: keep where it exists",
	}
	testing.expect_value(t, len(got), len(want))
	for line, i in want do if i < len(got) do testing.expect_value(t, got[i], line)
}

@(test)
a_category_finds_its_entries_after_the_names :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	entries := []Entry {
		{label = "Hide Sidebar", category = "View", enabled = true},
		{label = "Overview", category = "Help", enabled = true},
	}
	got := shown_matches(entries, "view")
	testing.expect_value(t, len(got), 2)
	if len(got) == 2 {
		testing.expect_value(t, got[0], "Over[view]")
		testing.expect_value(t, got[1], "[]Hide Sidebar")
	}
}

@(test)
entries_that_cannot_run_are_left_out :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	entries := []Entry {
		{label = "Undo", category = "Edit", enabled = false},
		{label = "Redo", category = "Edit", enabled = true},
	}
	got := shown_matches(entries, "")
	testing.expect_value(t, len(got), 1)
	if len(got) == 1 do testing.expect_value(t, got[0], "[]Redo")
}

// The palette's box, which the toolbar's button shares its label with.
@(private = "file")
palette_box :: proc(s: ^Screen) -> ui.Widget_Info {
	for w in s.h.ui.widgets do if w.id == ui.widget_id("Palette") do return w
	return {}
}
