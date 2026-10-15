package library_tests

import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"

import lib ".."
import id3 "../../../libs/odid3"

// A copy of a fixture in a new folder. Remove the folder with remove_folder.
@(private = "file")
copy_of :: proc(t: ^testing.T, name: string) -> (folder, path: string) {
	folder = folder_with(t, {})
	path = fmt.tprintf("%s/%s", folder, name)
	testing.expect(t, os.copy_file(path, fixture(name)) == nil)
	return
}

@(private = "file")
read_tags :: proc(t: ^testing.T, path: string) -> (track: lib.Track) {
	track = lib.read_track(path)
	testing.expect_value(t, track.error, lib.Read_Error.None)
	return
}

@(test)
a_full_date_keeps_its_month_and_day_while_its_year_stays :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v24_full.mp3")
	defer remove_folder(folder)
	file, _ := id3.read_file(path)
	testing.expect(t, id3.set(&file.v2, .Date, "2019-05-03") == nil)
	testing.expect(t, id3.write_file(path, &file) == nil)
	id3.destroy(&file)
	before := read_tags(t, path)
	defer lib.destroy_track(&before)
	tags := before.metadata.tags
	tags.album = "Another album"

	track, err := lib.write_track(path, tags, {.V2_4, nil})
	defer lib.destroy_track(&track)

	testing.expect_value(t, err, lib.Write_Error.None)
	file, _ = id3.read_file(path)
	defer id3.destroy(&file)
	testing.expect_value(t, id3.get(&file.v2, .Date, context.temp_allocator), "2019-05-03")
	free_all(context.temp_allocator)
}

@(test)
an_emptied_field_leaves_both_tags :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_v1_long_title.mp3")
	defer remove_folder(folder)
	before := read_tags(t, path)
	defer lib.destroy_track(&before)
	tags := before.metadata.tags
	tags.comment = nil
	tags.artist = nil

	track, err := lib.write_track(path, tags, {.V2_4, .V1_1})
	defer lib.destroy_track(&track)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expect_value(t, track.metadata.tags.artist, nil)
	file, _ := id3.read_file(path)
	defer id3.destroy(&file)
	testing.expect_value(t, file.v1.artist, "")
	testing.expect_value(t, file.v1.comment, "")
}

@(test)
a_save_writes_each_file_then_finishes :: proc(t: ^testing.T) {
	folder := folder_with(t, {})
	defer remove_folder(folder)
	one := fmt.tprintf("%s/1.mp3", folder)
	two := fmt.tprintf("%s/2.mp3", folder)
	testing.expect(t, os.copy_file(one, fixture("v23_full.mp3")) == nil)
	testing.expect(t, os.copy_file(two, fixture("v24_unicode.mp3")) == nil)
	jobs := []lib.Save_Job {
		{1, one, {title = "One"}, {.V2_4, nil}, {}},
		{2, fmt.tprintf("%s/missing.mp3", folder), {title = "Two"}, {.V2_4, nil}, {}},
	}
	save, started := lib.start_save(jobs)
	if !testing.expect(t, started) do return
	defer lib.destroy_save(save)
	events: [dynamic]lib.Save_Event
	defer {
		for &event in events do lib.destroy_save_event(&event)
		delete(events)
	}
	start := time.tick_now()
	for !ended(events[:]) {
		if time.tick_since(start) > 20 * time.Second do break
		lib.take_save_events(save, &events)
		time.sleep(time.Millisecond)
	}
	if !testing.expect_value(t, len(events), 3) do return
	saved, ok := events[0].(lib.Saved)
	testing.expect(t, ok && saved.id == 1 && saved.track.metadata.tags.title == "One")
	failure, failed := events[1].(lib.Save_Failure)
	testing.expect(t, failed && failure.id == 2 && failure.error == .Cannot_Write)
}

// Whether the last event says the save ended.
@(private = "file")
ended :: proc(events: []lib.Save_Event) -> bool {
	if len(events) == 0 do return false
	_, finished := events[len(events) - 1].(lib.Save_Finished)
	return finished
}
