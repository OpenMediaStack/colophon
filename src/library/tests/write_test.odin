package library_tests

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import lib ".."
import id3 "../../../libs/odid3"

// A copy of a fixture in a folder of its own. Remove the folder with remove_folder.
@(private = "file")
copy_of :: proc(t: ^testing.T, name: string) -> (folder, path: string) {
	folder = folder_with(t, {})
	path = fmt.tprintf("%s/%s", folder, name)
	testing.expect(t, os.copy_file(path, fixture(name)) == nil)
	return
}

@(private = "file")
new_tags :: proc() -> lib.Tags {
	return {
		title = "Neon Overpass",
		artist = "坂本龍一",
		album_artist = "Cassette Bloom",
		album = "Analog Hearts",
		year = 2024,
		track = 4,
		track_total = 9,
		disc = 2,
		disc_total = 3,
		genre = "Synthwave",
		comment = "Remastered from the original tapes.",
	}
}

// The audio of an MP3 found without odid3, as 1.0.0's tests found it: from its first
// frame sync after the ID3v2 tag to its ID3v1 or APE tag.
@(private = "file")
audio :: proc(bytes: []u8) -> []u8 {
	tag_end := 0
	if len(bytes) >= 10 && string(bytes[:3]) == "ID3" {
		size := 0
		for b in bytes[6:10] do size = size << 7 | int(b)
		tag_end = 10 + size
	}
	start := tag_end
	for at in tag_end ..< len(bytes) - 1 {
		if bytes[at] == 0xff && bytes[at + 1] & 0xe0 == 0xe0 {
			start = at
			break
		}
	}
	end := len(bytes)
	if end >= start + 128 && string(bytes[end - 128:][:3]) == "TAG" do end -= 128
	if ape := strings.index(string(bytes[start:end]), "APETAGEX"); ape >= 0 do end = start + ape
	return bytes[start:end]
}

@(private = "file")
read_bytes :: proc(path: string) -> []u8 {
	data, _ := os.read_entire_file_from_path(path, context.temp_allocator)
	return data
}

@(private = "file")
files_in :: proc(folder: string) -> []string {
	entries, _ := os.read_all_directory_by_path(folder, context.temp_allocator)
	names := make([]string, len(entries), context.temp_allocator)
	for e, i in entries do names[i] = e.name
	slice.sort(names)
	return names
}

@(test)
every_fixture_reads_back_what_was_written_with_its_audio_untouched :: proc(t: ^testing.T) {
	entries, err := os.read_all_directory_by_path(TESTDATA, context.allocator)
	if !testing.expect(t, err == nil) do return
	defer os.file_info_slice_delete(entries, context.allocator)
	all_versions := [?]lib.Tag_Versions {
		{.V2_4, nil},
		{.V2_4, .V1_1},
		{.V2_3, .V1_0},
		{.V2_2, nil},
		{nil, .V1_1},
	}
	checked := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".mp3") do continue
		original := lib.read_track(fixture(entry.name))
		defer lib.destroy_track(&original)
		if original.error != .None do continue
		checked += 1
		for versions in all_versions {
			folder, path := copy_of(t, entry.name)
			defer remove_folder(folder)
			before := slice.clone(audio(read_bytes(path)))
			defer delete(before)
			tags := new_tags()
			tags.cover = original.metadata.tags.cover

			written, write_err := lib.write_track(path, tags, versions)
			defer lib.destroy_track(&written)

			what := fmt.tprintf("%s in %v", entry.name, versions)
			if !testing.expectf(t, write_err == .None, "%s: %v", what, write_err) do continue
			want := lib.formats_after_write(original.metadata.formats, &tags, versions)
			testing.expectf(
				t,
				written.metadata.formats == want,
				"%s: %v",
				what,
				written.metadata.formats,
			)
			if versions.id3v2 != nil {
				testing.expectf(
					t,
					lib.same_tags(written.metadata.tags, tags),
					"%s: %v",
					what,
					written.metadata.tags,
				)
			}
			testing.expectf(
				t,
				slice.equal(audio(read_bytes(path)), before),
				"%s: the audio changed",
				what,
			)
			testing.expectf(
				t,
				slice.equal(files_in(folder), []string{entry.name}),
				"%s: a copy is left",
				what,
			)
		}
	}
	testing.expectf(t, checked > 10, "only %d fixtures", checked)
}

@(test)
removed_fields_are_gone :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	tags := lib.Tags {
		title = "Only a title",
	}

	written, err := lib.write_track(path, tags, {.V2_4, nil})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expectf(t, lib.same_tags(written.metadata.tags, tags), "%v", written.metadata.tags)
}

