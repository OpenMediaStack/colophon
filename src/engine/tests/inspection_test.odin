package engine_tests

import "core:fmt"
import "core:os"
import "core:testing"

import "../../engine"
import lib "../../library"

@(private = "file")
summary_of :: proc(t: ^testing.T, e: ^engine.Engine, loc := #caller_location) -> engine.Summary {
	summary, ok := engine.inspect(e).(engine.Summary)
	testing.expectf(t, ok, "not a summary: %v", engine.inspect(e), loc = loc)
	return summary
}

@(private = "file")
one_fixture :: proc(t: ^testing.T, e: ^engine.Engine, fixture, name: string) -> string {
	folder := folder_with_fixtures(t, {{fixture, name}})
	engine_reading(t, e, folder)
	return folder
}

@(test)
nothing_shows_until_a_track_is_selected :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := one_fixture(t, &e, "v23_full.mp3", "1.mp3")
	defer remove_folder(folder)
	defer engine.destroy(&e)
	testing.expect_value(t, engine.inspect(&e), nil)
}

@(test)
one_track_shows_its_tags_and_its_file :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := one_fixture(t, &e, "v23_full.mp3", "1.mp3")
	defer remove_folder(folder)
	defer engine.destroy(&e)
	info, err := os.stat(fmt.tprintf("%s/1.mp3", folder), context.temp_allocator)
	testing.expect(t, err == nil)

	engine.execute(&e, engine.Select{0})

	s := summary_of(t, &e)
	testing.expect_value(t, s.count, 1)
	testing.expect_value(t, s.heading, "Paper Satellites")
	testing.expect_value(t, s.title, engine.Shared(string)("Paper Satellites"))
	testing.expect_value(t, s.album_artist, engine.Shared(string)("Various Artists"))
	testing.expect_value(t, s.year, engine.Shared(int)(2019))
	testing.expect_value(t, s.track, engine.Shared(int)(3))
	testing.expect_value(t, s.track_total, engine.Shared(int)(12))
	testing.expect_value(t, s.disc, engine.Shared(int)(1))
	testing.expect_value(t, s.disc_total, engine.Shared(int)(2))
	testing.expect_value(t, s.comment, engine.Shared(string)("Recorded in one take."))
	testing.expect_value(
		t,
		s.audio,
		engine.Shared(engine.Audio_Line)(engine.Audio_Line{64, 44100, .Constant}),
	)
	testing.expect_value(
		t,
		s.formats,
		engine.Shared(lib.Tag_Formats)(lib.Tag_Formats{id3v2 = .V2_3}),
	)
	testing.expect_value(t, s.size, info.size)
}

@(test)
a_track_without_a_title_is_headed_by_its_file_name :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := one_fixture(t, &e, "no_tag.mp3", "07 Paper Satellites.mp3")
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Select{0})

	s := summary_of(t, &e)
	testing.expect_value(t, s.heading, "07 Paper Satellites")
	testing.expect_value(t, s.title, nil)
}

@(test)
several_tracks_share_what_they_have_in_common :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(
		t,
		{{"v23_full.mp3", "1.mp3"}, {"v24_full.mp3", "2.mp3"}, {"v24_unicode.mp3", "3.mp3"}},
	)
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Select{0})
	engine.execute(&e, engine.Select_Range{1})
	two := summary_of(t, &e)
	engine.execute(&e, engine.Select_All{})
	three := summary_of(t, &e)

	testing.expect_value(t, two.count, 2)
	testing.expect_value(t, two.heading, nil)
	testing.expect_value(t, two.title, engine.Shared(string)("Paper Satellites"))
	testing.expect_value(t, two.formats, engine.Shared(lib.Tag_Formats)(engine.Mixed{}))
	testing.expect_value(t, three.title, engine.Shared(string)(engine.Mixed{}))
	testing.expect_value(t, three.album_artist, engine.Shared(string)(engine.Mixed{}))
	testing.expect_value(t, three.genre, engine.Shared(string)(engine.Mixed{}))
}

@(test)
a_single_unreadable_track_shows_its_error :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := one_fixture(t, &e, "tiny_tag.mp3", "broken.mp3")
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Select{0})

	unreadable, ok := engine.inspect(&e).(engine.Unreadable_Track)
	testing.expect(t, ok)
	testing.expect_value(t, unreadable.error, lib.Read_Error.Damaged)
}

