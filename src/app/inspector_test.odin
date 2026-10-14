package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen showing these fixtures under these names, every track read.
@(private = "file")
screen_showing :: proc(
	t: ^testing.T,
	s: ^Screen,
	copies: [][2]string,
	kind := ui.Theme_Kind.Dark,
	subfolder := "",
) -> (
	folder: string,
) {
	screen_init(s, {1440, 900}, kind)
	folder = folder_with_fixtures(t, copies)
	// The folder shows from the home folder, as "~": a home named the same on every run.
	delete(s.app.home)
	s.app.home = strings.clone(folder)
	opened := len(subfolder) > 0 ? fmt.tprintf("%s/%s", folder, subfolder) : folder
	open_folder_of(t, s, opened)
	wait_until_shown(t, s, ui.tr_n("{n} track", "{n} tracks", len(copies)))
	return
}

// The value a field shows, by its label.
@(private = "file")
field_value :: proc(s: ^Screen, label: string) -> (value: string, found: bool) {
	for w in s.h.ui.widgets do if w.role == .Text_Field && w.label == label do return w.value, true
	return
}

// Types text in a field, in place of what it held.
@(private = "file")
retype :: proc(s: ^Screen, label, text: string) {
	ui.click(&s.h, label)
	ui.press_key(&s.h, .A, ui.COMMAND)
	ui.type_text(&s.h, text)
}

@(test)
the_inspector_asks_for_a_selection :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, shows(&s, "Select tracks to see their tags"))
	testing.expect(t, shows(&s, "⌘A selects every track"))
}

@(test)
one_track_shows_its_tags_and_its_file :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	ui.run_frame(&s.h)
	for value in ([]string{"Small Hours · Marlowe Kite", "MP3 · 64 kbps CBR · 44.1 kHz", "1 KB", "ID3v2.3"}) {
		testing.expectf(t, shows(&s, value), "%s is missing", value)
	}
	Expected :: struct {
		field, value: string,
	}
	for e in ([]Expected{{"Title", "Paper Satellites"}, {"Album artist", "Various Artists"}, {"Year", "2019"}, {"Track", "3"}, {"Track total", "12"}, {"Disc", "1"}, {"Disc total", "2"}, {"Comment", "Recorded in one take."}}) {
		value, found := field_value(&s, e.field)
		testing.expectf(t, found && value == e.value, "%s: %q", e.field, value)
	}
	testing.expect(t, shows(&s, "Paper Satellites"))
}

@(test)
several_tracks_show_what_they_share :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}, {"v24_unicode.mp3", "2.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.press_key(&s.h, .A, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "2 tracks selected"))
	testing.expect(t, shows(&s, "2 KB total"))
	title, _ := ui.find_widget(&s.h.ui, "Title")
	testing.expect_value(t, title.value, "")
	testing.expect(t, shows(&s, "Multiple values"))
}

@(test)
an_unreadable_track_explains_why :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"tiny_tag.mp3", "broken.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "broken"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Could not read this file"))
	testing.expect(
		t,
		shows(
			&s,
			"This file is damaged, or it is not an MP3: Colophon could not make sense of it.",
		),
	)
	testing.expect(t, shows(&s, "3 bytes"))
	testing.expect(t, shows(&s, "Show in Finder"))
}

@(test)
the_inspector_writes_numbers_in_french :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(t, ui.catalog_tr(&c, "{} kbps"), "{} kbit/s")
	testing.expect_value(t, ui.catalog_tr(&c, "{}.{} kHz"), "{},{} kHz")
	testing.expect_value(t, ui.catalog_tr(&c, "{} KB"), "{} Ko")
	testing.expect_value(
		t,
		ui.catalog_tr(&c, "Select tracks to see their tags"),
		"Sélectionnez des morceaux pour voir leurs tags",
	)
}

