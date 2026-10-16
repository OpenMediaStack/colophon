package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen over a copy of fixture named 1.mp3, its only track selected, as
// 1.0.0's settings tests.
@(private = "file")
screen_with_a_selected :: proc(
	t: ^testing.T,
	s: ^Screen,
	fixture: string,
	kind := ui.Theme_Kind.Dark,
) -> (
	folder: string,
) {
	screen_init(s, {1440, 900}, kind)
	folder = folder_with_fixtures(t, {{fixture, "1.mp3"}})
	// The folder shows as the home, "~": the same on every platform.
	delete(s.app.home)
	s.app.home = strings.clone(folder)
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "1 track")
	execute(&s.app, engine.Select_All{})
	ui.run_frame(&s.h)
	return
}

@(private = "file")
open_the_settings :: proc(t: ^testing.T, s: ^Screen) {
	open_settings(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.settings_open)
}

// The checkbox of developer mode, which the status bar's marker shares its label with.
@(private = "file")
developer_checkbox :: proc(s: ^Screen) -> ui.Widget_Info {
	for w in s.h.ui.widgets do if w.role == .Check_Box && w.label == "Developer mode" do return w
	return {}
}

@(test)
the_settings_choose_how_tags_are_written :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v24_unicode.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_settings(t, &s)
	testing.expect(t, ui.click(&s.h, "2.3"))
	testing.expect(t, ui.click(&s.h, "Always"))
	testing.expect_value(t, s.app.engine.edits.policy, lib.Write_Policy{.V2_3, .Always})
}

@(test)
developer_mode_is_a_setting :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v24_unicode.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_the_settings(t, &s)
	click_checkbox :: proc(s: ^Screen) {
		box := developer_checkbox(s)
		ui.move_mouse(&s.h, ui.rect_center(box.rect))
		ui.press(&s.h)
		ui.release(&s.h)
	}
	click_checkbox(&s)
	testing.expect(t, s.app.engine.view.developer_mode)
	// Toggled back off: the status bar's marker has the same label but not the id.
	click_checkbox(&s)
	testing.expect(t, !s.app.engine.view.developer_mode)
	click_checkbox(&s)
	testing.expect(t, s.app.engine.view.developer_mode)
	seen := make(map[ui.Widget_Id]bool, context.temp_allocator)
	for w in s.h.ui.widgets {
		testing.expectf(t, !seen[w.id], "%q repeats an id", w.label)
		seen[w.id] = true
	}
	testing.expect(t, ui.click(&s.h, "Done"))
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.settings_open)
	testing.expect(t, shows(&s, "Developer mode"))
}

@(test)
the_shortcut_and_escape_open_and_close_the_settings :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v24_unicode.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Comma, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.settings_open)
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.settings_open)
}

@(private = "file")
formats_of :: proc(s: ^Screen) -> lib.Tag_Formats {
	return s.app.engine.library.tracks[0].metadata.formats
}

@(test)
saving_while_never_writing_id3v1_asks_first :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Set_Write_Policy{{.V2_4, .Never}})
	retype(&s, "Album", "Analog Hearts")
	ui.press_key(&s.h, .Enter)
	request_save(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Remove the ID3v1 tag from 1 file?"))
	testing.expect(t, ui.click(&s.h, "Keep ID3v1"))
	wait_for_save(t, &s)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	testing.expect(t, formats_of(&s).id3v1 != nil)
}

@(test)
removing_id3v1_once_confirmed_removes_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Set_Write_Policy{{.V2_4, .Never}})
	retype(&s, "Album", "Analog Hearts")
	ui.press_key(&s.h, .Enter)
	request_save(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Remove ID3v1"))
	wait_for_save(t, &s)
	testing.expect(t, formats_of(&s).id3v1 == nil)
}

@(test)
escape_keeps_the_tag_and_return_does_not_remove_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Set_Write_Policy{{.V2_4, .Never}})
	retype(&s, "Album", "Analog Hearts")
	ui.press_key(&s.h, .Enter)
	request_save(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.removal != nil)
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.removal == nil)
	// Keeping saves the file as it is, its ID3v1 tag included.
	wait_for_save(t, &s)
	testing.expect(t, formats_of(&s).id3v1 != nil)
}

@(test)
removing_a_tag_asks_first_and_keeping_it_changes_nothing :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	request_version(&s.app, engine.Id3v1_Choice{nil})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Remove the ID3v1 tag from 1 file?"))
	testing.expect(t, shows(&s, "1.mp3"))
	testing.expect(t, ui.click(&s.h, "Keep ID3v1"))
	testing.expect(t, s.app.removal == nil)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	// Confirmed, it waits to be saved.
	request_version(&s.app, engine.Id3v1_Choice{nil})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Remove ID3v1"))
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
}

