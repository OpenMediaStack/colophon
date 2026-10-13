package library_tests

import "core:bytes"
import "core:fmt"
import "core:os"
import "core:slice"
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

// The audio bytes of a file, between its tags. Allocated with the temp allocator.
@(private = "file")
audio_of :: proc(path: string) -> []u8 {
	tags, err := id3.read_file(path, {skip_picture_data = true})
	if err != nil do return nil
	defer id3.destroy(&tags)
	data, _ := os.read_entire_file_from_path(path, context.temp_allocator)
	audio := tags.layout.audio
	return data[audio.offset:][:audio.size]
}

@(private = "file")
read_tags :: proc(t: ^testing.T, path: string) -> (track: lib.Track) {
	track = lib.read_track(path)
	testing.expect_value(t, track.error, lib.Read_Error.None)
	return
}

@(test)
every_version_round_trips_and_keeps_the_audio :: proc(t: ^testing.T) {
	Case :: struct {
		versions: lib.Tag_Versions,
		formats:  lib.Tag_Formats,
	}
	cases := [?]Case {
		{{.V2_4, nil}, {id3v2 = .V2_4}},
		{{.V2_3, .V1_1}, {id3v2 = .V2_3, id3v1 = .V1_1}},
		{{.V2_2, .V1_0}, {id3v2 = .V2_2, id3v1 = .V1_0}},
		{{nil, .V1_1}, {id3v1 = .V1_1}},
		{{nil, nil}, {}},
	}
	original := lib.read_track(fixture("v23_full.mp3"))
	defer lib.destroy_track(&original)
	// remove_folder frees the temp allocator: the bytes to compare with need their own.
	audio := slice.clone(audio_of(fixture("v23_full.mp3")))
	defer delete(audio)
	for c in cases {
		folder, path := copy_of(t, "v23_full.mp3")
		defer remove_folder(folder)
		tags := original.metadata.tags
		tags.title = "Written again"

		track, err := lib.write_track(path, tags, c.versions)
		defer lib.destroy_track(&track)

		testing.expectf(t, err == .None, "%v: %v", c.versions, err)
		testing.expectf(
			t,
			track.metadata.formats == c.formats,
			"%v: %v",
			c.versions,
			track.metadata.formats,
		)
		testing.expectf(t, bytes.equal(audio_of(path), audio), "%v: the audio changed", c.versions)
		if c.versions.id3v2 != nil {
			testing.expectf(
				t,
				track.metadata.tags == tags,
				"%v: %v",
				c.versions,
				track.metadata.tags,
			)
		}
	}
}

@(test)
other_frames_stay_as_they_were :: proc(t: ^testing.T) {
	folder, path := copy_of(t, "v23_cover.mp3")
	defer remove_folder(folder)
	before := read_tags(t, path)
	defer lib.destroy_track(&before)
	tags := before.metadata.tags
	tags.title = "Another title"

	track, err := lib.write_track(path, tags, {.V2_3, nil})
	defer lib.destroy_track(&track)

	testing.expect_value(t, err, lib.Write_Error.None)
	testing.expect(t, track.metadata.tags.has_cover)
	file, read_err := id3.read_file(path)
	defer id3.destroy(&file)
	testing.expect(t, read_err == nil)
	publisher := id3.get(&file.v2, .Title, context.temp_allocator)
	testing.expect_value(t, publisher, "Another title")
	found := false
	for f in file.v2.frames do if f.id == "TPUB" do found = true
	testing.expect(t, found, "the publisher frame is lost")
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
		{1, one, {title = "One"}, {.V2_4, nil}},
		{2, fmt.tprintf("%s/missing.mp3", folder), {title = "Two"}, {.V2_4, nil}},
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
	for len(events) == 0 || events[len(events) - 1] != lib.Save_Event(lib.Save_Finished{}) {
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
