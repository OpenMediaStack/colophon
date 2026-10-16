package main

import "core:fmt"
import "core:testing"

import ui "../ui"

@(test)
opening_a_folder_reads_its_tracks :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with(t, {"00.mp3", "01.mp3", "02.mp3"})
	defer remove_folder(folder)
	append(&s.answers.folders, folder)
	testing.expect(t, ui.click(&s.h, "Open folder…"))
	wait_until_shown(t, &s, "3 tracks")
	testing.expect(t, !shows(&s, "Open your music folder"))
	testing.expect(t, shows(&s, "Sidebar"))
}

@(test)
opening_another_folder_adds_its_tracks :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	first := folder_with(t, {"first.mp3"})
	defer remove_folder(first)
	second := folder_with(t, {"second.mp3"})
	defer remove_folder(second)
	append(&s.answers.folders, first, second)
	ui.click(&s.h, "Open folder")
	wait_until_shown(t, &s, "1 track")
	ui.click(&s.h, "Open folder")
	wait_until_shown(t, &s, "2 tracks")
	testing.expect_value(t, len(s.app.engine.library.roots), 2)
}

@(test)
cancelling_the_dialog_changes_nothing :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Open folder…"))
	testing.expect(t, shows(&s, "Open your music folder"))
	testing.expect(t, shows(&s, "No folder open"))
}

@(test)
the_stop_button_stops_reading :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with(t, {"00.mp3", "01.mp3", "02.mp3"})
	defer remove_folder(folder)
	append(&s.answers.folders, folder)
	// Nothing is polled before the next frame: the reading has just started.
	ui.click(&s.h, "Open folder")
	testing.expect(t, shows(&s, "Reading… 0 tracks found"))
	testing.expect(t, ui.click(&s.h, "Stop"))
	// The bar's text was drawn before the button: it follows in the next frame.
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Reading stopped, 0 tracks"))
	testing.expect(t, !shows(&s, "Stop"))
}

@(test)
the_shortcuts_open_a_folder_and_files :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with(t, {"00.mp3", "01.mp3", "02.mp3"})
	defer remove_folder(folder)
	other := folder_with(t, {"a.mp3", "b.mp3"})
	defer remove_folder(other)
	append(&s.answers.folders, other)
	files := [?]string{fmt.tprintf("%s/00.mp3", folder), fmt.tprintf("%s/02.mp3", folder)}
	s.answers.files = files[:]
	// The files alone, without the rest of their folder.
	ui.press_key(&s.h, .O, ui.COMMAND + {.Shift})
	wait_until_shown(t, &s, "2 tracks")
	ui.press_key(&s.h, .O, ui.COMMAND)
	wait_until_shown(t, &s, "4 tracks")
}

@(test)
an_unreadable_folder_is_reported :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	append(&s.answers.folders, "/this/folder/does/not/exist")
	ui.click(&s.h, "Open folder")
	// The scan reports its error, then its end: the count shows once it ended.
	wait_until_shown(t, &s, "0 tracks")
	testing.expect(t, shows(&s, "1 file could not be read"))
}

// A folder with two albums of one track each.
@(private = "file")
albums :: proc(t: ^testing.T) -> string {
	return folder_with_fixtures(
		t,
		{{"v23_full.mp3", "Small Hours/1.mp3"}, {"v24_full.mp3", "Analog Hearts/1.mp3"}},
	)
}

@(test)
folders_and_files_dropped_together_open_together :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	root := albums(t)
	defer remove_folder(root)
	drop_begin(&s.app)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Drop to open these folders and files"))
	drop_file(&s.app, fmt.tprintf("%s/Small Hours", root))
	drop_file(&s.app, fmt.tprintf("%s/Analog Hearts/1.mp3", root))
	drop_end(&s.app, 0)
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Drop to open these folders and files"))
	wait_until_shown(t, &s, "2 tracks")
}

@(test)
a_drag_that_leaves_the_window_opens_nothing :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	drop_begin(&s.app)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Drop to open these folders and files"))
	drop_end(&s.app, 0)
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Drop to open these folders and files"))
	testing.expect(t, shows(&s, "Open your music folder"))
	// A text file dropped is not music.
	notes := folder_with(t, {"notes.txt"})
	defer remove_folder(notes)
	drop_begin(&s.app)
	drop_file(&s.app, fmt.tprintf("%s/notes.txt", notes))
	drop_end(&s.app, 0)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Open your music folder"))
}

@(test)
the_drop_target_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		screen_init(&s, {1440, 900}, kind)
		defer screen_destroy(&s)
		drop_begin(&s.app)
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "drop-dark.png" : "drop-light.png")
	}
}

// The empty state's button is a large one, 32 high and 145 wide, as 1.0.0's.
@(test)
the_empty_states_button_is_a_large_one :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	button, found := ui.find_widget(&s.h.ui, "Open folder…")
	if !testing.expect(t, found) do return
	testing.expect_value(t, button.rect.h, 32)
	testing.expect_value(t, button.rect.w, 145)
}
