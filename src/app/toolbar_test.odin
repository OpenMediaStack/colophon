package main

import "core:fmt"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen over "Paper Satellites" by Marlowe Kite and "Café" by 坂本龍一.
@(private = "file")
screen_with_two_tracks :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 900})
	folder = folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v23_unicode.mp3", "2.mp3"}})
	open_folder_of(t, s, folder)
	testing.expect_value(t, len(s.app.engine.listed), 2)
	return
}

@(test)
the_filter_narrows_the_table_and_escape_empties_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Filter"))
	ui.type_text(&s.h, "marlowe")
	testing.expect_value(t, len(s.app.engine.listed), 1)
	ui.press_key(&s.h, .Escape)
	testing.expect_value(t, len(s.app.engine.listed), 2)
	testing.expect_value(t, s.app.engine.filter, "")
	testing.expect(t, !ui.has_focus(&s.h.ui, ui.widget_id("Filter")))
}

@(test)
the_clear_button_empties_the_filter_and_keeps_the_keyboard :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, !shows(&s, "Clear the filter"))
	ui.click(&s.h, "Filter")
	ui.type_text(&s.h, "café")
	testing.expect_value(t, len(s.app.engine.listed), 1)
	testing.expect(t, ui.click(&s.h, "Clear the filter"))
	testing.expect_value(t, len(s.app.engine.listed), 2)
	testing.expect(t, ui.has_focus(&s.h.ui, ui.widget_id("Filter")))
	ui.type_text(&s.h, "paper")
	testing.expect_value(t, len(s.app.engine.listed), 1)
}

// Enter does nothing in the filter, as in 1.0.0: it keeps the caret and the text.
@(test)
enter_keeps_the_filter_focused :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Filter")
	ui.type_text(&s.h, "marlowe")
	ui.press_key(&s.h, .Enter)
	testing.expect(t, ui.has_focus(&s.h.ui, ui.widget_id("Filter")))
	testing.expect_value(t, s.app.engine.filter, "marlowe")
	testing.expect_value(t, len(s.app.engine.listed), 1)
}

@(test)
command_f_reaches_the_filter :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .F, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, ui.has_focus(&s.h.ui, ui.widget_id("Filter")))
	ui.type_text(&s.h, "café")
	testing.expect_value(t, len(s.app.engine.listed), 1)
}

@(test)
the_save_button_saves_and_undo_takes_back :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	e := &s.app.engine
	undo, _ := ui.find_widget(&s.h.ui, "Undo")
	testing.expect(t, .Disabled in undo.states)
	save, _ := ui.find_widget(&s.h.ui, "Save")
	testing.expect(t, .Disabled in save.states)

	// The first track takes a new title, as the inspector will give it.
	engine.execute(e, engine.Select{0})
	engine.execute(e, engine.Apply_Edit{{.Title, "Neon Overpass"}})
	ui.run_frame(&s.h)
	undo, _ = ui.find_widget(&s.h.ui, "Undo")
	testing.expect(t, .Disabled not_in undo.states)
	testing.expect(t, shows(&s, "1 file with unsaved changes"))
	testing.expect(t, ui.click(&s.h, "Undo"))
	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect(t, ui.click(&s.h, "Redo"))
	testing.expect_value(t, len(e.edits.pending), 1)

	// The save button's label follows in the next frame.
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Save 1 file"))
	wait_for_save(t, &s)
	testing.expect_value(t, len(e.edits.pending), 0)
	track := lib.read_track(fmt.tprintf("%s/1.mp3", folder), context.temp_allocator)
	testing.expect_value(t, track.metadata.tags.title, "Neon Overpass")
	save, _ = ui.find_widget(&s.h.ui, "Save")
	testing.expect(t, .Disabled in save.states)
}

@(test)
command_s_saves_and_command_z_undoes :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	e := &s.app.engine
	engine.execute(e, engine.Select{0})
	engine.execute(e, engine.Apply_Edit{{.Title, "Neon Overpass"}})
	ui.press_key(&s.h, .Z, ui.COMMAND)
	testing.expect_value(t, len(e.edits.pending), 0)
	ui.press_key(&s.h, .Z, ui.COMMAND + {.Shift})
	testing.expect_value(t, len(e.edits.pending), 1)
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	testing.expect_value(t, len(e.edits.pending), 0)
}

@(test)
the_status_bar_counts_the_tracks_and_the_selection :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, shows(&s, "2 tracks"))
	engine.execute(&s.app.engine, engine.Select{1})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "2 tracks · 1 selected"))
}

// The command palette's button is its key (the command sign and K on a Mac) at 11 points in
// 8 points of padding, 34 wide (1.0.0's is 35), and the filter starts 4 points after the gap that follows Redo.
@(test)
the_palette_button_is_its_key_in_a_small_box :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	button, found := ui.find_widget(&s.h.ui, "Command palette")
	if !testing.expect(t, found) do return
	// 1.0.0's is 35: 19 of text and 16 of padding; the embedded Inter at 11 gives 34.
	testing.expect_value(t, button.rect.w, 34)
	redo, has_redo := ui.find_widget(&s.h.ui, "Redo")
	filter, has_filter := ui.find_widget(&s.h.ui, "Filter")
	testing.expect(t, has_redo && has_filter)
	testing.expect_value(t, filter.rect.x - (redo.rect.x + redo.rect.w), 16)
}
