package library_tests

import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"

import lib ".."

@(private = "file")
frame_named :: proc(
	layout: lib.Tag_Layout,
	id: string,
) -> (
	found_frame: lib.Frame_Layout,
	found: bool,
) {
	for frame in layout.frames do if frame.id == id do return frame, true
	return
}

@(test)
the_layout_of_an_id3v2_3_tag_says_where_its_frames_are :: proc(t: ^testing.T) {
	layout, found := lib.read_layout(fixture("v23_full.mp3"))
	defer lib.destroy_layout(&layout)
	testing.expect(t, found && layout.has_id3v2)
	testing.expect_value(t, layout.version, lib.Id3v2_Version.V2_3)
	testing.expect_value(t, layout.size, 226)
	testing.expect_value(t, layout.padding, 10)
	testing.expect(t, layout.id3v1_offset == nil)
	frame, has := frame_named(layout, "TIT2")
	testing.expect(t, has)
	testing.expect_value(t, frame.offset, 10)
	testing.expect_value(t, frame.size, 18)
	testing.expect_value(t, frame.value, "Paper Satellites")
	testing.expect_value(t, frame.kind, lib.Frame_Kind.Text)
	encoding, has_encoding := frame.encoding.?
	testing.expect(t, has_encoding && lib.encoding_name(encoding) == "ISO-8859-1")
	// A user text frame shows its description before its value.
	comment, has_comment := frame_named(layout, "TXXX")
	testing.expect(t, has_comment)
	testing.expect_value(t, comment.value, "comment: Recorded in one take.")
}

@(test)
an_id3v2_2_tag_names_its_frames_with_three_letters :: proc(t: ^testing.T) {
	layout, found := lib.read_layout(fixture("v22.mp3"))
	defer lib.destroy_layout(&layout)
	testing.expect(t, found && layout.has_id3v2)
	testing.expect_value(t, layout.version, lib.Id3v2_Version.V2_2)
	track, has := frame_named(layout, "TRK")
	testing.expect(t, has)
	testing.expect_value(t, track.value, "3/12")
}

@(test)
text_in_utf8_is_told_with_its_encoding :: proc(t: ^testing.T) {
	layout, found := lib.read_layout(fixture("v24_unicode.mp3"))
	defer lib.destroy_layout(&layout)
	testing.expect(t, found)
	utf8_frames := 0
	for frame in layout.frames {
		if encoding, has := frame.encoding.?; has && encoding == .UTF8 {
			utf8_frames += 1
			if frame.id == "TPE1" do testing.expect_value(t, frame.value, "坂本龍一")
		}
	}
	testing.expect(t, utf8_frames > 0)
}

@(test)
a_picture_is_told_by_its_type_and_size :: proc(t: ^testing.T) {
	layout, found := lib.read_layout(fixture("v23_cover.mp3"))
	defer lib.destroy_layout(&layout)
	testing.expect(t, found)
	picture, has := frame_named(layout, "APIC")
	testing.expect(t, has)
	testing.expect_value(t, picture.kind, lib.Frame_Kind.Picture)
	testing.expect_value(t, picture.value, "image/png")
	testing.expect_value(t, picture.picture_size, 96)
}

@(test)
an_id3v1_tag_is_found_128_bytes_before_the_end :: proc(t: ^testing.T) {
	path := fixture("v1_1_ascii.mp3")
	layout, found := lib.read_layout(path)
	defer lib.destroy_layout(&layout)
	testing.expect(t, found && !layout.has_id3v2)
	info, err := os.stat(path, context.temp_allocator)
	testing.expect(t, err == nil)
	offset, has := layout.id3v1_offset.?
	testing.expect(t, has)
	testing.expect_value(t, offset, info.size - 128)
}

@(private = "file")
write_bytes :: proc(t: ^testing.T, folder, name: string, bytes: []u8) -> string {
	path := fmt.tprintf("%s/%s", folder, name)
	testing.expect(t, os.write_entire_file(path, bytes) == nil)
	return path
}

// A file of zeros, then an ID3v2.4 tag with one title frame and its footer.
@(private = "file")
appended_tag :: proc() -> []u8 {
	bytes := make([dynamic]u8, 300, context.temp_allocator)
	syncsafe_13 := [4]u8{0, 0, 0, 13}
	header := [?]u8 {
		'I',
		'D',
		'3',
		4,
		0,
		0x10,
		syncsafe_13[0],
		syncsafe_13[1],
		syncsafe_13[2],
		syncsafe_13[3],
	}
	append(&bytes, ..header[:])
	frame := [?]u8{'T', 'I', 'T', '2', 0, 0, 0, 3, 0, 0, 3, 'H', 'i'}
	append(&bytes, ..frame[:])
	footer := [?]u8{'3', 'D', 'I', 4, 0, 0x10, 0, 0, 0, 13}
	append(&bytes, ..footer[:])
	return bytes[:]
}

