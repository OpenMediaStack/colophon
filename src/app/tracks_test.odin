package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../engine"
import ui "../ui"

// The main screen at 1440 by 900 showing the tags of one fixture, "Paper Satellites"
// by Marlowe Kite, track 3 of Small Hours, 2019, Folk.
@(private = "file")
screen_with_a_track :: proc(
	t: ^testing.T,
	s: ^Screen,
	size := [2]f32{1440, 900},
) -> (
	folder: string,
) {
	screen_init(s, size)
	folder = folder_with_fixtures(t, {{"v23_full.mp3", "Small Hours/07.mp3"}})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "1 track")
	return
}

// The main screen over files that only start like an MP3, named a to e, which the
// table lists by their names.
@(private = "file")
screen_with_named_files :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 900})
	folder = folder_with(t, {"a.mp3", "b.mp3", "c.mp3", "d.mp3", "e.mp3"})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "5 tracks")
	return
}

// Opens the column chooser with its button and picks item.
@(private = "file")
choose :: proc(t: ^testing.T, s: ^Screen, item: string) {
	testing.expect(t, ui.click(&s.h, "Choose columns"))
	testing.expectf(t, ui.click(&s.h, item), "%q is not in the chooser", item)
	ui.run_frame(&s.h)
}

// The left edge of a column's name in the header.
@(private = "file")
header_x :: proc(s: ^Screen, name: string) -> f32 {
	cell, _ := ui.find_widget(&s.h.ui, fmt.tprintf("Sort by %s", name))
	return cell.rect.x
}

// Where the edge of a column is dragged to resize it: just right of its name.
@(private = "file")
resize_handle :: proc(s: ^Screen, name: string) -> [2]f32 {
	cell, _ := ui.find_widget(&s.h.ui, fmt.tprintf("Sort by %s", name))
	return {cell.rect.x + cell.rect.w + 3, cell.rect.y + cell.rect.h / 2}
}

@(private = "file")
drag :: proc(s: ^Screen, from, to: [2]f32) {
	ui.move_mouse(&s.h, from)
	ui.press(&s.h)
	ui.move_mouse(&s.h, to)
	ui.release(&s.h)
	ui.run_frame(&s.h)
}

@(private = "file")
first_listed_name :: proc(s: ^Screen) -> string {
	e := &s.app.engine
	return filepath.stem(e.library.tracks[e.listed[0]].path)
}

@(test)
a_track_shows_its_tags_in_the_default_columns :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	for value in ([]string{"03", "Paper Satellites", "Marlowe Kite", "Small Hours", "2019", "Folk", "0:00"}) {
		testing.expectf(t, shows(&s, value), "%s is missing", value)
	}
	testing.expect(t, !shows(&s, "Unreadable"))
	testing.expect(t, !shows(&s, "Horizontal scroll bar"))
	// The bitrate, the tag formats and the file's place are hidden by default.
	testing.expect(t, !shows(&s, "Sort by Bitrate"))
	testing.expect(t, !shows(&s, "ID3v2.3"))
	testing.expect(t, !shows(&s, "07.mp3"))
}

@(test)
a_file_whose_tags_cannot_be_read_is_marked :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with(t, {"broken.mp3"})
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "1 track")
	testing.expect(t, shows(&s, "broken"))
	testing.expect(t, shows(&s, "Unreadable"))
}

@(test)
the_chooser_shows_and_hides_columns_but_the_title :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	choose(t, &s, "Tags")
	testing.expect(t, shows(&s, "ID3v2.3"))
	choose(t, &s, "Bitrate")
	testing.expect(t, shows(&s, "64"))
	choose(t, &s, "File")
	testing.expect(t, shows(&s, "07.mp3"))
	choose(t, &s, "Folder")
	// The folder as the engine names it, with the system's separators.
	album, _ := filepath.join(
		{s.app.engine.library.roots[0], "Small Hours"},
		context.temp_allocator,
	)
	testing.expect(t, shows(&s, display_folder(album, s.app.home)))
	choose(t, &s, "Genre")
	testing.expect(t, !shows(&s, "Folk"))
	testing.expect(t, !shows(&s, "Sort by Genre"))
	// The title cannot be hidden: its item is disabled.
	testing.expect(t, ui.click(&s.h, "Choose columns"))
	title, _ := ui.find_widget(&s.h.ui, "Title")
	testing.expect(t, .Disabled in title.states && .Checked in title.states)
	ui.press_key(&s.h, .Escape)
	choose(t, &s, "Reset to default columns")
	testing.expect(t, shows(&s, "Folk"))
	testing.expect(t, !shows(&s, "ID3v2.3"))
}

