package main

import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen, tall enough for every section of the inspector in developer mode,
// over "Paper Satellites" in ID3v2.3 alone, selected, as 1.0.0's developer mode tests.
@(private = "file")
screen_with_an_id3v2_3_track :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 1400})
	folder = folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "1 track")
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	ui.run_frame(&s.h)
	return
}

@(private = "file")
checked :: proc(s: ^Screen, label: string) -> bool {
	for w in s.h.ui.widgets do if w.label == label && .Checked in w.states do return true
	return false
}

// Whether a segment of a version row is selected, found through its row, since "None"
// and the versions of ID3v1 appear in both rows.
@(private = "file")
segment_checked :: proc(s: ^Screen, row, label: string) -> bool {
	group, found := ui.find_widget(&s.h.ui, row)
	if !found do return false
	for w in s.h.ui.widgets {
		if w.parent == group.id && w.label == label && .Checked in w.states do return true
	}
	return false
}

@(private = "file")
no_segment_checked :: proc(s: ^Screen, row: string) -> bool {
	group, found := ui.find_widget(&s.h.ui, row)
	if !found do return false
	for w in s.h.ui.widgets do if w.parent == group.id && .Checked in w.states do return false
	return true
}

@(test)
the_tag_format_section_shows_in_developer_mode_only :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_an_id3v2_3_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, !shows(&s, "Write ID3v2"))
	testing.expect(t, !shows(&s, "Developer mode"))
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Write ID3v2"))
	testing.expect(t, shows(&s, "Developer mode"))
	testing.expect(t, checked(&s, "2.4"))
}

@(test)
a_version_chosen_is_written_on_save :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_an_id3v2_3_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "2.2"))
	ui.run_frame(&s.h)
	testing.expect(t, checked(&s, "2.2"))
	testing.expect(t, shows(&s, "Saving converts 1 file from ID3v2.3 to ID3v2.2."))
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	formats := s.app.engine.library.tracks[0].metadata.formats
	testing.expect_value(t, formats.id3v2, lib.Id3v2_Version.V2_2)
	testing.expect(t, formats.id3v1 == nil)
}

@(test)
undo_takes_a_version_back :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_an_id3v2_3_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "1.1"))
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
	ui.press_key(&s.h, .Z, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	testing.expect(t, checked(&s, "2.4"))
}

@(test)
removing_a_version_asks_first_from_the_section :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_an_id3v2_3_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	// The first "None" is ID3v2's: the file has that tag.
	for w in s.h.ui.widgets {
		if w.role == .Radio_Button && w.label == "None" {
			ui.move_mouse(&s.h, ui.rect_center(w.rect))
			ui.press(&s.h)
			ui.release(&s.h)
			break
		}
	}
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Remove the ID3v2 tag from 1 file?"))
	testing.expect(t, ui.click(&s.h, "Keep ID3v2"))
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
}

@(test)
a_comment_too_long_for_a_new_id3v1_tag_is_told :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_an_id3v2_3_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "1.1"))
	retype(&s, "Comment", "A long comment for testing purposes, on more than one line")
	ui.press_key(&s.h, .Tab)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "ID3v1 will keep only part of: Comment"))
}

@(test)
a_mixed_selection_selects_no_version_where_the_files_differ :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 1400})
	folder := folder_with_fixtures(
		t,
		{{"v23_full.mp3", "1.mp3"}, {"v23_v1_long_title.mp3", "2.mp3"}},
	)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "2 tracks")
	e := &s.app.engine
	execute(&s.app, engine.Toggle_Developer_Mode{})
	execute(&s.app, engine.Select{e.listed[0]})
	execute(&s.app, engine.Select_Range{e.listed[1]})
	ui.run_frame(&s.h)
	// The files differ in ID3v1, so the versions are not shared: as in 1.0.0, neither
	// row selects anything.
	testing.expect(t, no_segment_checked(&s, "Write ID3v2"))
	testing.expect(t, no_segment_checked(&s, "Write ID3v1"))
	// Choosing one for both files is a pending change of both, and they now agree.
	testing.expect(t, ui.click(&s.h, "1.0"))
	ui.run_frame(&s.h)
	testing.expect_value(t, len(e.edits.pending), 2)
	testing.expect(t, segment_checked(&s, "Write ID3v1", "1.0"))
	testing.expect(t, segment_checked(&s, "Write ID3v2", "2.4"))
}