@(test)
a_file_without_the_tag_is_not_asked_about :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	request_version(&s.app, engine.Id3v1_Choice{nil})
	testing.expect(t, s.app.removal == nil)
}

@(test)
a_click_outside_the_dialog_does_nothing :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with_fixtures(
		t,
		{{"v23_v1_long_title.mp3", "1.mp3"}, {"v23_full.mp3", "2.mp3"}},
	)
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "2 tracks")
	testing.expect(t, ui.click(&s.h, "A title longer than thirty characters"))
	request_version(&s.app, engine.Id3v1_Choice{nil})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.removal != nil)
	// The second row, under the dialog's scrim, would have taken the selection.
	testing.expect(t, ui.click(&s.h, "Paper Satellites"))
	testing.expect(t, s.app.removal != nil)
	testing.expect_value(t, len(s.app.engine.selection.tracks), 1)
	testing.expect(t, engine.is_selected(&s.app.engine.selection, s.app.engine.listed[0]))
}

// The settings and the removal's dialog, in both themes.
@(test)
the_dialogs_match_their_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3", kind)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		open_the_settings(t, &s)
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "settings-dark.png" : "settings-light.png")
		app := &s.app
		app.settings_open = false
		ui.run_frame(&s.h)
		request_version(app, engine.Id3v1_Choice{nil})
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "tag-removal-dark.png" : "tag-removal-light.png")
	}
}

// A second removal while the first waits takes its place, leaking nothing.
@(test)
a_removal_asked_while_one_waits_takes_its_place :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	request_version(&s.app, engine.Id3v1_Choice{nil})
	request_version(&s.app, engine.Id3v2_Choice{nil})
	removal, asking := s.app.removal.?
	testing.expect(t, asking && removal.tag == .Id3v2)
}

// The ID3v2 removal, from the palette: Escape keeps the tag.
@(test)
removing_id3v2_from_the_palette_asks_and_escape_keeps_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Developer_Mode{})
	open_palette(&s.app)
	ui.run_frame(&s.h)
	ui.type_text(&s.h, "remove id3v2")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Remove the ID3v2 tag from 1 file?"))
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.removal == nil)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
}

// More than eight files: eight listed by name, the others counted.
@(test)
the_removal_lists_eight_files_and_counts_the_others :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	copies: [10][2]string
	for &c, i in copies do c = {"v23_v1_long_title.mp3", fmt.tprintf("%02d.mp3", i)}
	folder := folder_with_fixtures(t, copies[:])
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "10 tracks")
	execute(&s.app, engine.Select_All{})
	request_version(&s.app, engine.Id3v1_Choice{nil})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Remove the ID3v1 tag from 10 files?"))
	testing.expect(t, shows(&s, "07.mp3"))
	testing.expect(t, !shows(&s, "08.mp3"))
	testing.expect(t, shows(&s, "and 2 other files"))
}

// A choice already made is not asked about again.
@(test)
a_tag_already_removed_is_not_asked_about_again :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	request_version(&s.app, engine.Id3v1_Choice{nil})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Remove ID3v1"))
	request_version(&s.app, engine.Id3v1_Choice{nil})
	testing.expect(t, s.app.removal == nil)
}

// The settings item is named for the platform.
@(test)
the_settings_are_named_for_the_platform :: proc(t: ^testing.T) {
	app: App
	app.platform = .Linux
	testing.expect_value(t, settings_label(&app), "Preferences…")
	app.platform = .Windows
	testing.expect_value(t, settings_label(&app), "Options…")
	app.platform = .Mac
	testing.expect_value(t, settings_label(&app), "Settings…")
}

// The toolbar's Save asks as the shortcut does.
@(test)
the_toolbar_save_asks_first :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_selected(t, &s, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Set_Write_Policy{{.V2_4, .Never}})
	retype(&s, "Album", "Analog Hearts")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Save 1 file"))
	ui.run_frame(&s.h)
	testing.expect(t, s.app.removal != nil)
}

// The dialog is laid out as 1.0.0's grid: a control, 8 points, its hint of natural lines
// (15 for the 12 point text), 8 more before the next control, and a checkbox row of 20:
// 293 points from its top to its bottom, as 1.0.0's capture.
@(test)
the_settings_dialog_is_as_high_as_1_0_0s :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	s.app.settings_open = true
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	dialog, found := ui.find_widget(&s.h.ui, "Settings")
	if !testing.expect(t, found) do return
	testing.expect_value(t, dialog.rect.h, 293)
}
