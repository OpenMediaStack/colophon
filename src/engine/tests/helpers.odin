package engine_tests

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

import "../../engine"

// How long a test waits for a thread, in real time: long enough for a busy machine.
PATIENCE :: 20 * time.Second

// A new temporary folder holding files of a few bytes each. Remove it with
// remove_folder.
folder_with :: proc(t: ^testing.T, files: []string) -> string {
	folder, err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, err == nil)
	for file in files {
		path := fmt.tprintf("%s/%s", folder, file)
		made := os.make_directory_all(filepath.dir(path))
		testing.expect(t, made == nil || made == .Exist)
		testing.expect(t, os.write_entire_file(path, transmute([]u8)string("ID3")) == nil)
	}
	return folder
}

remove_folder :: proc(folder: string) {
	_ = os.remove_all(folder)
	delete(folder)
	free_all(context.temp_allocator)
}

// Polls the engine as the UI does, until its scans end or PATIENCE passes.
poll_until_done :: proc(t: ^testing.T, e: ^engine.Engine) {
	start := time.tick_now()
	for e.library.status == .Scanning {
		if time.tick_since(start) > PATIENCE {
			testing.fail_now(t, "the scan did not finish in time")
		}
		engine.poll(e)
		time.sleep(time.Millisecond)
	}
}

// The file names of the library's tracks, in its order.
file_names :: proc(e: ^engine.Engine) -> []string {
	names := make([]string, len(e.library.tracks), context.temp_allocator)
	for track, i in e.library.tracks do names[i] = filepath.base(track.path)
	return names
}

expect_strings :: proc(t: ^testing.T, got, want: []string, loc := #caller_location) {
	if !testing.expectf(t, len(got) == len(want), "got %v, want %v", got, want, loc = loc) do return
	for s, i in got do testing.expectf(t, s == want[i], "got %v, want %v", got, want, loc = loc)
}