@(test)
a_tag_at_the_end_of_the_file_has_its_size :: proc(t: ^testing.T) {
	folder := folder_with(t, {})
	defer remove_folder(folder)
	path := write_bytes(t, folder, "appended.mp3", appended_tag())
	layout, found := lib.read_layout(path)
	defer lib.destroy_layout(&layout)
	testing.expect(t, found && layout.has_id3v2)
	testing.expect_value(t, layout.version, lib.Id3v2_Version.V2_4)
	testing.expect(t, layout.footer)
	testing.expect_value(t, layout.size, 33)
	title, has := frame_named(layout, "TIT2")
	testing.expect(t, has)
	testing.expect_value(t, title.offset, 310)
	testing.expect_value(t, title.value, "Hi")
}

@(test)
a_file_that_cannot_be_read_has_no_layout :: proc(t: ^testing.T) {
	_, found := lib.read_layout(fixture("does_not_exist.mp3"))
	testing.expect(t, !found)
	folder := folder_with(t, {})
	defer remove_folder(folder)
	_, directory := lib.read_layout(folder)
	testing.expect(t, !directory)
}

@(test)
a_file_without_tags_has_a_layout_without_them :: proc(t: ^testing.T) {
	folder := folder_with(t, {})
	defer remove_folder(folder)
	path := write_bytes(t, folder, "short.mp3", make([]u8, 100, context.temp_allocator))
	layout, found := lib.read_layout(path)
	defer lib.destroy_layout(&layout)
	testing.expect(t, found)
	testing.expect(t, !layout.has_id3v2)
	testing.expect(t, layout.id3v1_offset == nil)
	testing.expect_value(t, len(layout.frames), 0)
}

// A tag cut short, or whose frames say more than the file holds, is reported as far as
// it goes: nothing lies past the end of the file.
@(test)
a_truncated_tag_is_told_as_far_as_it_goes :: proc(t: ^testing.T) {
	folder := folder_with(t, {})
	defer remove_folder(folder)
	whole, read_err := os.read_entire_file(fixture("v23_full.mp3"), context.temp_allocator)
	testing.expect(t, read_err == nil)
	for length in ([?]int{9, 10, 11, 20, 60, 100, 200}) {
		path := write_bytes(t, folder, "cut.mp3", whole[:length])
		layout, found := lib.read_layout(path)
		testing.expect(t, found)
		testing.expectf(t, layout.size <= i64(length), "%d bytes: size %d", length, layout.size)
		for frame in layout.frames {
			testing.expectf(
				t,
				frame.offset >= 0 && frame.offset + 10 <= i64(length),
				"%d bytes: %s at %d",
				length,
				frame.id,
				frame.offset,
			)
		}
		lib.destroy_layout(&layout)
	}
}

// What the layout allocates beyond its result is freed with the allocator given: a
// worker thread has nobody to empty the temporary allocator.
@(test)
reading_a_layout_keeps_nothing_in_the_temporary_allocator :: proc(t: ^testing.T) {
	paths: [4]string
	for name, i in ([?]string{"v23_cover.mp3", "v23_full.mp3", "v24_unicode.mp3", "v22.mp3"}) {
		paths[i] = fixture(name)
	}
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.temp_allocator = mem.tracking_allocator(&track)
	for path in paths {
		layout, found := lib.read_layout(path)
		testing.expect(t, found)
		lib.destroy_layout(&layout)
	}
	testing.expect_value(t, len(track.allocation_map), 0)
}

// A frame of text far larger than a tag holds is not spread into thousands of values,
// and a long value is cut.
@(test)
a_huge_text_frame_is_not_opened :: proc(t: ^testing.T) {
	folder := folder_with(t, {})
	defer remove_folder(folder)
	count := 100_000
	bytes := make([dynamic]u8, context.temp_allocator)
	body_size := 10 + 1 + count
	header := [?]u8 {
		'I',
		'D',
		'3',
		4,
		0,
		0,
		u8(body_size >> 21 & 0x7f),
		u8(body_size >> 14 & 0x7f),
		u8(body_size >> 7 & 0x7f),
		u8(body_size & 0x7f),
	}
	append(&bytes, ..header[:])
	content := 1 + count
	frame := [?]u8 {
		'T',
		'I',
		'T',
		'2',
		u8(content >> 21 & 0x7f),
		u8(content >> 14 & 0x7f),
		u8(content >> 7 & 0x7f),
		u8(content & 0x7f),
		0,
		0,
		3,
	}
	append(&bytes, ..frame[:])
	for _ in 0 ..< count do append(&bytes, 0)
	path := write_bytes(t, folder, "huge.mp3", bytes[:])
	layout, found := lib.read_layout(path)
	defer lib.destroy_layout(&layout)
	testing.expect(t, found)
	title, has := frame_named(layout, "TIT2")
	testing.expect(t, has)
	testing.expect_value(t, title.kind, lib.Frame_Kind.Binary)
	testing.expect_value(t, title.value, "")
}
