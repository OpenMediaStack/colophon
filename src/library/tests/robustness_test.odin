package library_tests

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import lib ".."
import id3 "../../../libs/odid3"

// Every fixture, cut short at many lengths, with random bytes changed in its tags and
// with extreme values in the fields that give sizes and counts, scans without a panic,
// and each file is a track, read or not. One track in five that reads is saved again,
// which either fails or reads back what was written with its audio untouched. The
// fixtures go in name order, so the same seed makes the same files everywhere.
@(test)
damaged_files_scan_and_save_without_a_panic :: proc(t: ^testing.T) {
	state := rand.create(20261014)
	context.random_generator = rand.default_random_generator(&state)
	folder := folder_with(t, {})
	defer remove_folder(folder)
	entries, err := os.read_all_directory_by_path(TESTDATA, context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	written := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".mp3") do continue
		data, read_err := os.read_entire_file_from_path(fixture(entry.name), context.allocator)
		if !testing.expect(t, read_err == nil) || len(data) == 0 do continue
		defer delete(data)
		cuts := [?]int{0, 1, 3, 10, 64, 128, 1000, len(data) / 2, len(data) - 129, len(data) - 1}
		for cut, i in cuts {
			if cut < 0 || cut > len(data) do continue
			name := fmt.tprintf("%s/cut-%d-%s", folder, i, entry.name)
			testing.expect(t, os.write_entire_file(name, data[:cut]) == nil)
			written += 1
		}
		mutated := make([]u8, len(data))
		defer delete(mutated)
		for round in 0 ..< 30 {
			copy(mutated, data)
			for _ in 0 ..< 1 + round % 8 {
				// The tags are at the start and the end of the file.
				at := rand.int_max(min(len(mutated), 4096))
				if rand.int_max(2) == 0 do at = len(mutated) - 1 - rand.int_max(min(len(mutated), 256))
				mutated[at] = u8(rand.int_max(256))
			}
			name := fmt.tprintf("%s/mutated-%d-%s", folder, round, entry.name)
			testing.expect(t, os.write_entire_file(name, mutated) == nil)
			written += 1
		}
		for field, i in size_fields(data) {
			for extreme, k in ([?]u32{0, 0x7F7F7F7F, 0xFFFFFFFF}) {
				copy(mutated, data)
				for b in 0 ..< field.length do mutated[field.at + b] = u8(extreme >> u32(8 * (field.length - 1 - b)))
				name := fmt.tprintf("%s/sized-%d-%d-%s", folder, i, k, entry.name)
				testing.expect(t, os.write_entire_file(name, mutated) == nil)
				written += 1
			}
		}
	}

	events := scan_all(folder)
	defer destroy_events(&events)

	tracks := 0
	saved := 0
	for event in events {
		track := event.(lib.Track) or_continue
		tracks += 1
		if track.error != .None || tracks % 5 != 0 do continue
		tags := track.metadata.tags
		tags.title = "Saved again"
		before := slice.clone(audio(track.path))
		defer delete(before)
		again, write_err := lib.write_track(track.path, tags, {.V2_4, .V1_1})
		defer lib.destroy_track(&again)
		if write_err == .None {
			saved += 1
			testing.expectf(t, again.metadata.tags.title == "Saved again", "%s", track.path)
			testing.expectf(
				t,
				slice.equal(audio(track.path), before),
				"%s: the audio changed",
				track.path,
			)
		}
	}
	testing.expect_value(t, tracks, written)
	testing.expectf(t, saved > 0, "no damaged file could be saved again")
}

// Where a fixture keeps a size or a count, big endian: the ID3v2 header's flags and size,
// its first frame's size, and an APE footer's size and item count (little endian, so
// written backwards here, which only changes which extreme lands where).
@(private = "file")
Size_Field :: struct {
	at, length: int,
}

@(private = "file")
size_fields :: proc(data: []u8) -> []Size_Field {
	fields := make([dynamic]Size_Field, context.temp_allocator)
	if len(data) >= 22 && string(data[:3]) == "ID3" {
		append(&fields, Size_Field{5, 1}, Size_Field{6, 4})
		append(&fields, Size_Field{data[3] == 2 ? 13 : 14, data[3] == 2 ? 3 : 4})
	}
	if ape := strings.last_index(string(data), "APETAGEX"); ape >= 0 && ape + 20 <= len(data) {
		append(&fields, Size_Field{ape + 12, 4}, Size_Field{ape + 16, 4})
	}
	return fields[:]
}

@(private = "file")
read_file :: proc(path: string) -> []u8 {
	data, _ := os.read_entire_file_from_path(path, context.temp_allocator)
	return data
}

// The bytes odid3 keeps between the tags of a file, the audio among them: on a damaged
// file, the independent extraction of write_test.odin cannot tell a broken ID3v2
// header, which odid3 keeps as unknown bytes, from the audio.
@(private = "file")
audio :: proc(path: string) -> []u8 {
	tags, err := id3.read_file(path, {skip_picture_data = true})
	if err != nil do return nil
	defer id3.destroy(&tags)
	data := read_file(path)
	region := tags.layout.audio
	return data[region.offset:][:region.size]
}
