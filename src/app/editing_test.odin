package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "../engine"
import ui "../ui"

// The main screen over count copies of "Paper Satellites" by Marlowe Kite, from 2019,
// the first one selected, as 1.0.0's editing tests.
@(private = "file")
screen_with_copies :: proc(
	t: ^testing.T,
	s: ^Screen,
	count: int,
	kind := ui.Theme_Kind.Dark,
) -> (
	folder: string,
) {
	screen_init(s, {1440, 900}, kind)
	copies := make([][2]string, count, context.temp_allocator)
	for &c, i in copies do c = {"v23_full.mp3", fmt.tprintf("%d.mp3", i + 1)}
	folder = folder_with_fixtures(t, copies)
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, ui.tr_n("{n} track", "{n} tracks", count))
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	return
}

// The main screen over "Paper Satellites" by Marlowe Kite and "Café" by 坂本龍一, the
// first one selected.
@(private = "file")
screen_with_two_tracks :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 900})
	folder = folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v24_unicode.mp3", "2.mp3"}})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "2 tracks")
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	return
}

// The text of the cell being edited in place, if one is: the editor is the table's own
// field.
@(private = "file")
editor :: proc(s: ^Screen) -> (value: string, editing: bool) {
	if s.app.table.editing == nil do return
	for w in s.h.ui.widgets {
		if w.role == .Text_Field && w.parent == ui.widget_id("Tracks") do return w.value, true
	}
	return
}

// Double-clicks the first cell of the table that shows text: a row and the inspector
// may show the same words.
@(private = "file")
double_click_cell :: proc(s: ^Screen, text: string) -> bool {
	for w in s.h.ui.widgets {
		if w.role != .Cell || w.label != text do continue
		ui.move_mouse(&s.h, ui.rect_center(w.rect))
		for i in 1 ..= 2 {
			ui.press(&s.h, .Left, i)
			ui.release(&s.h)
		}
		return true
	}
	return false
}

@(private = "file")
modified_count :: proc(s: ^Screen) -> int {
	return len(s.app.engine.edits.pending)
}

@(private = "file")
selected_count :: proc(s: ^Screen) -> int {
	return len(s.app.engine.selection.tracks)
}

@(private = "file")
select_all :: proc(s: ^Screen) {
	ui.press_key(&s.h, .A, ui.COMMAND)
	ui.run_frame(&s.h)
}

@(private = "file")
pick :: proc(t: ^testing.T, s: ^Screen, item: string) {
	testing.expectf(t, ui.click(&s.h, item), "%q is not in the menu", item)
	ui.run_frame(&s.h)
}

@(test)
a_double_click_edits_a_cell :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, double_click_cell(&s, "Marlowe Kite"))
	value, editing := editor(&s)
	testing.expect(t, editing)
	testing.expect_value(t, value, "Marlowe Kite")
	ui.type_text(&s.h, "Cassette Bloom")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	_, editing = editor(&s)
	testing.expect(t, !editing)
	testing.expect(t, shows(&s, "Cassette Bloom"))
	testing.expect_value(t, modified_count(&s), 1)
	artist, _ := field_value(&s, "Artist")
	testing.expect_value(t, artist, "Cassette Bloom")
}

@(test)
a_double_click_in_a_selection_edits_every_selected_track :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 3)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	select_all(&s)
	testing.expect(t, double_click_cell(&s, "Marlowe Kite"))
	ui.type_text(&s.h, "Cassette Bloom")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect_value(t, selected_count(&s), 3)
	testing.expect_value(t, modified_count(&s), 3)
	testing.expect(t, !shows(&s, "Marlowe Kite"))
}

@(test)
a_click_in_a_selection_keeps_it_while_a_double_click_may_follow :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 3)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	select_all(&s)
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	testing.expect_value(t, selected_count(&s), 3)
	ui.wait(&s.h, 0.6)
	testing.expect_value(t, selected_count(&s), 1)
}

@(test)
another_click_cancels_the_pending_shrink :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 3)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	select_all(&s)
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	s.h.ui.input.modifiers = ui.COMMAND
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	s.h.ui.input.modifiers = {}
	ui.wait(&s.h, 0.6)
	testing.expect_value(t, selected_count(&s), 2)
}

