package library_tests

import "core:fmt"
import "core:os"
import "core:testing"

import lib ".."

@(test)
a_cover_is_found_without_reading_it :: proc(t: ^testing.T) {
	track := lib.read_track(fixture("v23_cover.mp3"))
	defer lib.destroy_track(&track)
	testing.expect(t, track.metadata.tags.has_cover)
}

@(test)
id3v1_alone_gives_the_fields :: proc(t: ^testing.T) {
	track := lib.read_track(fixture("v1_1_ascii.mp3"))
	defer lib.destroy_track(&track)
	tags := track.metadata.tags
	testing.expect_value(t, tags.title, "Track seven")
	testing.expect_value(t, tags.year, 2004)
	testing.expect_value(t, tags.track, 7)
	testing.expect_value(t, tags.genre, "Folk-Rock")
	testing.expect_value(t, track.metadata.formats.id3v2, nil)
	testing.expect_value(
		t,
		track.metadata.formats.id3v1,
		Maybe(lib.Id3v1_Version)(lib.Id3v1_Version.V1_1),
	)
}

@(test)
an_ape_tag_gives_the_fields :: proc(t: ^testing.T) {
	track := lib.read_track(fixture("ape.mp3"))
	defer lib.destroy_track(&track)
	tags := track.metadata.tags
	testing.expect_value(t, tags.title, "Paper Satellites")
	testing.expect_value(t, tags.artist, "Marlowe Kite")
	testing.expect_value(t, tags.album_artist, "Various Artists")
	testing.expect_value(t, tags.album, "Small Hours")
	testing.expect_value(t, tags.year, 2019)
	testing.expect(t, tags.track == 3 && tags.track_total == 12)
	testing.expect(t, tags.disc == 1 && tags.disc_total == 2)
	testing.expect_value(t, tags.genre, "Folk")
	testing.expect_value(t, tags.comment, "Recorded in one take.")
	testing.expect(t, track.metadata.formats.ape)
}

@(test)
id3v1_comes_before_ape :: proc(t: ^testing.T) {
	track := lib.read_track(fixture("ape_v1.mp3"))
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.metadata.tags.title, "Plain ASCII title")
	testing.expect(t, track.metadata.formats.ape)
}

@(test)
id3v2_and_id3v1_are_never_mixed :: proc(t: ^testing.T) {
	// An ID3v2.3 tag holding only a title, before a file with a full ID3v1 tag.
	TITLE :: "Only a title"
	header := [?]u8{'I', 'D', '3', 3, 0, 0, 0, 0, 0, 10 + 1 + len(TITLE)}
	frame := [?]u8{'T', 'I', 'T', '2', 0, 0, 0, 1 + len(TITLE), 0, 0, 0}
	audio, read_err := os.read_entire_file_from_path(fixture("v1_1_ascii.mp3"), context.allocator)
	if !testing.expect(t, read_err == nil) do return
	defer delete(audio)
	folder := folder_with(t, {})
	defer remove_folder(folder)
	path := fmt.tprintf("%s/mixed.mp3", folder)
	data := make([dynamic]u8, context.temp_allocator)
	append(&data, ..header[:])
	append(&data, ..frame[:])
	append(&data, TITLE)
	append(&data, ..audio)
	testing.expect(t, os.write_entire_file(path, data[:]) == nil)

	track := lib.read_track(path)
	defer lib.destroy_track(&track)
	tags := track.metadata.tags
	testing.expect_value(t, tags.title, TITLE)
	testing.expect_value(t, tags.artist, nil)
	testing.expect_value(t, tags.year, nil)
	testing.expect_value(t, tags.track, nil)
}

@(test)
the_tags_column_names_the_formats_in_file_order :: proc(t: ^testing.T) {
	all := lib.tag_formats_string(
		{id3v2 = .V2_3, id3v1 = .V1_1, ape = true},
		context.temp_allocator,
	)
	testing.expect_value(t, all, "ID3v2.3, ID3v1.1, APE")
	testing.expect_value(t, lib.tag_formats_string({}, context.temp_allocator), "")
	free_all(context.temp_allocator)
}