@(test)
a_right_click_on_the_header_opens_the_chooser :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Sort by Album", .Right))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Reset to default columns"))
}

@(test)
a_click_on_a_column_name_sorts_by_it :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with(t, {"b.mp3", "c.mp3", "a.mp3"})
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "3 tracks")
	ui.click(&s.h, "Sort by Title")
	testing.expect_value(t, first_listed_name(&s), "a")
	ui.click(&s.h, "Sort by Title")
	testing.expect_value(t, first_listed_name(&s), "c")
}

@(test)
resizing_a_column_widens_the_table_rather_than_squeezing_the_others :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	album := header_x(&s, "Album")
	year := header_x(&s, "Year")
	handle := resize_handle(&s, "Artist")
	drag(&s, handle, {handle.x + 200, handle.y})
	// The shared widths are rounded to whole points when they are kept.
	testing.expect(t, abs(header_x(&s, "Album") - (album + 200)) < 2)
	testing.expect(t, abs(header_x(&s, "Year") - (year + 200)) < 2)
	testing.expect(t, shows(&s, "Horizontal scroll bar"))

	// Never narrower than 40 points.
	handle = resize_handle(&s, "Artist")
	drag(&s, handle, {handle.x - 500, handle.y})
	widths, sized := s.app.engine.view.column_widths.?
	testing.expect(t, sized && widths[.Artist] == 40)

	// Back to the shared widths.
	choose(t, &s, "Reset to default columns")
	testing.expect_value(t, header_x(&s, "Album"), album)
	testing.expect(t, !shows(&s, "Horizontal scroll bar"))
}

@(test)
a_double_click_on_a_separator_fits_the_column_to_its_content :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	album := header_x(&s, "Album")
	handle := resize_handle(&s, "Artist")
	ui.move_mouse(&s.h, handle)
	ui.press(&s.h)
	ui.release(&s.h)
	ui.press(&s.h, clicks = 2)
	ui.release(&s.h)
	ui.run_frame(&s.h)
	// "Marlowe Kite" needs much less room than the share the artist had.
	testing.expect(t, header_x(&s, "Album") < album - 20)
}

@(test)
dragging_a_column_by_its_name_moves_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	e := &s.app.engine
	year, _ := ui.find_widget(&s.h.ui, "Sort by Year")
	title_left := header_x(&s, "Title")
	drag(&s, ui.rect_center(year.rect), {title_left + 4, ui.rect_center(year.rect).y})
	testing.expect_value(t, e.view.column_order[0], engine.Table_Column.Year)
	testing.expect_value(t, e.sort, nil)
	testing.expect(t, header_x(&s, "Year") < header_x(&s, "Title"))

	choose(t, &s, "Reset to default columns")
	testing.expect_value(t, e.view.column_order[0], engine.Table_Column.Title)

	// Dropped where it was: neither moved nor sorted.
	year, _ = ui.find_widget(&s.h.ui, "Sort by Year")
	centre := ui.rect_center(year.rect)
	drag(&s, centre, {centre.x + 8, centre.y})
	testing.expect_value(t, e.view.column_order[3], engine.Table_Column.Year)
	testing.expect_value(t, e.sort, nil)
}

@(test)
a_narrow_window_scrolls_every_column_sideways :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_track(t, &s, {960, 600})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, shows(&s, "Horizontal scroll bar"))
	title := header_x(&s, "Title")
	album := header_x(&s, "Album")
	cell, _ := ui.find_widget(&s.h.ui, "Paper Satellites")
	ui.move_mouse(&s.h, {300, 300})
	s.h.ui.input.wheel = {100, 0}
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, abs(header_x(&s, "Title") - (title - 100)) < 1)
	testing.expect(t, abs(header_x(&s, "Album") - (album - 100)) < 1)
	moved, _ := ui.find_widget(&s.h.ui, "Paper Satellites")
	testing.expect(t, abs(moved.rect.x - (cell.rect.x - 100)) < 1)
}