@(test)
ffmpegs_comment_goes_with_the_comment :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	before := lib.read_track(path)
	defer lib.destroy_track(&before)
	testing.expect(t, before.metadata.tags.comment != nil)
	tags := before.metadata.tags
	tags.comment = nil

	written, _ := lib.write_track(path, tags, {.V2_4, nil})
	defer lib.destroy_track(&written)

	testing.expect_value(t, written.metadata.tags.comment, nil)
}

@(test)
id3v2_2_keeps_the_frames_colophon_does_not_edit :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_cover.mp3")
	defer remove_folder(folder)
	tags := new_tags()
	tags.cover = lib.Own_Cover{}

	written, err := lib.write_track(path, tags, {.V2_2, nil})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expect_value(t, written.metadata.formats, lib.Tag_Formats{id3v2 = .V2_2})
	testing.expectf(t, lib.same_tags(written.metadata.tags, tags), "%v", written.metadata.tags)
	file, _ := id3.read_file(path)
	defer id3.destroy(&file)
	pictures, publishers := 0, 0
	for f in file.v2.frames {
		kind, _ := id3.frame_kind(f.id, file.v2.version)
		if kind == .APIC do pictures += 1
		if kind == .TPUB do publishers += 1
	}
	testing.expect_value(t, pictures, 1)
	testing.expect_value(t, publishers, 1)
}

@(test)
an_id3v1_tag_is_rewritten_from_the_new_values :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	tags := new_tags()
	tags.title = "A brand new title, well over thirty characters"
	tags.artist = "Marlowe Kite"

	written, err := lib.write_track(path, tags, {.V2_4, .V1_1})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expect_value(
		t,
		written.metadata.formats,
		lib.Tag_Formats{id3v2 = .V2_4, id3v1 = .V1_1},
	)
	file, _ := id3.read_file(path)
	defer id3.destroy(&file)
	testing.expect_value(t, file.v1.title, "A brand new title, well over t")
	testing.expect_value(t, file.v1.track, 4)
	testing.expect(t, lib.id3v1_losses(&tags, .V1_1) != {})
}

@(test)
a_file_with_only_id3v1_gains_id3v2 :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v1_1_ascii.mp3")
	defer remove_folder(folder)

	written, err := lib.write_track(path, new_tags(), {.V2_4, .V1_1})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expect_value(
		t,
		written.metadata.formats,
		lib.Tag_Formats{id3v2 = .V2_4, id3v1 = .V1_1},
	)
}

@(test)
a_missing_file_cannot_be_written :: proc(t: ^testing.T) {
	_, err := lib.write_track("/there/is/no/such/file.mp3", new_tags(), {.V2_4, nil})
	testing.expect_value(t, err, lib.Write_Error.Cannot_Write)
}

@(test)
a_damaged_file_is_left_alone_and_cleaned_up_after :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "tiny_tag.mp3")
	defer remove_folder(folder)

	_, err := lib.write_track(path, new_tags(), {.V2_4, nil})

	testing.expect_value(t, err, lib.Write_Error.Damaged)
	testing.expect_value(t, string(read_bytes(path)), "TAG")
	testing.expect(t, slice.equal(files_in(folder), []string{"tiny_tag.mp3"}))
}

@(test)
a_read_only_file_is_left_alone :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	before := slice.clone(read_bytes(path))
	defer delete(before)
	testing.expect(t, os.change_mode(path, {.Read_User, .Read_Group, .Read_Other}) == nil)

	_, err := lib.write_track(path, new_tags(), {.V2_4, nil})

	testing.expect_value(t, err, lib.Write_Error.Read_Only)
	testing.expect(t, slice.equal(read_bytes(path), before))
	_ = os.change_mode(path, os.Permissions_Default)
}

@(test)
a_total_without_its_number_reads_back_the_same :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	file, _ := id3.read_file(path)
	testing.expect(t, id3.set_track(&file.v2, 0, 12) == nil)
	testing.expect(t, id3.write_file(path, &file) == nil)
	id3.destroy(&file)
	before := lib.read_track(path)
	defer lib.destroy_track(&before)
	testing.expect(t, before.metadata.tags.track == nil && before.metadata.tags.track_total == 12)

	written, err := lib.write_track(path, before.metadata.tags, {.V2_4, nil})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expectf(
		t,
		lib.same_tags(written.metadata.tags, before.metadata.tags),
		"%v",
		written.metadata.tags,
	)
}