@(test)
a_section_folds_and_stays_folded :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	_, found := field_value(&s, "Title")
	testing.expect(t, found)
	header, _ := ui.find_widget(&s.h.ui, "Tags")
	testing.expect(t, .Expanded in header.states)
	testing.expect(t, ui.click(&s.h, "Tags"))
	ui.run_frame(&s.h)
	_, found = field_value(&s, "Title")
	testing.expect(t, !found)
	header, _ = ui.find_widget(&s.h.ui, "Tags")
	testing.expect(t, .Expanded not_in header.states)
	// Hidden and shown again, the inspector remembers.
	execute(&s.app, engine.Toggle_Inspector{})
	ui.run_frame(&s.h)
	execute(&s.app, engine.Toggle_Inspector{})
	ui.run_frame(&s.h)
	_, found = field_value(&s, "Title")
	testing.expect(t, !found)
}

@(test)
typing_in_a_field_edits_the_selection_and_escape_takes_it_back :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	e := &s.app.engine
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	retype(&s, "Title", "Neon Overpass")
	testing.expect_value(t, len(e.edits.pending), 1)
	// One step for the whole of the typing.
	testing.expect_value(t, len(e.edits.undo), 1)
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Neon Overpass"))
	value, _ := field_value(&s, "Title")
	testing.expect_value(t, value, "Neon Overpass")

	retype(&s, "Year", "2024")
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	value, _ = field_value(&s, "Year")
	testing.expect_value(t, value, "2019")
	testing.expect_value(t, len(e.edits.undo), 1)
	// Letters are not a year: the field keeps them, and changes nothing.
	retype(&s, "Year", "20x4")
	year, _ := field_value(&s, "Year")
	testing.expect_value(t, year, "20x4")
	testing.expect_value(t, len(e.edits.undo), 1)
}

// The genres suggested by the open list, in its order.
@(private = "file")
suggestions :: proc(s: ^Screen) -> []string {
	list := ui.child_id(ui.widget_id("Genre"), "suggestions")
	found := make([dynamic]string, context.temp_allocator)
	for w in s.h.ui.widgets do if w.parent == list do append(&found, w.label)
	return found[:]
}

@(test)
typing_a_genre_suggests_those_that_start_with_it_first :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	retype(&s, "Genre", "rock")
	ui.run_frame(&s.h)
	suggested := suggestions(&s)
	testing.expect(t, len(suggested) > 1 && suggested[0] == "Rock")
	has_classic := false
	for g in suggested do has_classic ||= g == "Classic Rock"
	testing.expect(t, has_classic)
}

@(test)
the_arrow_keys_and_enter_pick_a_genre :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	retype(&s, "Genre", "folk-r")
	ui.press_key(&s.h, .Down)
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect_value(t, len(suggestions(&s)), 0)
	value, _ := field_value(&s, "Genre")
	testing.expect_value(t, value, "Folk-Rock")
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
}

@(test)
a_click_picks_a_genre :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	retype(&s, "Genre", "folk")
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Folklore"))
	ui.run_frame(&s.h)
	testing.expect_value(t, len(suggestions(&s)), 0)
	value, _ := field_value(&s, "Genre")
	testing.expect_value(t, value, "Folklore")
}

@(test)
escape_closes_the_list_then_puts_the_genre_back :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	retype(&s, "Genre", "rock")
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect_value(t, len(suggestions(&s)), 0)
	value, _ := field_value(&s, "Genre")
	testing.expect_value(t, value, "rock")
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	value, _ = field_value(&s, "Genre")
	testing.expect_value(t, value, "Folk")
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
}

@(test)
the_button_shows_every_genre :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Marlowe Kite")
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Show suggestions"))
	ui.run_frame(&s.h)
	suggested := suggestions(&s)
	testing.expect(t, len(suggested) > 0 && suggested[0] == "A Cappella")
}

// What the window asked of the desktop.
@(private = "file")
Asked :: struct {
	revealed: [dynamic]string,
}

