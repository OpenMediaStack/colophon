package library_tests

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import lib ".."

// Runs a scan to the end and returns its events; free them with destroy_events.
scan_all :: proc(root: string) -> (events: [dynamic]lib.Scan_Event) {
	stop := false
	extensions := lib.AUDIO_EXTENSIONS
	report :: proc(event: lib.Scan_Event, data: rawptr) {
		append((^[dynamic]lib.Scan_Event)(data), event)
	}
	outcome := lib.scan(root, extensions[:], &stop, report, &events)
	append(&events, outcome)
	return
}

destroy_events :: proc(events: ^[dynamic]lib.Scan_Event) {
	for &event in events do lib.destroy_scan_event(&event)
	delete(events^)
}

// The paths of the files found, relative to root.
found :: proc(root: string, events: []lib.Scan_Event) -> []string {
	paths := make([dynamic]string, context.temp_allocator)
	for event in events {
		if track, ok := event.(lib.Track); ok do append(&paths, strings.trim_prefix(track.path, strings.concatenate({root, "/"}, context.temp_allocator)))
	}
	return paths[:]
}

@(test)
finds_mp3_files_in_subfolders_sorted_by_name :: proc(t: ^testing.T) {
	folder := folder_with(t, {"b.mp3", "a.mp3", "Album/02.mp3", "Album/01.mp3"})
	defer remove_folder(folder)
	events := scan_all(folder)
	defer destroy_events(&events)
	testing.expect_value(t, len(found(folder, events[:])), 4)
	want := []string{"Album/01.mp3", "Album/02.mp3", "a.mp3", "b.mp3"}
	for path, i in found(folder, events[:]) do testing.expect_value(t, path, want[i])
	testing.expect_value(t, events[len(events) - 1], lib.Scan_Event(lib.Scan_Outcome.Completed))
}

@(test)
matches_the_extension_whatever_its_case :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.MP3", "b.Mp3"})
	defer remove_folder(folder)
	events := scan_all(folder)
	defer destroy_events(&events)
	testing.expect_value(t, len(found(folder, events[:])), 2)
}

@(test)
ignores_other_formats_and_hidden_entries :: proc(t: ^testing.T) {
	folder := folder_with(
		t,
		{"cover.jpg", "notes.txt", ".hidden.mp3", "._a.mp3", ".cache/c.mp3", "song.mp3", "mp3"},
	)
	defer remove_folder(folder)
	events := scan_all(folder)
	defer destroy_events(&events)
	paths := found(folder, events[:])
	testing.expect_value(t, len(paths), 1)
	if len(paths) == 1 do testing.expect_value(t, paths[0], "song.mp3")
}

@(test)
reports_the_size_and_the_modification_date :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3", "b.mp3"})
	defer remove_folder(folder)
	events := scan_all(folder)
	defer destroy_events(&events)
	sizes := [2]i64{}
	i := 0
	for event in events {
		track := event.(lib.Track) or_continue
		sizes[i] = track.size
		testing.expect(t, time.since(track.modified) < time.Hour)
		i += 1
	}
	testing.expect_value(t, sizes, [2]i64{1, 2})
}

@(test)
stops_when_asked :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3", "b.mp3"})
	defer remove_folder(folder)
	stop := true
	extensions := lib.AUDIO_EXTENSIONS
	count := 0
	report :: proc(event: lib.Scan_Event, data: rawptr) {
		(^int)(data)^ += 1
		event := event
		lib.destroy_scan_event(&event)
	}
	outcome := lib.scan(folder, extensions[:], &stop, report, &count)
	testing.expect_value(t, outcome, lib.Scan_Outcome.Stopped)
	testing.expect_value(t, count, 0)
}

@(test)
reports_a_missing_folder_and_still_finishes :: proc(t: ^testing.T) {
	events := scan_all("/this/folder/does/not/exist")
	defer destroy_events(&events)
	testing.expect_value(t, len(events), 2)
	failure, ok := events[0].(lib.Scan_Error)
	testing.expect(t, ok)
	testing.expect_value(t, failure.path, "/this/folder/does/not/exist")
	testing.expect_value(t, events[1], lib.Scan_Event(lib.Scan_Outcome.Completed))
}

@(test)
a_file_root_is_reported_alone :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3", "b.mp3"})
	defer remove_folder(folder)
	events := scan_all(strings.concatenate({folder, "/a.mp3"}, context.temp_allocator))
	defer destroy_events(&events)
	testing.expect_value(t, len(found(folder, events[:])), 1)
}

@(test)
a_spawned_scan_reads_files_and_folders_and_finishes_once :: proc(t: ^testing.T) {
	folder := folder_with(t, {"One/a.mp3", "Two/b.mp3", "c.mp3"})
	defer remove_folder(folder)
	roots := []string {
		strings.concatenate({folder, "/One"}, context.temp_allocator),
		strings.concatenate({folder, "/c.mp3"}, context.temp_allocator),
	}
	extensions := lib.AUDIO_EXTENSIONS
	scan := lib.start_scan(roots, extensions[:])
	defer lib.destroy_scan(scan)
	events: [dynamic]lib.Scan_Event
	defer destroy_events(&events)
	deadline := time.tick_now()
	for {
		lib.take_scan_events(scan, &events)
		if len(events) > 0 {
			if _, done := events[len(events) - 1].(lib.Scan_Outcome); done do break
		}
		if time.tick_since(deadline) > 20 * time.Second do break
		time.sleep(time.Millisecond)
	}
	outcomes := 0
	for event in events do if _, ok := event.(lib.Scan_Outcome); ok do outcomes += 1
	testing.expect_value(t, outcomes, 1)
	testing.expect_value(t, len(found(folder, events[:])), 2)
}

@(test)
a_found_file_carries_its_tags :: proc(t: ^testing.T) {
	track := lib.read_track(fixture("v23_full.mp3"))
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.error, lib.Read_Error.None)
	testing.expect(t, track.metadata.tags.title != nil)
	testing.expect_value(
		t,
		track.metadata.formats.id3v2,
		Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_3),
	)
	testing.expect(t, track.metadata.audio.sample_rate > 0)
}

@(test)
a_file_whose_tags_cannot_be_read_is_found_all_the_same :: proc(t: ^testing.T) {
	folder := folder_with(t, {"broken.mp3"})
	defer remove_folder(folder)
	events := scan_all(folder)
	defer destroy_events(&events)
	track, ok := events[0].(lib.Track)
	testing.expect(t, ok)
	testing.expect_value(t, track.error, lib.Read_Error.Damaged)
}

@(test)
a_missing_file_cannot_be_opened :: proc(t: ^testing.T) {
	track := lib.read_track("/this/file/does/not/exist.mp3")
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.error, lib.Read_Error.Cannot_Open)
	_ = os.exists(track.path)
}
