package library_tests

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

TESTDATA :: #directory + "/../../../testdata"

// A new temporary folder holding files, each with i + 1 bytes so that sizes differ.
// Remove it with remove_folder.
folder_with :: proc(t: ^testing.T, files: []string) -> string {
	folder, err := make_temp_folder()
	testing.expect(t, err == nil)
	for file, i in files {
		path := fmt.tprintf("%s/%s", folder, file)
		made := os.make_directory_all(filepath.dir(path))
		testing.expect(t, made == nil || made == .Exist)
		bytes := make([]u8, i + 1, context.temp_allocator)
		testing.expect(t, os.write_entire_file(path, bytes) == nil)
	}
	return folder
}

remove_folder :: proc(folder: string) {
	_ = os.remove_all(folder)
	delete(folder)
	free_all(context.temp_allocator)
}

fixture :: proc(name: string) -> string {
	return fmt.tprintf("%s/%s", TESTDATA, name)
}

// A new temporary folder. Windows now and then refuses one when the tests make several
// at once, so it is asked for again a few times before the error is given.
make_temp_folder :: proc(pattern := "colophon-*") -> (folder: string, err: os.Error) {
	for _ in 0 ..< 10 {
		folder, err = os.make_directory_temp("", pattern, context.allocator)
		if err == nil do return
		time.sleep(10 * time.Millisecond)
	}
	return
}