@(test)
the_enhanced_tag_keeps_its_speed_and_times :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v1_1_ascii.mp3")
	defer remove_folder(folder)
	file, _ := id3.read_file(path)
	file.v1.enhanced = id3.V1_Enhanced {
		speed      = 2,
		start_time = strings.clone("001:00", file.v1.allocator),
		end_time   = strings.clone("002:30", file.v1.allocator),
	}
	testing.expect(t, id3.write_file(path, &file) == nil)
	id3.destroy(&file)
	before := lib.read_track(path)
	defer lib.destroy_track(&before)
	tags := before.metadata.tags
	tags.title = "Another title"

	for versions in ([]lib.Tag_Versions{{.V2_4, .V1_1}, {nil, .V1_1}}) {
		written, err := lib.write_track(path, tags, versions)
		lib.destroy_track(&written)
		testing.expect_value(t, err, lib.Write_Error.None)
		after, _ := id3.read_file(path)
		defer id3.destroy(&after)
		enhanced, kept := after.v1.enhanced.?
		testing.expectf(t, kept, "%v: no Enhanced TAG", versions)
		if kept {
			testing.expect_value(t, enhanced.speed, 2)
			testing.expect_value(t, enhanced.start_time, "001:00")
			testing.expect_value(t, enhanced.end_time, "002:30")
		}
	}
}

@(test)
a_cover_is_replaced_and_removed :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	cover, found := lib.read_cover(fixture("v23_cover.mp3"))
	defer lib.destroy_cover(&cover)
	testing.expect(t, found)
	tags := new_tags()
	tags.cover = cover

	written, err := lib.write_track(path, tags, {.V2_3, nil})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	_, own := written.metadata.tags.cover.(lib.Own_Cover)
	testing.expect(t, own)
	back, has := lib.read_cover(path)
	defer lib.destroy_cover(&back)
	testing.expect(t, has && back.mime == cover.mime && slice.equal(back.data, cover.data))

	// None removes it.
	tags.cover = nil
	again, err_again := lib.write_track(path, tags, {.V2_3, nil})
	defer lib.destroy_track(&again)
	testing.expect_value(t, err_again, lib.Write_Error.None)
	testing.expect(t, again.metadata.tags.cover == nil)
}

// A file with a front cover and a back cover: removing the cover removes the front one
// alone, and the back cover is the file's cover from then on, as 1.0.0 did.
@(test)
removing_the_cover_keeps_the_other_pictures :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_cover.mp3")
	defer remove_folder(folder)
	file, read_err := id3.read_file(path)
	testing.expect(t, read_err == nil)
	back := []u8{66, 65, 67, 75}
	testing.expect(
		t,
		id3.set_picture(&file.v2, {mime = "image/png", type = .Back_Cover, data = back}) == nil,
	)
	testing.expect(t, id3.write_file(path, &file) == nil)
	id3.destroy(&file)
	tags := new_tags()
	tags.cover = nil

	written, err := lib.write_track(path, tags, {.V2_3, nil})
	defer lib.destroy_track(&written)

	testing.expect_value(t, err, lib.Write_Error.None)
	_, own := written.metadata.tags.cover.(lib.Own_Cover)
	testing.expect(t, own)
	cover, found := lib.read_cover(path)
	defer lib.destroy_cover(&cover)
	testing.expect(t, found && slice.equal(cover.data, back))
}

// A cover written as ID3v2.2 names its format in three letters and reads back as its
// MIME type; a format ID3v2.2 cannot name fails the file, left untouched.
@(test)
a_cover_written_as_id3v2_2_keeps_its_format :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	before := slice.clone(read_bytes(path))
	defer delete(before)
	tags := new_tags()
	tags.cover = lib.Cover{"image/jpeg", []u8{0xFF, 0xD8, 0xFF, 0xE0}}

	written, err := lib.write_track(path, tags, {.V2_2, nil})
	defer lib.destroy_track(&written)
	testing.expect_value(t, err, lib.Write_Error.None)
	cover, found := lib.read_cover(path)
	defer lib.destroy_cover(&cover)
	testing.expect(t, found && cover.mime == "image/jpeg")

	tags.cover = lib.Cover{"image/webp", []u8{1, 2, 3}}
	again_before := slice.clone(read_bytes(path))
	defer delete(again_before)
	again, err_again := lib.write_track(path, tags, {.V2_2, nil})
	defer lib.destroy_track(&again)
	testing.expect(t, err_again != .None)
	testing.expect(t, slice.equal(read_bytes(path), again_before))
}