@(test)
unreadable_tracks_among_others_are_counted :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"tiny_tag.mp3", "2.mp3"}})
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Select_All{})

	s := summary_of(t, &e)
	testing.expect_value(t, s.count, 2)
	testing.expect_value(t, s.unreadable, 1)
	testing.expect_value(t, s.title, engine.Shared(string)("Paper Satellites"))
}

@(private = "file")
two_tracks :: proc(t: ^testing.T, e: ^engine.Engine) -> string {
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v24_unicode.mp3", "2.mp3"}})
	engine_reading(t, e, folder)
	return folder
}

@(test)
an_edit_shows_in_the_inspector :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})

	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})

	s := summary_of(t, &e)
	testing.expect_value(t, s.album, engine.Shared(string)("Analog Hearts"))
	testing.expect_value(t, s.modified, engine.Fields{.Album})
}

@(test)
a_single_edited_track_is_headed_by_its_new_title :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{0})

	engine.execute(&e, engine.Apply_Edit{{.Title, "New"}})

	testing.expect_value(t, summary_of(t, &e).heading, "New")
}

@(test)
the_inspection_says_what_saving_will_write :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := one_fixture(t, &e, "v23_v1_long_title.mp3", "1.mp3")
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{0})
	testing.expect_value(t, summary_of(t, &e).saved_as, nil)

	engine.execute(
		&e,
		engine.Apply_Edit{{.Title, "A brand new title, well over thirty characters"}},
	)

	s := summary_of(t, &e)
	want := lib.Tag_Formats {
		id3v2 = .V2_4,
		id3v1 = .V1_1,
	}
	testing.expect_value(t, s.saved_as, engine.Shared(lib.Tag_Formats)(want))
	testing.expect_value(t, s.id3v1_losses, lib.Id3v1_Losses{.Title})
}

@(test)
the_inspection_says_which_versions_saving_writes :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	versions, same := summary_of(t, &e).versions.(lib.Tag_Versions)
	testing.expect(t, same, "the tracks should share Colophon's versions")
	testing.expect_value(t, versions.id3v2, Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_4))

	engine.execute(&e, engine.Select{0})
	engine.execute(&e, engine.Choose_Version{engine.Id3v2_Choice{.V2_3}})
	engine.execute(&e, engine.Select_All{})

	testing.expect_value(
		t,
		summary_of(t, &e).versions,
		engine.Shared(lib.Tag_Versions)(engine.Mixed{}),
	)
}

@(test)
the_inspection_counts_the_files_saving_converts :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})

	engine.execute(&e, engine.Choose_Version{engine.Id3v2_Choice{.V2_3}})

	testing.expect_value(t, len(e.edits.pending), 1)
	testing.expect_value(t, summary_of(t, &e).converted, 1)
}

// 1.0.0's cover test of edits.rs. A cover set from a file counts as a change for the
// track that already has it, since the scan never reads picture bytes to compare.
@(test)
a_cover_is_an_edit_like_any_other :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(t, {{"v23_cover.mp3", "1.mp3"}, {"v23_full.mp3", "2.mp3"}})
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	_, mixed := summary_of(t, &e).cover.(engine.Mixed)
	testing.expect(t, mixed)
	cover, found := lib.read_cover(fmt.tprintf("%s/1.mp3", folder))
	defer lib.destroy_cover(&cover)
	testing.expect(t, found)

	engine.execute(&e, engine.Apply_Edit{{.Cover, cover}})

	s := summary_of(t, &e)
	key, shared := s.cover.(lib.Cover_Key)
	testing.expect(t, shared && key.size == len(cover.data))
	testing.expect_value(t, s.modified, engine.Fields{.Cover})
	testing.expect_value(t, len(e.edits.pending), 2)
	testing.expect(t, s.cover_track != nil)

	engine.execute(&e, engine.Apply_Edit{{.Cover, nil}})
	s = summary_of(t, &e)
	testing.expect_value(t, s.cover, nil)
	testing.expect_value(t, s.cover_track, nil)
	engine.execute(&e, engine.Undo{})
	engine.execute(&e, engine.Undo{})
	testing.expect_value(t, len(e.edits.pending), 0)
}
