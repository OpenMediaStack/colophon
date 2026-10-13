package engine_tests

import "core:path/filepath"
import "core:testing"

import "../../engine"
import lib "../../library"

@(private = "file")
title_of :: proc(e: ^engine.Engine, track: engine.Track_Id) -> string {
	tags, ok := engine.shown_tags(e, track)
	if !ok do return "?"
	return tags.title.? or_else ""
}

// The track of this file name.
@(private = "file")
track_named :: proc(e: ^engine.Engine, name: string) -> engine.Track_Id {
	for track, i in e.library.tracks {
		if filepath.base(track.path) == name do return engine.Track_Id(i)
	}
	return -1
}

@(private = "file")
number_of :: proc(e: ^engine.Engine, name: string) -> (track, total: Maybe(int)) {
	tags, ok := engine.shown_tags(e, track_named(e, name))
	if !ok do return
	return tags.track, tags.track_total
}

@(private = "file")
two_tracks :: proc(t: ^testing.T, e: ^engine.Engine) -> string {
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v24_unicode.mp3", "2.mp3"}})
	engine_reading(t, e, folder)
	return folder
}

@(test)
an_edit_changes_every_selected_track :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})

	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})

	testing.expect_value(t, len(e.edits.pending), 2)
	all := []engine.Track_Id{0, 1}
	testing.expect_value(t, engine.modified_fields(&e, all), engine.Fields{.Album})
	testing.expect_value(t, title_of(&e, track_named(&e, "2.mp3")), "Café")
}

@(test)
undo_redo_and_revert_go_through_the_engine :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	one := track_named(&e, "1.mp3")
	engine.execute(&e, engine.Select{one})
	engine.execute(&e, engine.Apply_Edit{{.Title, "New"}})

	engine.execute(&e, engine.Undo{})
	testing.expect_value(t, title_of(&e, one), "Paper Satellites")
	engine.execute(&e, engine.Redo{})
	testing.expect_value(t, title_of(&e, one), "New")
	engine.execute(&e, engine.Revert{})
	testing.expect_value(t, title_of(&e, one), "Paper Satellites")
	testing.expect_value(t, len(e.edits.pending), 0)
}

@(test)
opening_another_folder_keeps_the_edits :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Apply_Edit{{.Genre, "Synthwave"}})
	other := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(other)

	engine.execute(&e, engine.Open_Folder{other})
	poll_until_done(t, &e)

	testing.expect_value(t, len(e.library.tracks), 3)
	testing.expect_value(t, len(e.edits.pending), 2)
	testing.expect(t, engine.can_undo(&e))
}

@(test)
choosing_a_version_changes_only_the_files_in_another :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})

	engine.execute(&e, engine.Choose_Version{engine.Id3v2_Choice{.V2_3}})

	testing.expect_value(t, len(e.edits.pending), 1)
	_, pending := engine.pending_tags(&e, track_named(&e, "2.mp3"))
	testing.expect(t, pending)
	versions, _ := engine.versions_of(&e, track_named(&e, "1.mp3"))
	testing.expect_value(t, versions.id3v2, Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_3))
}

@(test)
tracks_are_numbered_in_the_table_order_disc_by_disc :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(
		t,
		{{"v23_full.mp3", "1.mp3"}, {"v24_full.mp3", "2.mp3"}, {"v24_unicode.mp3", "3.mp3"}},
	)
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Apply_Edit{{.Disc, 1}})
	engine.execute(&e, engine.Select{track_named(&e, "3.mp3")})
	engine.execute(&e, engine.Apply_Edit{{.Disc, 2}})
	engine.execute(&e, engine.Sort_By{.File})
	engine.execute(&e, engine.Sort_By{.File})
	engine.execute(&e, engine.Select_All{})

	engine.execute(&e, engine.Number_Tracks{})

	track, total := number_of(&e, "2.mp3")
	testing.expect(t, track == 1 && total == 2)
	track, total = number_of(&e, "1.mp3")
	testing.expect(t, track == 2 && total == 2)
	track, total = number_of(&e, "3.mp3")
	testing.expect(t, track == 1 && total == 1)
	engine.execute(&e, engine.Undo{})
	track, total = number_of(&e, "1.mp3")
	testing.expect(t, track == 3 && total == 12)
}

@(test)
selecting_the_album_selects_every_listed_track_of_it :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(
		t,
		{{"v23_full.mp3", "1.mp3"}, {"v24_full.mp3", "2.mp3"}, {"v24_unicode.mp3", "3.mp3"}},
	)
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)
	one, two := track_named(&e, "1.mp3"), track_named(&e, "2.mp3")
	engine.execute(&e, engine.Select{one})
	engine.execute(&e, engine.Toggle_Selected{two})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})
	engine.execute(&e, engine.Apply_Edit{{.Album_Artist, "Cassette Bloom"}})
	engine.execute(&e, engine.Select{two})

	engine.execute(&e, engine.Select_Album{})

	selected := e.selection.tracks[:]
	testing.expect_value(t, len(selected), 2)
	testing.expect(t, engine.is_selected(&e.selection, one))
	testing.expect(t, engine.is_selected(&e.selection, two))
}