@(test)
return_edits_the_title_of_the_selected_track :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Enter)
	value, editing := editor(&s)
	testing.expect(t, editing)
	testing.expect_value(t, value, "Paper Satellites")
	ui.type_text(&s.h, "Neon Overpass")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Neon Overpass"))
	testing.expect(t, !shows(&s, "Paper Satellites"))
}

@(test)
escape_puts_the_cell_back :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, double_click_cell(&s, "Marlowe Kite"))
	ui.type_text(&s.h, "Cassette Bloom")
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	_, editing := editor(&s)
	testing.expect(t, !editing)
	testing.expect(t, shows(&s, "Marlowe Kite"))
	testing.expect_value(t, modified_count(&s), 0)
	testing.expect(t, !engine.can_undo(&s.app.engine))
}

@(test)
a_year_cell_refuses_letters :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, double_click_cell(&s, "2019"))
	ui.type_text(&s.h, "20x4")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	value, editing := editor(&s)
	testing.expect(t, editing)
	testing.expect_value(t, value, "20x4")
	testing.expect_value(t, modified_count(&s), 0)
}

@(test)
the_time_cell_is_not_a_tag :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, double_click_cell(&s, "0:00"))
	_, editing := editor(&s)
	testing.expect(t, !editing)
}

@(test)
command_s_saves_what_is_typed_in_a_cell :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, double_click_cell(&s, "Paper Satellites"))
	ui.type_text(&s.h, "Neon Overpass")
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	e := &s.app.engine
	testing.expect_value(t, modified_count(&s), 0)
	// What the file holds now, read back by the save.
	testing.expect_value(t, e.library.tracks[0].metadata.tags.title.? or_else "", "Neon Overpass")
}

@(test)
the_arrow_keys_move_the_selection_again_after_an_edit :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 2)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Enter)
	ui.type_text(&s.h, "Neon Overpass")
	ui.press_key(&s.h, .Enter)
	ui.press_key(&s.h, .Down)
	e := &s.app.engine
	testing.expect(t, e.selection.focus == e.listed[1])
	testing.expect_value(t, selected_count(&s), 1)
}

@(test)
clicking_another_track_ends_the_edit :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 2)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Enter)
	ui.type_text(&s.h, "Neon Overpass")
	// The first row shows the new title as it is typed: the second still has the old.
	testing.expect(t, ui.click(&s.h, "Paper Satellites"))
	ui.run_frame(&s.h)
	_, editing := editor(&s)
	testing.expect(t, !editing)
	e := &s.app.engine
	testing.expect(t, e.selection.focus == e.listed[1])
	testing.expect(t, shows(&s, "Neon Overpass"))
}

@(test)
a_moved_column_edits_where_it_shows :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	year, _ := ui.find_widget(&s.h.ui, "Sort by Year")
	title, _ := ui.find_widget(&s.h.ui, "Sort by Title")
	centre := ui.rect_center(year.rect)
	drag(&s, centre, {title.rect.x + 4, centre.y})
	testing.expect(t, double_click_cell(&s, "2019"))
	value, editing := editor(&s)
	testing.expect(t, editing)
	testing.expect_value(t, value, "2019")
	cell, _ := ui.find_widget(&s.h.ui, "2019")
	for w in s.h.ui.widgets {
		if w.role == .Text_Field && w.parent == ui.widget_id("Tracks") {
			testing.expect(t, abs(w.rect.x - cell.rect.x) < 12)
		}
	}
}

@(test)
enter_keeps_a_new_title :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	retype(&s, "Title", "Neon Overpass")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Neon Overpass"))
	testing.expect(t, shows(&s, "Unsaved changes"))
	testing.expect(t, shows(&s, "1 file with unsaved changes"))
}

@(test)
the_disc_is_edited_like_the_track :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	retype(&s, "Disc", "2")
	ui.press_key(&s.h, .Enter)
	retype(&s, "Disc total", "3")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	disc, _ := field_value(&s, "Disc")
	testing.expect_value(t, disc, "2")
	total, _ := field_value(&s, "Disc total")
	testing.expect_value(t, total, "3")
	testing.expect(t, shows(&s, "1 file with unsaved changes"))
}

