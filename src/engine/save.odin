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

// How a save ended: how many files it wrote, and how many it could not.
Save_Report :: struct {
	written, failed: int,
}

@(private)
Saving :: struct {
	save:     ^lib.Save,
	progress: Save_Progress,
	// The key of the cover sent for each track, so that a track whose cover was
	// written settles, while one replaced again meanwhile stays pending.
	sent:     map[Track_Id]Maybe(lib.Cover_Key),
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

// A tag a choice of versions may remove.
Removable_Tag :: enum u8 {
	Id3v1,
	Id3v2,
}

// The selected tracks whose file has the tag and whose versions to write, chosen or
// by the write policy, still keep it: those that choosing to remove it would strip.
// Allocated with allocator.
losing_tag :: proc(e: ^Engine, tag: Removable_Tag, allocator := context.allocator) -> []Track_Id {
	losing := make([dynamic]Track_Id, allocator)
	for track in e.selection.tracks {
		if e.library.tracks[track].error != .None do continue
		formats := e.library.tracks[track].metadata.formats
		versions := versions_of(e, track) or_continue
		has, kept := formats.id3v1 != nil, versions.id3v1 != nil
		if tag == .Id3v2 {
			has, kept = formats.id3v2 != nil, versions.id3v2 != nil
		}
		if has && kept do append(&losing, track)
	}
	return losing[:]
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
	sent := make(map[Track_Id]Maybe(lib.Cover_Key), e.allocator)
	for job in jobs do sent[Track_Id(job.id)] = lib.cover_key(job.tags.cover)
	e.saving = Saving{s, {0, len(jobs)}, sent}
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
			take_saved(e, Track_Id(ev.id), ev.track, s.sent[Track_Id(ev.id)])
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
		delete(s.sent)
		e.last_save = {s.progress.done - len(e.save_failures), len(e.save_failures)}
		e.saves_ended += 1
		e.saving = nil
	}
	return
}

// Puts what a track's file holds once written in place of what it held. The track
// keeps its path, which found borrows.
@(private = "file")
take_saved :: proc(e: ^Engine, id: Track_Id, written: lib.Track, sent: Maybe(lib.Cover_Key)) {
	written := written
	if !has_track(e, id) {
		lib.destroy_track(&written)
		return
	}
	// What the user wants now, before the file's tags change under it: an undo made
	// while saving brings back what the file held, which is a change to save again.
	wanted, readable := wanted_of(e, id)
	defer if readable do destroy_wanted(&wanted)
	track := &e.library.tracks[id]
	lib.destroy_tags(&track.metadata.tags)
	track.metadata = written.metadata
	track.size = written.size
	track.modified = written.modified
	track.error = .None
	delete(written.path)
	e.saved[id] = {}
	// The file now holds the cover that was sent: wanting it is wanting the file's
	// own, else the track would wait to be saved again. A cover replaced again
	// meanwhile differs from the one sent, and stays pending.
	if held, has := &wanted.tags.cover.(lib.Cover);
	   readable && has && lib.cover_key(wanted.tags.cover) == sent {
		lib.destroy_cover(held)
		wanted.tags.cover = track.metadata.tags.cover
	}
	if readable do want(e, id, wanted)
}
