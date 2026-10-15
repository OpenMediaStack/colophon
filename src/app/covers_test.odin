package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen over a track with a cover, "With a cover", and one without, "Paper
// Satellites", in a Music folder, with the cover written beside as cover.png for the
// image dialog to answer, and notes.txt, which is no image.
@(private = "file")
screen_with_covers :: proc(
	t: ^testing.T,
	s: ^Screen,
	kind := ui.Theme_Kind.Dark,
) -> (
	folder: string,
) {
	screen_init(s, {1440, 900}, kind)
	folder = folder_with_fixtures(
		t,
		{{"v23_cover.mp3", "Music/1.mp3"}, {"v23_full.mp3", "Music/2.mp3"}},
	)
	cover, found := lib.read_cover(fmt.tprintf("%s/Music/1.mp3", folder), context.temp_allocator)
	testing.expect(t, found)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/cover.png", folder), cover.data) == nil)
	testing.expect(
		t,
		os.write_entire_file(
			fmt.tprintf("%s/notes.txt", folder),
			transmute([]u8)string("not an image"),
		) ==
		nil,
	)
	delete(s.app.home)
	s.app.home = strings.clone(folder)
	open_folder_of(t, s, fmt.tprintf("%s/Music", folder))
	wait_until_shown(t, s, "2 tracks")
	return
}

@(private = "file")
well_label :: proc(s: ^Screen) -> string {
	for w in s.h.ui.widgets do if w.id == ui.widget_id("Cover") do return w.label
	return ""
}

@(test)
a_track_shows_its_cover_and_several_tracks_say_they_differ :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "With a cover"))
	ui.run_frame(&s.h)
	testing.expect_value(t, well_label(&s), "Cover")
	shown, has := s.app.inspector.cover.?
	testing.expect(t, has && shown.texture != nil)
	ui.press_key(&s.h, .A, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect_value(t, well_label(&s), "Several covers")
	testing.expect_value(t, s.app.inspector.cover, nil)
	// A click on a selected track waits for a double click before the selection shrinks.
	testing.expect(t, ui.click(&s.h, "Paper Satellites"))
	ui.wait(&s.h, 0.6)
	testing.expect_value(t, well_label(&s), "No cover")
}

@(test)
replacing_the_cover_of_every_selected_track_waits_to_be_saved :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.answers.image = fmt.tprintf("%s/cover.png", folder)
	testing.expect(t, ui.click(&s.h, "With a cover"))
	ui.press_key(&s.h, .A, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Replace cover…"))
	ui.run_frame(&s.h)
	testing.expect_value(t, well_label(&s), "Cover")
	// Both tracks change: a cover set from a file is not known to be the one a track
	// already has, as the plan's decision says.
	testing.expect_value(t, len(s.app.engine.edits.pending), 2)
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	cover, found := lib.read_cover(fmt.tprintf("%s/Music/2.mp3", folder), context.temp_allocator)
	testing.expect(t, found && cover.mime == "image/png")
}

@(test)
a_cover_is_removed_from_the_wells_menu :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "With a cover"))
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Cover", .Right))
	testing.expect(t, ui.click(&s.h, "Remove Cover"))
	ui.run_frame(&s.h)
	testing.expect_value(t, well_label(&s), "No cover")
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
}

@(test)
an_image_that_cannot_be_read_is_told :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.answers.image = fmt.tprintf("%s/notes.txt", folder)
	testing.expect(t, ui.click(&s.h, "With a cover"))
	testing.expect(t, ui.click(&s.h, "Replace cover…"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "“notes.txt” is not a JPEG or PNG image"))
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
}

// The cover of a track in the well, in both themes.
@(test)
the_cover_well_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		folder := screen_with_covers(t, &s, kind)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		testing.expect(t, ui.click(&s.h, "With a cover"))
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "cover-dark.png" : "cover-light.png")
	}
}

// A cover whose bytes cannot be decoded is tried once: the well stays the cover's,
// empty, and no frame reads the file again.
@(test)
a_cover_that_cannot_be_decoded_is_tried_once :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Paper Satellites"))
	ui.wait(&s.h, 0.6)
	execute(&s.app, engine.Apply_Edit{{.Cover, lib.Cover{"image/png", {1, 2, 3}}}})
	ui.run_frame(&s.h)
	testing.expect_value(t, well_label(&s), "Cover")
	images := len(s.h.images)
	shown, has := s.app.inspector.cover.?
	testing.expect(t, has && shown.texture == nil)
	for _ in 0 ..< 3 do ui.run_frame(&s.h)
	testing.expect_value(t, len(s.h.images), images)
	// The modified border: the cover waits to be saved.
	summary, _ := s.app.inspector.inspection.(engine.Summary)
	testing.expect(t, .Cover in summary.modified)
}