@(test)
a_file_without_tags_shows_the_versions_saving_would_write :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 1400})
	folder := folder_with_fixtures(t, {{"no_tag.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "1 track")
	execute(&s.app, engine.Toggle_Developer_Mode{})
	execute(&s.app, engine.Select{s.app.engine.listed[0]})
	ui.run_frame(&s.h)
	testing.expect(t, segment_checked(&s, "Write ID3v2", "2.4"))
	testing.expect(t, segment_checked(&s, "Write ID3v1", "None"))
	testing.expect(t, !shows(&s, "Saving converts 1 file."))
}

@(test)
the_section_folds_with_its_header :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_an_id3v2_3_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Write ID3v1"))
	testing.expect(t, ui.click(&s.h, "Tag format"))
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Write ID3v1"))
	testing.expect(t, ui.click(&s.h, "Tag format"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Write ID3v1"))
}

// The five texts saving can give for a conversion, from summaries made by hand.
@(test)
the_conversion_is_told_in_five_ways :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	v23 := lib.Tag_Formats {
		id3v2 = .V2_3,
	}
	v24 := lib.Tag_Formats {
		id3v2 = .V2_4,
	}
	Case :: struct {
		name:     string,
		summary:  engine.Summary,
		expected: string,
	}
	cases := [?]Case {
		{"nothing to convert", {}, ""},
		{"mixed results", {converted = 3, saved_as = engine.Mixed{}}, "Saving converts 3 files."},
		{"one file", {converted = 1, saved_as = engine.Mixed{}}, "Saving converts 1 file."},
		{
			"every tag removed",
			{converted = 2, formats = v23, saved_as = lib.Tag_Formats{}},
			"Saving removes the tags of 2 files.",
		},
		{
			"from nothing known",
			{converted = 1, formats = engine.Mixed{}, saved_as = v24},
			"Saving converts 1 file to ID3v2.4.",
		},
		{
			"from tags to others",
			{converted = 2, formats = v23, saved_as = v24},
			"Saving converts 2 files from ID3v2.3 to ID3v2.4.",
		},
	}
	for c in cases do testing.expect_value(t, conversion_text(c.summary), c.expected)
}

// The same texts in French, from 1.0.0's catalogue: checked on the catalogue itself,
// since the one in use is shared by every test.
@(test)
the_conversion_speaks_french :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(
		t,
		ui.fill(
			ui.catalog_tr_n(
				&c,
				"Saving converts {n} file from {} to {}.",
				"Saving converts {n} files from {} to {}.",
				2,
				"",
			),
			"ID3v2.3",
			"ID3v2.4",
		),
		"L’enregistrement convertit 2 fichiers de ID3v2.3 en ID3v2.4.",
	)
	testing.expect_value(
		t,
		ui.catalog_tr_n(&c, "Saving converts {n} file.", "Saving converts {n} files.", 1, ""),
		"L’enregistrement convertit 1 fichier.",
	)
	testing.expect_value(t, ui.catalog_tr(&c, "Write ID3v2"), "Écrire l’ID3v2")
}

// The developer mode's marker in the status bar is JetBrains Mono at 11 points in a box
// 18 high with 6 points on either side, as 1.0.0's: its words are 91 points wide at twice the scale (92.4 as the font draws them).
@(test)
the_developer_marker_is_mono_at_11_points :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	// At twice the scale, where fontstash's whole pixel advances are fine enough to tell
	// 11 points from 12 (13 pixels a glyph against 14).
	s.h.scale = 2
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	marker: ui.Widget_Info
	for w in s.h.ui.widgets do if w.role == .Label && w.label == "Developer mode" do marker = w
	if !testing.expect(t, marker.rect.h > 0) do return
	testing.expect_value(t, marker.rect.h, 18)
	testing.expectf(t, abs(marker.rect.w - (91 + 12)) <= 1, "the marker is %v wide", marker.rect.w)
}