@(test)
a_click_on_a_row_selects_it_with_its_keys :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_named_files(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	e := &s.app.engine
	track :: proc(e: ^engine.Engine, name: string) -> engine.Track_Id {
		for t, i in e.library.tracks do if filepath.stem(t.path) == name do return engine.Track_Id(i)
		return -1
	}
	testing.expect(t, ui.click(&s.h, "c"))
	testing.expect_value(t, len(e.selection.tracks), 1)
	testing.expect(t, engine.is_selected(&e.selection, track(e, "c")))
	s.h.ui.input.modifiers = ui.COMMAND
	ui.click(&s.h, "e")
	s.h.ui.input.modifiers = {.Shift}
	testing.expect_value(t, len(e.selection.tracks), 2)
	ui.click(&s.h, "a")
	s.h.ui.input.modifiers = {}
	testing.expect(t, engine.is_selected(&e.selection, track(e, "a")))
	testing.expect(t, len(e.selection.tracks) >= 3)
	testing.expect(t, shows(&s, fmt.tprintf("5 tracks · %d selected", len(e.selection.tracks))))
}

@(test)
the_keyboard_moves_and_extends_the_selection :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_named_files(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	e := &s.app.engine
	ui.click(&s.h, "b")
	ui.press_key(&s.h, .Down)
	testing.expect_value(t, len(e.selection.tracks), 1)
	testing.expect_value(t, filepath.stem(e.library.tracks[e.selection.tracks[0]].path), "c")
	ui.press_key(&s.h, .Up)
	testing.expect_value(t, filepath.stem(e.library.tracks[e.selection.tracks[0]].path), "b")
	ui.press_key(&s.h, .Down, {.Shift})
	testing.expect_value(t, len(e.selection.tracks), 2)
	ui.press_key(&s.h, .Up, {.Shift})
	testing.expect_value(t, len(e.selection.tracks), 1)
	ui.press_key(&s.h, .A, ui.COMMAND)
	testing.expect_value(t, len(e.selection.tracks), 5)
}

@(test)
durations_read_as_in_a_player :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, duration_text(5 * time.Second), "0:05")
	testing.expect_value(t, duration_text(221 * time.Second), "3:41")
	testing.expect_value(t, duration_text(3723 * time.Second), "1:02:03")
}

@(test)
folders_inside_the_home_start_with_a_tilde :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	home, _ := filepath.join({"", "Users", "marlowe"}, context.temp_allocator)
	music, _ := filepath.join({home, "Music"}, context.temp_allocator)
	testing.expect_value(
		t,
		display_folder(music, home),
		fmt.tprintf("~%cMusic", filepath.SEPARATOR),
	)
	testing.expect_value(t, display_folder(home, home), "~")
	elsewhere, _ := filepath.join({"", "Volumes", "Music"}, context.temp_allocator)
	testing.expect_value(t, display_folder(elsewhere, home), elsewhere)
	// A folder whose name only starts like the home.
	other, _ := filepath.join({"", "Users", "marlowe2", "Music"}, context.temp_allocator)
	testing.expect_value(t, display_folder(other, home), other)
	testing.expect_value(t, display_folder(music, ""), music)
}

// The text of a cell of the screen's table.
@(private = "file")
cell :: proc(s: ^Screen, row: int, column: engine.Table_Column) -> string {
	return track_cell(&s.app, row, int(column))
}

@(test)
the_cells_follow_the_file :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	// Without a title, with a variable bitrate, with every tag, unreadable.
	folder := folder_with_fixtures(
		t,
		{{"no_tag.mp3", "a.mp3"}, {"vbr_mono.mp3", "b.mp3"}, {"v23_full.mp3", "c.mp3"}},
	)
	defer remove_folder(folder)
	testing.expect(
		t,
		os.write_entire_file(fmt.tprintf("%s/d.mp3", folder), transmute([]u8)string("ID3")) == nil,
	)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "4 tracks")
	testing.expect_value(t, cell(&s, 0, .Title), "a")
	testing.expect_value(t, track_cell(&s.app, 0, -1), "")
	testing.expect_value(t, cell(&s, 0, .Artist), "")
	testing.expect(t, .Placeholder in track_states(&s.app, 0))
	testing.expect(t, strings.has_prefix(cell(&s, 1, .Bitrate), "VBR "))
	testing.expect_value(t, track_cell(&s.app, 2, -1), "03")
	testing.expect_value(t, cell(&s, 2, .Bitrate), "64")
	testing.expect_value(t, cell(&s, 2, .Tags), "ID3v2.3")
	testing.expect_value(t, cell(&s, 2, .File), "c.mp3")
	testing.expect_value(t, cell(&s, 3, .Title), "d")
	testing.expect_value(t, cell(&s, 3, .Time), "")
	testing.expect(t, .Error in track_states(&s.app, 3))
	testing.expect(t, .Placeholder not_in track_states(&s.app, 3))
	// Pending tags show, marked as modified.
	execute(&s.app, engine.Select{s.app.engine.listed[2]})
	execute(&s.app, engine.Apply_Edit{{.Title, "Neon Overpass"}})
	testing.expect_value(t, cell(&s, 2, .Title), "Neon Overpass")
	testing.expect(t, .Modified in track_states(&s.app, 2))
}

