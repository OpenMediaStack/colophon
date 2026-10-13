package library

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"

import id3 "../../libs/odid3"

// Why a file could not be written. Its tags are left as they were.
Write_Error :: enum u8 {
	None,
	// The file is marked read only, which Colophon respects.
	Read_Only,
	// The file, or the folder that holds it, could not be read or written.
	Cannot_Write,
	// The file holds no tags or audio Colophon can make sense of.
	Damaged,
	// A value the tag version cannot hold.
	Cannot_Encode,
	// The file changed while it was rewritten: it is left as the other program made it.
	Changed,
	// The tags were written, but the file could not be read back.
	Cannot_Read_Back,
}

// Writes tags into the MP3 at path, in the tags and versions of versions, and removes
// the ID3 tags it leaves out. Every other frame, the APE tag and the audio stay as they
// are, and a field whose value does not change keeps its frame as it was: its
// encoding, a full date whose year stays. odid3 writes a copy next to the file and
// renames it over the file once complete: a failed write leaves the file untouched.
// Gives back the track as its file now is, read with allocator.
write_track :: proc(
	path: string,
	tags: Tags,
	versions: Tag_Versions,
	allocator := context.allocator,
) -> (
	track: Track,
	err: Write_Error,
) {
	err = write_tags(path, tags, versions, allocator)
	if err != .None do return
	track = read_track(path, allocator)
	if track.error != .None {
		destroy_track(&track, allocator)
		return {}, .Cannot_Read_Back
	}
	return track, .None
}

@(private = "file")
write_tags :: proc(
	path: string,
	tags: Tags,
	versions: Tag_Versions,
	allocator: runtime.Allocator,
) -> Write_Error {
	info, stat_err := os.stat(path, allocator)
	if stat_err != nil do return .Cannot_Write
	read_only := .Write_User not_in info.mode
	os.file_info_delete(info, allocator)
	if read_only do return .Read_Only
	file, read_err := id3.read_file(path, {}, allocator)
	if read_err != nil do return write_error(read_err)
	defer id3.destroy(&file)

	// The fields go into the ID3v2 tag that will be written, or into a scratch one that
	// only the ID3v1 tag is made from.
	scratch: id3.Tag
	defer id3.destroy(&scratch)
	source := &file.v2
	if version, ok := versions.id3v2.?; ok {
		dropped, convert_err := id3.convert(&file.v2, V2_VERSIONS[version], allocator)
		id3.destroy(&dropped, allocator)
		if convert_err != nil do return write_error(convert_err)
	} else {
		id3.destroy(&file.v2)
		scratch = {
			version   = .V2_4,
			allocator = allocator,
		}
		source = &scratch
	}
	if err := set_fields(source, tags); err != nil do return write_error(err)

	if version, ok := versions.id3v1.?; ok {
		old := &file.v1
		enhanced := old.version != .None && old.enhanced != nil
		encoding := old.encoding if old.version != .None else id3.V1_Encoding.Latin1
		v1, _, v1_err := id3.v1_from_tag(
			source,
			V1_VERSIONS[version],
			enhanced,
			encoding,
			allocator,
		)
		if v1_err != nil do return .Cannot_Write
		id3.destroy(old)
		file.v1 = v1
	} else {
		id3.destroy(&file.v1)
	}
	// 1.0.0 rewrote what it could read of a damaged tag, as this does.
	if err := id3.write_file(path, &file, {replace_damaged = true}, allocator); err != nil {
		return write_error(err)
	}
	return .None
}

@(private = "file", rodata)
V2_VERSIONS := [Id3v2_Version]id3.V2_Version {
	.V2_2 = .V2_2,
	.V2_3 = .V2_3,
	.V2_4 = .V2_4,
}

@(private = "file", rodata)
V1_VERSIONS := [Id3v1_Version]id3.V1_Version {
	.V1_0 = .V1_0,
	.V1_1 = .V1_1,
}

// Sets the generic fields of tags in tag. odid3 leaves a field whose value does not
// change as it is; the year is compared apart, so that a full date keeps its month and
// day while its year stays.
@(private = "file")
set_fields :: proc(tag: ^id3.Tag, tags: Tags) -> id3.Error {
	text :: proc(value: Maybe(string)) -> string {
		return value.? or_else ""
	}
	id3.set(tag, .Title, text(tags.title)) or_return
	id3.set(tag, .Artist, text(tags.artist)) or_return
	id3.set(tag, .Album_Artist, text(tags.album_artist)) or_return
	id3.set(tag, .Album, text(tags.album)) or_return
	id3.set(tag, .Genre, text(tags.genre)) or_return
	id3.set(tag, .Comment, text(tags.comment)) or_return
	year, has_year := id3.tag_year(tag)
	wanted, wants_year := tags.year.?
	if has_year != wants_year || year != wanted {
		buffer: [8]u8
		date := wants_year ? fmt.bprintf(buffer[:], "%04d", wanted) : ""
		id3.set(tag, .Date, date) or_return
	}
	// A total without its number would read back as no number at all.
	track, track_total := pair(tags.track, tags.track_total)
	if number, total := id3.tag_track(tag); number != track || total != track_total {
		id3.set_track(tag, track, track_total) or_return
	}
	disc, disc_total := pair(tags.disc, tags.disc_total)
	if number, total := id3.tag_disc(tag); number != disc || total != disc_total {
		id3.set_disc(tag, disc, disc_total) or_return
	}
	return nil

	pair :: proc(number, total: Maybe(int)) -> (int, int) {
		n, ok := number.?
		if !ok do return 0, 0
		return n, total.? or_else 0
	}
}

