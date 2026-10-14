package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../engine"
import lib "../library"
import ui "../ui"

// How long a test waits for a thread, in real time.
@(private = "file")
PATIENCE :: 20 * time.Second

// The main screen over one copy of a fixture, its only track selected, as 1.0.0's
// saving tests. The folder is the home, so that it shows as "~".
@(private = "file")
screen_with_a_selected :: proc(
	t: ^testing.T,
	s: ^Screen,
	fixture: string,
	kind := ui.Theme_Kind.Dark,
) -> (
	folder, path: string,
) {
	screen_init(s, {1440, 900}, kind)
	folder = folder_with_fixtures(t, {{fixture, "1.mp3"}})
	path, _ = filepath.join({folder, "1.mp3"})
	delete(s.app.home)
	s.app.home = strings.clone(folder)
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "1 track")
	execute(&s.app, engine.Select_All{})
	ui.run_frame(&s.h)
	return
}

// The same with the title changed to "Neon Overpass" and not saved.
@(private = "file")
screen_with_a_change :: proc(t: ^testing.T, s: ^Screen) -> (folder, path: string) {
	folder, path = screen_with_a_selected(t, s, "v23_full.mp3")
	retype(s, "Title", "Neon Overpass")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	return
}

@(private = "file")
title_on_disk :: proc(path: string) -> string {
	track := lib.read_track(path, context.temp_allocator)
	return track.metadata.tags.title.? or_else ""
}

@(private = "file")
set_read_only :: proc(t: ^testing.T, path: string, read_only: bool) {
	mode :=
		read_only ? os.Permissions{.Read_User, .Read_Group, .Read_Other} : os.Permissions_Default
	testing.expect(t, os.change_mode(path, mode) == nil)
}

// Polls the engine as the loop does, running frames, until the window closes.
@(private = "file")
wait_until_quit :: proc(t: ^testing.T, s: ^Screen) {
	start := time.tick_now()
	for !s.app.quit {
		if time.tick_since(start) > PATIENCE do testing.fail_now(t, "the window did not close in time")
		engine.poll(&s.app.engine)
		ui.run_frame(&s.h)
		time.sleep(time.Millisecond)
	}
}

// Asks the window to close and runs the frames the dialog needs to take the keys.
@(private = "file")
close_requested :: proc(s: ^Screen) -> (closes: bool) {
	closes = request_close(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	return
}

// Clicks a button of the unsaved changes dialog, whose label the toolbar's save button
// may share.
@(private = "file")
dialog_click :: proc(s: ^Screen, label: string) -> bool {
	dialog := ui.widget_id("Unsaved changes")
	for w in s.h.ui.widgets {
		if w.role != .Button || w.label != label || w.parent != dialog do continue
		ui.move_mouse(&s.h, ui.rect_center(w.rect))
		ui.press(&s.h)
		ui.release(&s.h)
		ui.run_frame(&s.h)
		return true
	}
	return false
}

@(test)
command_s_saves_what_was_typed_even_without_enter :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_selected(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	retype(&s, "Title", "Neon Overpass")
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	testing.expect_value(t, title_on_disk(path), "Neon Overpass")
	testing.expect(t, !shows(&s, "1 file with unsaved changes"))
}

@(test)
the_save_button_saves :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Save 1 file"))
	wait_for_save(t, &s)
	testing.expect_value(t, title_on_disk(path), "Neon Overpass")
}

@(test)
undo_and_redo_take_back_a_whole_word :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Z, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Paper Satellites"))
	testing.expect(t, !engine.can_undo(&s.app.engine))
	ui.press_key(&s.h, .Z, ui.COMMAND + {.Shift})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Neon Overpass"))
}

@(test)
escape_leaves_nothing_to_undo :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_selected(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	retype(&s, "Title", "Neon Overpass")
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Paper Satellites"))
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	testing.expect(t, !engine.can_undo(&s.app.engine))
}

@(test)
revert_drops_the_changes_of_the_selection :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Revert"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Paper Satellites"))
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
}

@(test)
the_inspector_says_how_the_file_will_be_saved :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	retype(&s, "Title", "A brand new title, well over thirty characters")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "ID3v2.4, ID3v1.1"))
	testing.expect(t, shows(&s, "ID3v1 will keep only part of: Title"))
}

@(test)
a_file_that_cannot_be_saved_is_reported :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_selected(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	set_read_only(t, path, true)
	defer set_read_only(t, path, false)
	retype(&s, "Title", "Neon Overpass")
	ui.press_key(&s.h, .Enter)
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	testing.expect(t, shows(&s, "1 file could not be saved"))
	testing.expect(t, shows(&s, "1 file with unsaved changes"))
}

@(test)
a_save_says_it_saved_then_the_toast_goes :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	execute(&s.app, engine.Save{})
	wait_for_save(t, &s)
	testing.expect(t, shows(&s, "Saved 1 file"))
	ui.wait(&s.h, 5)
	testing.expect(t, !shows(&s, "Saved 1 file"))
}

