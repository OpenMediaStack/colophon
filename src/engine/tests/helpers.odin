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

TESTDATA :: #directory + "/../../../testdata"

// A new temporary folder holding copies of fixtures of testdata/, each under its new
// name. Remove it with remove_folder.
folder_with_fixtures :: proc(t: ^testing.T, copies: [][2]string) -> string {
	folder, err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, err == nil)
	for c in copies {
		path := fmt.tprintf("%s/%s", folder, c[1])
		made := os.make_directory_all(filepath.dir(path))
		testing.expect(t, made == nil || made == .Exist)
		testing.expect(t, os.copy_file(path, fmt.tprintf("%s/%s", TESTDATA, c[0])) == nil)
	}
	return folder
}

// An engine that has read the whole folder. Free it with engine.destroy.
engine_reading :: proc(t: ^testing.T, e: ^engine.Engine, folder: string) {
	engine.init(e)
	engine.execute(e, engine.Open_Folder{folder})
	poll_until_done(t, e)
}

// The file names of the tracks the table lists, in its order.
listed_names :: proc(e: ^engine.Engine) -> []string {
	names := make([]string, len(e.listed), context.temp_allocator)
	for id, i in e.listed do names[i] = filepath.base(e.library.tracks[id].path)
	return names
}

// The track of this file name.
track_named :: proc(e: ^engine.Engine, name: string) -> engine.Track_Id {
	for track, i in e.library.tracks {
		if filepath.base(track.path) == name do return engine.Track_Id(i)
	}
	return -1
}
