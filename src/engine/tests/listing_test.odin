package engine_tests

import "core:fmt"
import "core:strings"
import "core:testing"

import "../../engine"

// A library of four tracks: two by Marlowe Kite and 坂本龍一 in a/, a plain ASCII one
// and a damaged one in b/.
library :: proc(t: ^testing.T, e: ^engine.Engine) -> (folder: string) {
	folder = folder_with_fixtures(
		t,
		{
			{"v23_full.mp3", "a/1.mp3"},
			{"v23_unicode.mp3", "a/2.mp3"},
			{"v1_1_ascii.mp3", "b/3.mp3"},
			{"tiny_tag.mp3", "b/4.mp3"},
		},
	)
	engine_reading(t, e, folder)
	return
}

@(test)
every_track_is_listed_in_library_order_at_first :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	expect_strings(t, listed_names(&e), {"1.mp3", "2.mp3", "3.mp3", "4.mp3"})
}

@(test)
the_filter_matches_titles_artists_albums_and_file_names :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Filter{"MARLOWE"})
	expect_strings(t, listed_names(&e), {"1.mp3"})
	engine.execute(&e, engine.Filter{"ελληνικά"})
	expect_strings(t, listed_names(&e), {"2.mp3"})
	engine.execute(&e, engine.Filter{"4.mp3"})
	expect_strings(t, listed_names(&e), {"4.mp3"})
	engine.execute(&e, engine.Filter{""})
	testing.expect_value(t, len(e.listed), 4)
}

@(test)
a_column_sorts_up_then_down :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Sort_By{.Title})
	expect_strings(t, listed_names(&e), {"4.mp3", "2.mp3", "1.mp3", "3.mp3"})
	engine.execute(&e, engine.Sort_By{.Title})
	expect_strings(t, listed_names(&e), {"3.mp3", "1.mp3", "2.mp3", "4.mp3"})
}

@(test)
a_missing_value_sorts_last :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Sort_By{.Album})
	names := listed_names(&e)
	testing.expect_value(t, names[len(names) - 1], "4.mp3")
}

@(test)
sources_list_a_folder_an_album_an_artist_or_the_unreadable_tracks :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Show_Source{engine.Folder{fmt.tprintf("%s/b", folder)}})
	expect_strings(t, listed_names(&e), {"3.mp3", "4.mp3"})
	engine.execute(&e, engine.Show_Source{engine.Album_Key{"Small Hours", "Various Artists"}})
	expect_strings(t, listed_names(&e), {"1.mp3"})
	engine.execute(&e, engine.Show_Source{engine.Artist{"坂本龍一"}})
	expect_strings(t, listed_names(&e), {"2.mp3"})
	engine.execute(&e, engine.Show_Source{engine.Unreadable{}})
	expect_strings(t, listed_names(&e), {"4.mp3"})
	engine.execute(&e, engine.Show_Source{engine.All_Tracks{}})
	testing.expect_value(t, len(e.listed), 4)
}

@(test)
a_folder_source_is_a_whole_path_component :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Show_Source{engine.Folder{fmt.tprintf("%s/", folder)[:len(folder)]}})
	testing.expect_value(t, len(e.listed), 4)
	engine.execute(&e, engine.Show_Source{engine.Folder{fmt.tprintf("%s/a/1", folder)}})
	testing.expect_value(t, len(e.listed), 0)
}

@(test)
the_library_groups_its_tracks_by_album_and_artist :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	groups := engine.groups(&e)
	defer engine.destroy_groups(&groups)
	found_album := false
	for album in groups.albums {
		if album.key.title == "Small Hours" do found_album = true
		testing.expect_value(t, album.cover_track, nil)
	}
	testing.expect(t, found_album)
	found_artist := false
	for artist in groups.artists {
		if artist.name == "Marlowe Kite" && artist.tracks == 1 do found_artist = true
	}
	testing.expect(t, found_artist)
}

@(test)
groups_are_in_alphabetical_order_ignoring_case :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	groups := engine.groups(&e)
	defer engine.destroy_groups(&groups)
	for i in 1 ..< len(groups.artists) {
		a := strings.to_lower(groups.artists[i - 1].name, context.temp_allocator)
		b := strings.to_lower(groups.artists[i].name, context.temp_allocator)
		testing.expectf(t, a <= b, "%s before %s", a, b)
	}
}

@(test)
the_listing_follows_the_library_as_scans_report :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Filter{"marlowe"})
	more := folder_with_fixtures(t, {{"v23_full.mp3", "5.mp3"}})
	defer remove_folder(more)
	engine.execute(&e, engine.Open_Folder{more})
	poll_until_done(t, &e)
	expect_strings(t, listed_names(&e), {"1.mp3", "5.mp3"})
}

@(test)
listing_commands_keep_the_ids_of_1_0 :: proc(t: ^testing.T) {
	testing.expect_value(t, engine.command_id(engine.Show_Source{}), "view.show_source")
	testing.expect_value(t, engine.command_id(engine.Filter{}), "view.filter")
	testing.expect_value(t, engine.command_id(engine.Sort_By{}), "view.sort_by")
}
