package main

import "core:strings"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen in developer mode, tall enough for every section, over one ID3v2.3
// track, selected.
@(private = "file")
screen_with_details :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 2000})
	folder = folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "1 track")
	execute(&s.app, engine.Select{s.app.engine.listed[0]})
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	return
}

// Clicks a segment of a control, found through the control: "Auto" is in two.
@(private = "file")
click_segment :: proc(t: ^testing.T, s: ^Screen, control, label: string) {
	group, found := ui.find_widget(&s.h.ui, control)
	if !testing.expectf(t, found, "no %q control", control) do return
	for w in s.h.ui.widgets {
		if w.parent == group.id && w.label == label {
			ui.move_mouse(&s.h, ui.rect_center(w.rect))
			ui.press(&s.h)
			ui.release(&s.h)
			ui.run_frame(&s.h)
			return
		}
	}
	testing.expectf(t, false, "no %q in %q", label, control)
}

@(test)
the_write_details_show_in_the_tag_format_section :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_details(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	for label in ([?]string{"Text encoding", "Padding", "Unsynchronisation", "Rewrite Selected Files"}) {
		testing.expectf(t, shows(&s, label), "%q does not show", label)
	}
	testing.expect(
		t,
		shows(
			&s,
			"These apply to every file saved in developer mode. UTF-16BE and UTF-8 need ID3v2.4; earlier versions get UTF-16.",
		),
	)
	testing.expect_value(t, s.app.engine.details, lib.Write_Details{})
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Padding"))
}

@(test)
a_choice_of_encoding_is_kept_and_auto_clears_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_details(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	click_segment(t, &s, "Text encoding", "UTF-8")
	testing.expect_value(t, s.app.engine.details.encoding, lib.Text_Encoding.UTF8)
	click_segment(t, &s, "Text encoding", "Latin-1")
	testing.expect_value(t, s.app.engine.details.encoding, lib.Text_Encoding.Latin1)
	click_segment(t, &s, "Text encoding", "Auto")
	testing.expect(t, s.app.engine.details.encoding == nil)
}

// 1.0.0's developer_mode.rs: a file rewritten takes the padding asked for, and the
// unsynchronisation.
@(test)
a_file_rewritten_takes_the_padding_and_the_unsynchronisation_asked_for :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_details(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	click_segment(t, &s, "Padding", "4096")
	testing.expect_value(t, s.app.engine.details.padding, 4096)
	testing.expect(t, ui.click(&s.h, "Unsynchronisation"))
	testing.expect(t, s.app.engine.details.unsynchronisation)
	testing.expect(t, ui.click(&s.h, "Rewrite Selected Files"))
	ui.run_frame(&s.h)
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	padded, flagged := false, false
	for w in s.h.ui.widgets {
		if strings.has_suffix(w.label, " · 4096 bytes of padding") do padded = true
		if w.label == "Unsynchronised" do flagged = true
	}
	testing.expect(t, padded)
	testing.expect(t, flagged)
}

@(test)
the_write_details_speak_french :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(t, ui.catalog_tr(&c, "Text encoding"), "Encodage du texte")
	testing.expect_value(t, ui.catalog_tr(&c, "Padding"), "Remplissage")
	testing.expect_value(t, ui.catalog_tr(&c, "Unsynchronisation"), "Désynchronisation")
	testing.expect_value(
		t,
		ui.catalog_tr(&c, "Rewrite Selected Files"),
		"Réécrire les fichiers sélectionnés",
	)
}