@(test)
an_unreadable_file_shows_in_the_file_manager :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"tiny_tag.mp3", "track07.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	asked: Asked
	asked.revealed = make([dynamic]string, context.temp_allocator)
	s.app.dialogs.data = &asked
	s.app.dialogs.reveal = proc(app: ^App, data: rawptr, path: string) {
		append(&(^Asked)(data).revealed, strings.clone(path, context.temp_allocator))
	}
	ui.click(&s.h, "track07")
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Show in Finder"))
	testing.expect(
		t,
		len(asked.revealed) == 1 && asked.revealed[0] == s.app.engine.library.tracks[0].path,
	)
}

@(test)
the_details_of_an_unreadable_file_go_to_the_clipboard :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_showing(t, &s, {{"tiny_tag.mp3", "track07.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "track07")
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Copy details"))
	copied := strings.to_string(s.h.clipboard)
	testing.expect(
		t,
		strings.contains(copied, fmt.tprintf("File: %s", s.app.engine.library.tracks[0].path)),
	)
	testing.expect(t, strings.contains(copied, "Size: 3 bytes"))
	testing.expect(t, strings.contains(copied, "Error: The file holds no MPEG audio"))
}

// The tracks and the unreadable file, in both themes.
@(test)
the_inspector_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		folder := screen_showing(
			t,
			&s,
			{
				{"v23_full.mp3", "01.mp3"},
				{"v23_full.mp3", "02.mp3"},
				{"v24_full.mp3", "03.mp3"},
				{"tiny_tag.mp3", "track07.mp3"},
			},
			kind,
		)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		e := &s.app.engine
		// Three tracks with a year and a genre changed, as 1.0.0's capture.
		execute(&s.app, engine.Select{e.listed[0]})
		execute(&s.app, engine.Select_Range{e.listed[2]})
		execute(&s.app, engine.Apply_Edit{{.Year, 2024}})
		execute(&s.app, engine.Apply_Edit{{.Genre, "Synthwave"}})
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(
			t,
			&s,
			kind == .Dark ? "inspector-tracks-dark.png" : "inspector-tracks-light.png",
		)
		execute(&s.app, engine.Select{e.listed[3]})
		ui.run_frame(&s.h)
		expect_screen(
			t,
			&s,
			kind == .Dark ? "inspector-unreadable-dark.png" : "inspector-unreadable-light.png",
		)
	}
}

// The texts of the File section, as 1.0.0 wrote them.
@(test)
sizes_and_audio_read_as_in_1_0_0 :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, size_text(999), "999\u00A0bytes")
	testing.expect_value(t, size_text(4_096), "4\u00A0KB")
	testing.expect_value(t, size_text(25_400_000), "25.4\u00A0MB")
	testing.expect_value(t, size_text(8_349_999), "8.3\u00A0MB")
	testing.expect_value(t, size_text(1_250_000_000), "1.3\u00A0GB")
	line :: proc(rate: int, mode: lib.Bitrate_Mode) -> engine.Summary {
		return {audio = engine.Audio_Line{bitrate_kbps = 128, sample_rate = rate, mode = mode}}
	}
	testing.expect_value(
		t,
		audio_text(line(44_100, .Constant)),
		"MP3 · 128\u00A0kbps\u00A0CBR · 44.1\u00A0kHz",
	)
	testing.expect_value(
		t,
		audio_text(line(48_000, .Variable)),
		"MP3 · 128\u00A0kbps\u00A0VBR · 48\u00A0kHz",
	)
	testing.expect_value(
		t,
		audio_text(line(22_050, .Constant)),
		"MP3 · 128\u00A0kbps\u00A0CBR · 22.1\u00A0kHz",
	)
	testing.expect_value(t, audio_text({audio = engine.Mixed{}}), "Multiple values")
	testing.expect_value(
		t,
		album_and_artist({album = "Small Hours", artist = "Marlowe Kite"}),
		"Small Hours · Marlowe Kite",
	)
	testing.expect_value(
		t,
		album_and_artist({album = "Small Hours", artist = engine.Mixed{}}),
		"Small Hours",
	)
}