@(test)
a_failed_save_can_be_retried_from_its_toast :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_selected(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	set_read_only(t, path, true)
	retype(&s, "Album", "Analog Hearts")
	ui.press_key(&s.h, .Enter)
	execute(&s.app, engine.Save{})
	wait_for_save(t, &s)
	testing.expect(t, shows(&s, "1 file could not be saved"))
	set_read_only(t, path, false)
	testing.expect(t, ui.click(&s.h, "Retry"))
	wait_for_save(t, &s)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	testing.expect(t, shows(&s, "Saved 1 file"))
}

@(test)
closing_without_changes_closes_at_once :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_selected(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	testing.expect(t, close_requested(&s))
	testing.expect(t, s.app.quit)
}

@(test)
closing_with_changes_asks_first :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	testing.expect(t, !close_requested(&s))
	testing.expect(t, !s.app.quit)
	testing.expect(t, shows(&s, "Save changes to 1 file before quitting?"))
	testing.expect(
		t,
		shows(
			&s,
			"Neon Overpass has changes that are not saved yet. Quitting without saving discards them.",
		),
	)
}

@(test)
cancel_and_escape_keep_the_changes :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	close_requested(&s)
	testing.expect(t, dialog_click(&s, "Cancel"))
	testing.expect_value(t, s.app.departure, nil)
	close_requested(&s)
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect_value(t, s.app.departure, nil)
	testing.expect(t, !s.app.quit)
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
}

@(test)
dont_save_closes_without_writing :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	close_requested(&s)
	testing.expect(t, dialog_click(&s, "Don’t Save"))
	testing.expect(t, s.app.quit)
	testing.expect_value(t, title_on_disk(path), "Paper Satellites")
}

@(test)
save_writes_the_files_then_closes :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	close_requested(&s)
	testing.expect(t, dialog_click(&s, "Save 1 file"))
	wait_until_quit(t, &s)
	testing.expect_value(t, title_on_disk(path), "Neon Overpass")
}

@(test)
return_saves :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	close_requested(&s)
	ui.press_key(&s.h, .Enter)
	wait_until_quit(t, &s)
	testing.expect_value(t, title_on_disk(path), "Neon Overpass")
}

@(test)
a_file_that_cannot_be_saved_keeps_the_window_open :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	set_read_only(t, path, true)
	defer set_read_only(t, path, false)
	close_requested(&s)
	testing.expect(t, dialog_click(&s, "Save 1 file"))
	wait_for_save(t, &s)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.quit)
	testing.expect_value(t, s.app.departure, nil)
	testing.expect(t, shows(&s, "1 file could not be saved"))
}

@(test)
opening_another_folder_keeps_the_changes_without_asking :: proc(t: ^testing.T) {
	s: Screen
	folder, path := screen_with_a_change(t, &s)
	defer remove_folder(folder)
	defer delete(path)
	defer screen_destroy(&s)
	other := folder_with_fixtures(t, {{"v24_full.mp3", "a.mp3"}})
	defer remove_folder(other)
	open_folder_of(t, &s, other)
	testing.expect_value(t, len(s.app.engine.library.tracks), 2)
	testing.expect_value(t, s.app.departure, nil)
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
}

@(test)
the_dialog_names_three_tracks_and_counts_the_others :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	copies: [5][2]string
	for &c, i in copies do c = {"v23_full.mp3", fmt.tprintf("%d.mp3", i + 1)}
	folder := folder_with_fixtures(t, copies[:])
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "5 tracks")
	execute(&s.app, engine.Select_All{})
	ui.run_frame(&s.h)
	retype(&s, "Title", "Neon Overpass")
	ui.press_key(&s.h, .Enter)
	close_requested(&s)
	testing.expect(
		t,
		shows(
			&s,
			"Neon Overpass, Neon Overpass and 3 other files have changes that are not saved yet. Quitting without saving discards them.",
		),
	)
}

@(test)
the_unsaved_changes_dialog_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		folder, path := screen_with_a_selected(t, &s, "v23_full.mp3", kind)
		defer remove_folder(folder)
		defer delete(path)
		defer screen_destroy(&s)
		retype(&s, "Title", "Neon Overpass")
		ui.press_key(&s.h, .Enter)
		close_requested(&s)
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(
			t,
			&s,
			kind == .Dark ? "unsaved-changes-dark.png" : "unsaved-changes-light.png",
		)
	}
}

// A toast over the empty window, as 1.0.0's capture: a save that failed twice.
@(test)
a_toast_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		screen_init(&s, {1440, 900}, kind)
		defer screen_destroy(&s)
		notify(&s.app, .Error, "2 files could not be saved", .Retry_Save, s.h.ui.input.time)
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "toast-dark.png" : "toast-light.png")
	}
}