@(private = "file")
write_error :: proc(err: id3.Error) -> Write_Error {
	switch e in err {
	case id3.Format_Error:
		#partial switch e {
		case .File_Changed:
			return .Changed
		case .Not_Encodable, .Bad_Value, .Not_In_Version, .Encoding_Not_In_Version, .Tag_Too_Large:
			return .Cannot_Encode
		case .Incomplete_Tag, .Damaged_Tag, .Bad_Content:
			return .Damaged
		}
		return .Damaged
	case os.Error:
		return .Cannot_Write
	case runtime.Allocator_Error:
		return .Cannot_Write
	}
	return .None
}

// A file to write, and the tags to write into it, in which versions. id is handed back
// with the outcome.
Save_Job :: struct {
	id:       int,
	path:     string,
	tags:     Tags,
	versions: Tag_Versions,
}

// A file as it is once written. The track is the caller's: free it with destroy_track.
Saved :: struct {
	id:    int,
	track: Track,
}

// A file that could not be written.
Save_Failure :: struct {
	id:    int,
	error: Write_Error,
}

// The save has written every file, or stopped.
Save_Finished :: struct {}

// What a save reports: each file written or not, in order, then its end.
Save_Event :: union {
	Saved,
	Save_Failure,
	Save_Finished,
}

// A save running on its own thread. Take its events with take_save_events; free it
// with destroy_save, which stops it after the file being written.
Save :: struct {
	allocator: runtime.Allocator,
	jobs:      []Save_Job,
	wake:      Wake,
	stop:      bool,
	mutex:     sync.Mutex,
	events:    [dynamic]Save_Event,
	thread:    ^thread.Thread,
}

// Writes each job's tags into its file, one file after the other, on a new thread, so
// that the UI thread never waits for the disk. The jobs are copied. allocator must be
// thread safe. ok is false when the thread cannot be started.
start_save :: proc(
	jobs: []Save_Job,
	wake := Wake{},
	allocator := context.allocator,
) -> (
	s: ^Save,
	ok: bool,
) {
	s = new(Save, allocator)
	s.allocator = allocator
	s.jobs = make([]Save_Job, len(jobs), allocator)
	for job, i in jobs {
		s.jobs[i] = {
			job.id,
			strings.clone(job.path, allocator),
			clone_tags(job.tags, allocator),
			job.versions,
		}
	}
	s.wake = wake
	s.events = make([dynamic]Save_Event, allocator)
	s.thread = thread.create_and_start_with_data(s, run_save)
	if s.thread == nil {
		destroy_save(s)
		return nil, false
	}
	return s, true
}

// Moves the events reported since the last call to the end of into. The caller owns
// them: free them with destroy_save_event.
take_save_events :: proc(s: ^Save, into: ^[dynamic]Save_Event) {
	sync.mutex_lock(&s.mutex)
	defer sync.mutex_unlock(&s.mutex)
	append(into, ..s.events[:])
	clear(&s.events)
}

// Stops the save after the file being written, waits for its thread, and frees it
// with the events no one took.
destroy_save :: proc(s: ^Save) {
	sync.atomic_store(&s.stop, true)
	if s.thread != nil {
		thread.join(s.thread)
		thread.destroy(s.thread)
	}
	for &event in s.events do destroy_save_event(&event, s.allocator)
	delete(s.events)
	for &job in s.jobs {
		delete(job.path, s.allocator)
		destroy_tags(&job.tags, s.allocator)
	}
	delete(s.jobs, s.allocator)
	free(s, s.allocator)
}

// Frees an event with the allocator its save was started with.
destroy_save_event :: proc(event: ^Save_Event, allocator := context.allocator) {
	if saved, ok := &event.(Saved); ok do destroy_track(&saved.track, allocator)
	event^ = nil
}

@(private = "file")
run_save :: proc(data: rawptr) {
	s := (^Save)(data)
	report :: proc(s: ^Save, event: Save_Event) {
		sync.mutex_lock(&s.mutex)
		was_empty := len(s.events) == 0
		append(&s.events, event)
		sync.mutex_unlock(&s.mutex)
		if was_empty && s.wake.procedure != nil do s.wake.procedure(s.wake.data)
	}
	for job in s.jobs {
		if sync.atomic_load(&s.stop) do break
		track, err := write_track(job.path, job.tags, job.versions, s.allocator)
		if err == .None {
			report(s, Saved{job.id, track})
		} else {
			report(s, Save_Failure{job.id, err})
		}
	}
	report(s, Save_Finished{})
}