@(test)
a_jpeg_is_told_by_its_first_bytes_and_the_texture_goes_with_the_selection :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	jpeg := fmt.tprintf("%s/photo.jpg", folder)
	testing.expect(t, os.write_entire_file(jpeg, []u8{0xFF, 0xD8, 0xFF, 0xE0, 0, 16}) == nil)
	s.answers.image = jpeg
	testing.expect(t, ui.click(&s.h, "With a cover"))
	ui.run_frame(&s.h)
	testing.expect(t, len(s.h.images) == 1 && s.h.images[0].rgba != nil)
	testing.expect(t, ui.click(&s.h, "Replace cover…"))
	ui.run_frame(&s.h)
	pending, found := s.app.engine.edits.pending[s.app.engine.listed[0]]
	cover, held := pending.cover.(lib.Cover)
	testing.expect(t, found && held && cover.mime == "image/jpeg")
	// Nothing selected: the texture goes.
	clear(&s.app.engine.selection.tracks)
	execute(&s.app, engine.Select_All{})
	execute(&s.app, engine.Revert{})
	clear(&s.app.engine.selection.tracks)
	ui.run_frame(&s.h)
	testing.expect_value(t, s.app.inspector.cover, nil)
	testing.expect(t, s.h.images[0].rgba == nil)
}

@(test)
a_cover_is_extracted_to_a_file :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.answers.saved = fmt.tprintf("%s/extracted.png", folder)
	testing.expect(t, ui.click(&s.h, "With a cover"))
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Cover", .Right))
	testing.expect(t, ui.click(&s.h, "Extract Cover…"))
	ui.run_frame(&s.h)
	extracted, read := os.read_entire_file(s.answers.saved, context.temp_allocator)
	original, _ := os.read_entire_file(fmt.tprintf("%s/cover.png", folder), context.temp_allocator)
	testing.expect(t, read == nil && len(extracted) > 0 && string(extracted) == string(original))
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	// The dialog suggested cover.png, by the format, beside the track's file.
	expected, _ := filepath.join({folder, "Music", "cover.png"}, context.temp_allocator)
	testing.expect_value(t, s.answers.suggested, expected)
	testing.expect(t, s.app.cover_to_write == nil)
	// A path that cannot be written is told.
	s.answers.saved = fmt.tprintf("%s/missing/x.png", folder)
	testing.expect(t, ui.click(&s.h, "Cover", .Right))
	testing.expect(t, ui.click(&s.h, "Extract Cover…"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Could not write the cover to “x.png”"))
}

@(test)
nothing_is_extracted_from_several_covers :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.answers.saved = fmt.tprintf("%s/never.png", folder)
	testing.expect(t, ui.click(&s.h, "With a cover"))
	ui.press_key(&s.h, .A, ui.COMMAND)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Several covers", .Right))
	testing.expect(t, ui.click(&s.h, "Extract Cover…"))
	ui.run_frame(&s.h)
	testing.expect_value(t, s.answers.suggested, "")
	testing.expect(t, !os.exists(s.answers.saved))
}

@(test)
an_image_dropped_becomes_the_cover_of_the_selection :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_covers(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Paper Satellites"))
	ui.run_frame(&s.h)
	drop_begin(&s.app)
	drop_file(&s.app, fmt.tprintf("%s/cover.png", folder))
	drop_end(&s.app, 0)
	ui.run_frame(&s.h)
	testing.expect_value(t, well_label(&s), "Cover")
	testing.expect_value(t, len(s.app.engine.edits.pending), 1)
	// Dropped with an audio file, the image is left alone: the file opens.
	execute(&s.app, engine.Revert{})
	drop_begin(&s.app)
	drop_file(&s.app, fmt.tprintf("%s/cover.png", folder))
	drop_file(&s.app, fmt.tprintf("%s/Music/2.mp3", folder))
	drop_end(&s.app, 0)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	// Without a selection, an image dropped is left alone.
	execute(&s.app, engine.Toggle_Selected{s.app.engine.listed[1]})
	testing.expect_value(t, len(s.app.engine.selection.tracks), 0)
	drop_begin(&s.app)
	drop_file(&s.app, fmt.tprintf("%s/cover.png", folder))
	drop_end(&s.app, 0)
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
}
