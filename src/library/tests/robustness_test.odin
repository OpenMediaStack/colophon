package library_tests

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:testing"

import lib ".."

// Every fixture, cut short at many lengths and with random bytes changed in its tags,
// scans without a panic, and each file is a track, read or not. Every fifth damaged
// file that reads is saved again, which either fails or reads back.
@(test)
damaged_files_scan_and_save_without_a_panic :: proc(t: ^testing.T) {
	state := rand.create(20261014)
	context.random_generator = rand.default_random_generator(&state)
	folder := folder_with(t, {})
	defer remove_folder(folder)
	entries, err := os.read_all_directory_by_path(TESTDATA, context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	written := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".mp3") do continue
		data, read_err := os.read_entire_file_from_path(fixture(entry.name), context.allocator)
		if !testing.expect(t, read_err == nil) do continue
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
		again, write_err := lib.write_track(track.path, tags, {.V2_4, .V1_1})
		defer lib.destroy_track(&again)
		if write_err == .None {
			saved += 1
			testing.expectf(t, again.metadata.tags.title == "Saved again", "%s", track.path)
		}
	}
	testing.expect_value(t, tracks, written)
	testing.expectf(t, saved > 0, "no damaged file could be saved again")
}
