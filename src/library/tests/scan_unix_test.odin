#+build !windows
package library_tests

import "core:os"
import "core:strings"
import "core:testing"

import lib ".."

@(test)
skips_an_unreadable_folder_and_reads_the_others :: proc(t: ^testing.T) {
	folder := folder_with(t, {"Locked/hidden.mp3", "Open/visible.mp3"})
	defer remove_folder(folder)
	locked := strings.concatenate({folder, "/Locked"}, context.temp_allocator)
	testing.expect(t, os.change_mode(locked, {}) == nil)
	events := scan_all(folder)
	defer destroy_events(&events)
	testing.expect(t, os.change_mode(locked, os.Permissions_Default) == nil)
	paths := found(folder, events[:])
	testing.expect_value(t, len(paths), 1)
	if len(paths) == 1 do testing.expect_value(t, paths[0], "Open/visible.mp3")
	reported := false
	for event in events {
		if failure, ok := event.(lib.Scan_Error); ok && failure.path == locked do reported = true
	}
	testing.expect(t, reported)
	testing.expect_value(t, events[len(events) - 1], lib.Scan_Event(lib.Scan_Outcome.Completed))
}

@(test)
the_entries_of_a_folder_that_cannot_be_searched_are_reported_alone :: proc(t: ^testing.T) {
	folder := folder_with(t, {"Locked/1.mp3", "Locked/2.mp3", "Locked/3.mp3", "Open/a.mp3"})
	defer remove_folder(folder)
	locked := strings.concatenate({folder, "/Locked"}, context.temp_allocator)
	// Readable, so its names can be listed, but not searchable, so its entries cannot be read.
	testing.expect(t, os.change_mode(locked, {.Read_User}) == nil)
	events := scan_all(folder)
	defer destroy_events(&events)
	testing.expect(t, os.change_mode(locked, os.Permissions_Default) == nil)
	inside := strings.concatenate({locked, "/"}, context.temp_allocator)
	errors := 0
	for event in events {
		failure := event.(lib.Scan_Error) or_continue
		errors += 1
		testing.expectf(
			t,
			strings.has_prefix(failure.path, inside),
			"%s is not an entry of %s",
			failure.path,
			locked,
		)
	}
	// One per entry on macOS; Linux keeps only the last.
	testing.expect(t, errors >= 1)
	paths := found(folder, events[:])
	testing.expect(t, len(paths) == 1 && paths[0] == "Open/a.mp3")
}