@(test)
leaving_a_field_keeps_what_was_typed :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	retype(&s, "Genre", "Synthwave")
	testing.expect(t, ui.click(&s.h, "Album"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Synthwave"))
	testing.expect(t, shows(&s, "1 file with unsaved changes"))
}

@(test)
a_year_that_is_not_one_is_refused_and_put_back :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	retype(&s, "Year", "20x4")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	year, _ := field_value(&s, "Year")
	testing.expect_value(t, year, "20x4")
	testing.expect(t, !shows(&s, "1 file with unsaved changes"))
	testing.expect(t, ui.click(&s.h, "Album"))
	ui.run_frame(&s.h)
	year, _ = field_value(&s, "Year")
	testing.expect_value(t, year, "2019")
}

@(test)
several_tracks_take_the_same_value :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	select_all(&s)
	testing.expect(t, shows(&s, "Multiple values"))
	retype(&s, "Title", "Same title")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "2 files with unsaved changes"))
	testing.expect(t, !shows(&s, "Café"))
	testing.expect(t, !shows(&s, "Paper Satellites"))
}

@(test)
numbering_the_selection_numbers_every_track_of_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	select_all(&s)
	testing.expect(t, ui.click(&s.h, "Marlowe Kite", .Right))
	pick(t, &s, "Number Tracks")
	summary, inspected := s.app.inspector.inspection.(engine.Summary)
	if !testing.expect(t, inspected) do return
	_, mixed := summary.track.(engine.Mixed)
	testing.expect(t, mixed)
	testing.expect(t, .Track in summary.modified)
	total, _ := field_value(&s, "Track total")
	testing.expect_value(t, total, "2")
	testing.expect(t, shows(&s, "2 files with unsaved changes"))
}

@(test)
a_right_click_selects_the_row_and_opens_its_menu :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Café", .Right))
	testing.expect_value(t, selected_count(&s), 1)
	pick(t, &s, "Number Tracks")
	track, _ := field_value(&s, "Track")
	testing.expect_value(t, track, "1")
	total, _ := field_value(&s, "Track total")
	testing.expect_value(t, total, "1")
}

@(test)
a_right_click_on_a_selected_row_keeps_the_selection :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_two_tracks(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	select_all(&s)
	testing.expect(t, ui.click(&s.h, "Marlowe Kite", .Right))
	testing.expect_value(t, selected_count(&s), 2)
	_, found := ui.find_widget(&s.h.ui, "Select Album")
	testing.expect(t, found)
}

@(test)
the_genre_cell_of_the_table_suggests_genres_too :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_copies(t, &s, 1)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, double_click_cell(&s, "Folk"))
	ui.type_text(&s.h, "folk-r")
	ui.run_frame(&s.h)
	suggested := suggestions(&s)
	testing.expect_value(t, len(suggested), 1)
	testing.expect(t, len(suggested) == 1 && suggested[0] == "Folk-Rock")
	ui.press_key(&s.h, .Down)
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect_value(t, len(suggestions(&s)), 0)
	testing.expect(t, shows(&s, "Folk-Rock"))
	genre, _ := field_value(&s, "Genre")
	testing.expect_value(t, genre, "Folk-Rock")
}

// The counts in French, from 1.0.0's catalogue: checked on the catalogue itself, since
// the one in use is shared by every test.
@(test)
the_counts_of_the_status_bar_speak_french_when_selected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(
		t,
		ui.catalog_tr_n(
			&c,
			"{n} file with unsaved changes",
			"{n} files with unsaved changes",
			1,
			"",
		),
		"1 fichier avec des modifications non enregistrées",
	)
	testing.expect_value(t, ui.catalog_tr_n(&c, "{n} track", "{n} tracks", 3, ""), "3 morceaux")
	testing.expect_value(
		t,
		ui.catalog_tr_n(&c, "{n} selected", "{n} selected", 3, ""),
		"3 sélectionnés",
	)
}

// Three tracks selected and the artist of one edited in place, in both themes.
@(test)
editing_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		// The folder shows as the home, "~": the same on every platform.
		folder := screen_with_copies(t, &s, 3, kind)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		delete(s.app.home)
		s.app.home = strings.clone(folder)
		select_all(&s)
		testing.expect(t, double_click_cell(&s, "Marlowe Kite"))
		ui.type_text(&s.h, "Cassette Bloom")
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "editing-dark.png" : "editing-light.png")
	}
}