@(private = "file")
title_encoding :: proc(t: ^testing.T, path: string) -> lib.Text_Encoding {
	layout, found := lib.read_layout(path)
	defer lib.destroy_layout(&layout)
	testing.expect(t, found)
	for frame in layout.frames do if frame.id == "TIT2" || frame.id == "TT2" do return frame.encoding.? or_else .Latin1
	testing.expect(t, false, "no title frame")
	return .Latin1
}

@(test)
details_set_the_padding_and_the_unsynchronisation :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	written, err := lib.write_track_with(
		path,
		new_tags(),
		{.V2_4, nil},
		{padding = 1024, unsynchronisation = true},
	)
	defer lib.destroy_track(&written)
	testing.expect_value(t, err, lib.Write_Error.None)
	layout, found := lib.read_layout(path)
	defer lib.destroy_layout(&layout)
	testing.expect(t, found)
	testing.expect_value(t, layout.padding, 1024)
	testing.expect(t, layout.unsynchronisation)

	none, err_none := lib.write_track_with(path, new_tags(), {.V2_4, nil}, {padding = 0})
	defer lib.destroy_track(&none)
	testing.expect_value(t, err_none, lib.Write_Error.None)
	plain, plain_found := lib.read_layout(path)
	defer lib.destroy_layout(&plain)
	testing.expect(t, plain_found)
	testing.expect_value(t, plain.padding, 0)
}

@(test)
an_encoding_the_version_lacks_becomes_utf16 :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	for encoding in ([?]struct {
			encoding: lib.Text_Encoding,
			version:  lib.Id3v2_Version,
			expected: lib.Text_Encoding,
		}{{.UTF16BE, .V2_4, .UTF16BE}, {.UTF8, .V2_4, .UTF8}, {.UTF16BE, .V2_3, .UTF16}, {.UTF8, .V2_2, .UTF16}, {.Latin1, .V2_3, .Latin1}, {.UTF16, .V2_3, .UTF16}}) {
		written, err := lib.write_track_with(
			path,
			{title = "Neon Overpass"},
			{encoding.version, nil},
			{encoding = encoding.encoding},
		)
		lib.destroy_track(&written)
		testing.expectf(t, err == .None, "%v in %v: %v", encoding.encoding, encoding.version, err)
		testing.expectf(
			t,
			title_encoding(t, path) == encoding.expected,
			"%v in %v: %v",
			encoding.encoding,
			encoding.version,
			title_encoding(t, path),
		)
	}
}

// Every text frame takes the encoding asked for, as 1.0.0's test of it checked, and the
// tags read back the same.
@(test)
every_frame_takes_the_encoding_asked_for :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	for version in lib.Id3v2_Version {
		for encoding in lib.Text_Encoding {
			written, err := lib.write_track_with(
				path,
				new_tags_ascii(),
				{version, nil},
				{encoding = encoding},
			)
			testing.expectf(t, err == .None, "%v in %v: %v", encoding, version, err)
			expected := encoding
			if version != .V2_4 && (encoding == .UTF16BE || encoding == .UTF8) do expected = .UTF16
			layout, found := lib.read_layout(path)
			testing.expect(t, found)
			for frame in layout.frames {
				if has, ok := frame.encoding.?; ok && frame.kind == .Text {
					testing.expectf(
						t,
						has == expected,
						"%s in %v with %v: %v",
						frame.id,
						version,
						encoding,
						has,
					)
				}
			}
			testing.expectf(
				t,
				written.metadata.tags.title == "Neon Overpass",
				"%v in %v read back %v",
				encoding,
				version,
				written.metadata.tags.title,
			)
			lib.destroy_layout(&layout)
			lib.destroy_track(&written)
		}
	}
}

@(private = "file")
new_tags_ascii :: proc() -> lib.Tags {
	return {
		title = "Neon Overpass",
		artist = "Cassette Bloom",
		album = "Analog Hearts",
		year = 2024,
		track = 4,
	}
}

// Text that Latin-1 cannot hold is not written, and the file stays as it was.
@(test)
text_an_encoding_cannot_hold_leaves_the_file_untouched :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_full.mp3")
	defer remove_folder(folder)
	before, read_before := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_before == nil)
	defer delete(before)
	_, err := lib.write_track_with(path, new_tags(), {.V2_4, nil}, {encoding = .Latin1})
	testing.expect_value(t, err, lib.Write_Error.Cannot_Encode)
	after, read_after := os.read_entire_file(path, context.allocator)
	testing.expect(t, read_after == nil)
	defer delete(after)
	testing.expect(t, slice.equal(before, after))
}
