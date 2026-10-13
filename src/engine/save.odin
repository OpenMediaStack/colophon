package engine

import "core:slice"

import lib "../library"

// Writes every pending change to its file, in the background.
Save :: struct {}

// The same, but the files the write policy alone would strip of their ID3v1 tag keep
// it.
Save_Keeping_Id3v1 :: struct {}

// How far a save has got.
Save_Progress :: struct {
	done, total: int,
}

// A file a save could not write. Its changes stay pending.
Save_Failure :: struct {
	track: Track_Id,
	error: lib.Write_Error,
}

@(private)
Saving :: struct {
	save:     ^lib.Save,
	progress: Save_Progress,
}

// How far the running save has got, if one runs.
saving :: proc(e: ^Engine) -> Maybe(Save_Progress) {
	s, running := e.saving.?
	if !running do return nil
	return s.progress
}

// The tracks with pending changes, in library order. Allocated with allocator.
pending_tracks :: proc(e: ^Engine, allocator := context.allocator) -> []Track_Id {
	tracks := make([dynamic]Track_Id, 0, len(e.edits.pending), allocator)
	for track in e.edits.pending do append(&tracks, track)
	slice.sort(tracks[:])
	return tracks[:]
}

// The tracks with changes that saving would strip of their ID3v1 tag because the write
// policy never writes one, and not because the user chose so for them: saving them asks
// first. Allocated with allocator.
losing_id3v1_to_policy :: proc(e: ^Engine, allocator := context.allocator) -> []Track_Id {
	losing := make([dynamic]Track_Id, allocator)
	for track in pending_tracks(e, context.temp_allocator) {
		versions, _ := versions_of(e, track)
		kept, _ := versions_keeping_id3v1(e, track)
		if versions != kept do append(&losing, track)
	}
	return losing[:]
}

// The versions to write a track in, but a track the policy alone would strip of its
// ID3v1 tag keeps it.
@(private)
versions_keeping_id3v1 :: proc(
	e: ^Engine,
	track: Track_Id,
) -> (
	versions: lib.Tag_Versions,
	ok: bool,
) {
	versions = versions_of(e, track) or_return
	if track in e.edits.chosen || versions.id3v1 != nil do return versions, true
	versions.id3v1 = e.library.tracks[track].metadata.formats.id3v1
	return versions, true
}

// Starts writing every pending change, unless a save already runs.
@(private)
save :: proc(e: ^Engine, keeping_id3v1: bool) {
	if e.saving != nil do return
	jobs := make([dynamic]lib.Save_Job, context.temp_allocator)
	for track in pending_tracks(e, context.temp_allocator) {
		versions: lib.Tag_Versions
		ok: bool
		if keeping_id3v1 {
			versions, ok = versions_keeping_id3v1(e, track)
		} else {
			versions, ok = versions_of(e, track)
		}
		if !ok do continue
		path := e.library.tracks[track].path
		append(&jobs, lib.Save_Job{int(track), path, e.edits.pending[track], versions})
	}
	if len(jobs) == 0 do return
	clear(&e.save_failures)
	s, started := lib.start_save(jobs[:], e.wake, e.allocator)
	if !started {
		for job in jobs do append(&e.save_failures, Save_Failure{Track_Id(job.id), .Cannot_Write})
		return
	}
	e.saving = Saving{s, {0, len(jobs)}}
}

// Takes in the files the save wrote: each track gets what its file now holds, and its
// pending tags go once the file holds them. A change made meanwhile stays pending.
// True when anything changed.
@(private)
poll_save :: proc(e: ^Engine) -> (changed: bool) {
	s, running := &e.saving.?
	if !running do return
	events := make([dynamic]lib.Save_Event, context.temp_allocator)
	lib.take_save_events(s.save, &events)
	finished := false
	for &event in events {
		changed = true
		switch ev in event {
		case lib.Saved:
			s.progress.done += 1
			take_saved(e, Track_Id(ev.id), ev.track)
			event = nil
		case lib.Save_Failure:
			s.progress.done += 1
			append(&e.save_failures, Save_Failure{Track_Id(ev.id), ev.error})
		case lib.Save_Finished:
			finished = true
		}
	}
	if finished {
		lib.destroy_save(s.save)
		e.saving = nil
	}
	return
}

// Puts what a track's file holds once written in place of what it held. The track
// keeps its path, which found borrows.
@(private = "file")
take_saved :: proc(e: ^Engine, id: Track_Id, written: lib.Track) {
	written := written
	if !has_track(e, id) {
		lib.destroy_track(&written)
		return
	}
	track := &e.library.tracks[id]
	lib.destroy_tags(&track.metadata.tags)
	track.metadata = written.metadata
	track.size = written.size
	track.modified = written.modified
	track.error = .None
	delete(written.path)
	e.saved[id] = {}
	settle(e, id)
}