// The columns' names in French, from 1.0.0's catalogue: checked on the catalogue
// itself, since the one in use is shared by every test.
@(test)
the_headers_and_the_chooser_speak_french_when_selected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(t, ui.catalog_tr(&c, "Title"), "Titre")
	testing.expect_value(t, ui.catalog_tr(&c, "Artist"), "Artiste")
	testing.expect_value(t, ui.catalog_tr(&c, "Year"), "Année")
	testing.expect_value(t, ui.catalog_tr(&c, "Time"), "Durée")
	testing.expect_value(t, ui.catalog_tr(&c, "Choose columns"), "Choisir les colonnes")
	testing.expect_value(t, ui.catalog_tr(&c, "Columns"), "Colonnes")
	testing.expect_value(
		t,
		ui.catalog_tr(&c, "Reset to default columns"),
		"Rétablir les colonnes par défaut",
	)
}

// Rows in every state, the selection outlined, in both themes at two sizes.
@(test)
the_table_matches_its_references :: proc(t: ^testing.T) {
	copies := [?][2]string {
		{"v23_full.mp3", "Music/01.mp3"},
		{"v23_full.mp3", "Music/02.mp3"},
		{"v24_full.mp3", "Music/03.mp3"},
		{"no_tag.mp3", "Music/04 Track without a title tag.mp3"},
		{"v23_full.mp3", "Music/05.mp3"},
		{"v23_full.mp3", "Music/07.mp3"},
		{"v23_full.mp3", "Music/08.mp3"},
		{"v23_full.mp3", "Music/09.mp3"},
		{"v23_full.mp3", "Music/10.mp3"},
		{"v23_full.mp3", "Music/11.mp3"},
		{"v23_full.mp3", "Music/12.mp3"},
	}
	sizes := [?][2]f32{{1440, 900}, {960, 600}}
	for size in sizes {
		for kind in ui.Theme_Kind {
			s: Screen
			screen_init(&s, size, kind)
			defer screen_destroy(&s)
			folder := folder_with_fixtures(t, copies[:])
			defer remove_folder(folder)
			// A file that only starts like an MP3, whose tags cannot be read.
			damaged := fmt.tprintf("%s/Music/06 Damaged file.mp3", folder)
			testing.expect(t, os.write_entire_file(damaged, transmute([]u8)string("ID3")) == nil)
			// A folder named the same on every run, since the sidebar shows its name.
			open_folder_of(t, &s, fmt.tprintf("%s/Music", folder))
			wait_until_shown(t, &s, "12 tracks")
			e := &s.app.engine
			// Unsaved changes on the fifth, a run of three selected and one apart, the
			// second playing, the table focused for the selection's outline.
			engine.execute(e, engine.Select{e.listed[4]})
			engine.execute(e, engine.Apply_Edit{{.Title, "Neon Overpass"}})
			engine.execute(e, engine.Select{e.listed[6]})
			engine.execute(e, engine.Select_Range{e.listed[8]})
			engine.execute(e, engine.Toggle_Selected{e.listed[10]})
			e.playback.track = e.listed[1]
			ui.request_focus(&s.h.ui, ui.widget_id("Tracks"))
			ui.run_frame(&s.h)
			ui.run_frame(&s.h)
			name := fmt.tprintf(
				"tracks-%s-%dx%d.png",
				kind == .Dark ? "dark" : "light",
				int(size.x),
				int(size.y),
			)
			expect_screen(t, &s, name)
		}
	}
}
