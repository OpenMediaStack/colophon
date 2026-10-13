package engine

import "core:path/filepath"
import "core:slice"
import "core:strings"

import lib "../library"

// What looks wrong in a track's tags beside the other tracks of its album: those of
// the same folder with the same album title.
Warning :: enum u8 {
	// The track has no number, while other tracks of its album have one.
	Missing_Number,
	// Its album artist is not the one most tracks of its album have.
	Odd_Album_Artist,
}

// What looks wrong in one track.
Warnings :: bit_set[Warning]

// The tracks whose tags look wrong beside the rest of their album, with what does,
// from the tags they show. Allocated with allocator. It walks the whole library: call
// it once after each change, not every frame.
warnings :: proc(e: ^Engine, allocator := context.allocator) -> map[Track_Id]Warnings {
	entries := make([dynamic]Album_Entry, context.temp_allocator)
	for track, i in e.library.tracks {
		id := Track_Id(i)
		tags := shown_tags(e, id) or_continue
		album := tags.album.? or_continue
		append(&entries, Album_Entry{filepath.dir(track.path), album, id, tags})
	}
	// The tracks of an album follow each other, in library order.
	slice.sort_by_cmp(entries[:], proc(a, b: Album_Entry) -> slice.Ordering {
		if order := slice.Ordering(strings.compare(a.folder, b.folder)); order != .Equal do return order
		if order := slice.Ordering(strings.compare(a.album, b.album)); order != .Equal do return order
		return slice.cmp(a.track, b.track)
	})
	found := make(map[Track_Id]Warnings, allocator)
	for start := 0; start < len(entries); {
		end := start + 1
		for end < len(entries) &&
		    entries[end].folder == entries[start].folder &&
		    entries[end].album == entries[start].album {
			end += 1
		}
		if end - start > 1 do warn_album(entries[start:end], &found)
		start = end
	}
	return found
}

// A track of an album, by the folder and the album title that make the album.
@(private = "file")
Album_Entry :: struct {
	folder, album: string,
	track:         Track_Id,
	tags:          ^lib.Tags,
}

// Adds the warnings of the tracks of one album to found.
@(private = "file")
warn_album :: proc(album: []Album_Entry, found: ^map[Track_Id]Warnings) {
	numbered := false
	artists := make([]Maybe(string), len(album), context.temp_allocator)
	for entry, i in album {
		if entry.tags.track != nil do numbered = true
		artists[i] = entry.tags.album_artist
	}
	usual, has_usual := most_common(artists)
	for entry in album {
		w: Warnings
		if numbered && entry.tags.track == nil do w += {.Missing_Number}
		if has_usual && entry.tags.album_artist != usual do w += {.Odd_Album_Artist}
		if w != {} do found[entry.track] = w
	}
}

// The value that comes up most often, unless another comes up as often. Sorts values.
@(private = "file")
most_common :: proc(values: []Maybe(string)) -> (top: Maybe(string), ok: bool) {
	slice.sort_by(values, proc(a, b: Maybe(string)) -> bool {
		x, has_x := a.?
		y, has_y := b.?
		if has_x != has_y do return !has_x
		return x < y
	})
	most, tied := 0, false
	for start := 0; start < len(values); {
		end := start + 1
		for end < len(values) && values[end] == values[start] do end += 1
		count := end - start
		if count > most {
			most, tied, top = count, false, values[start]
		} else if count == most {
			tied = true
		}
		start = end
	}
	return top, most > 0 && !tied
}
