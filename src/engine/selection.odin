package engine

import "core:slice"

// The selected tracks, in library order.
Selection :: struct {
	tracks: [dynamic]Track_Id,
	// Where a Shift click or a Shift arrow extends the selection from.
	anchor: Maybe(Track_Id),
	// The track the arrow keys move from, outlined in the table.
	focus:  Maybe(Track_Id),
}

// A move of the arrow keys.
Step :: enum u8 {
	Up,
	Down,
}

// A click on a track: it alone becomes the selection.
Select :: struct {
	track: Track_Id,
}

// A Command click: the track joins the selection or leaves it.
Toggle_Selected :: struct {
	track: Track_Id,
}

// A Shift click: the tracks from the last one clicked to this one become the selection.
Select_Range :: struct {
	track: Track_Id,
}

// Every track the table lists becomes the selection.
Select_All :: struct {}

// An arrow key: the selection moves to the previous or next track.
Move_Selection :: struct {
	step: Step,
}

// A Shift arrow: the selection grows or shrinks by one track.
Extend_Selection :: struct {
	step: Step,
}

// Whether the track is selected. It searches tracks, which only the engine changes,
// keeping them sorted and each once.
is_selected :: proc(s: ^Selection, track: Track_Id) -> bool {
	_, found := slice.binary_search(s.tracks[:], track)
	return found
}

@(private)
destroy_selection :: proc(s: ^Selection) {
	delete(s.tracks)
	s^ = {}
}

// The track alone.
@(private)
select_one :: proc(s: ^Selection, track: Track_Id) {
	clear(&s.tracks)
	append(&s.tracks, track)
	s.anchor = track
	s.focus = track
}

// The track joins the selection or leaves it.
@(private)
toggle_selected :: proc(s: ^Selection, track: Track_Id) {
	if at, found := slice.binary_search(s.tracks[:], track); found {
		ordered_remove(&s.tracks, at)
	} else {
		inject_at(&s.tracks, at, track)
	}
	s.anchor = track
	s.focus = track
}

// Every track of order, the tracks as the table lists them, from the anchor to this
// one, and nothing else. An anchor the table no longer lists starts from this track.
@(private)
select_range :: proc(s: ^Selection, track: Track_Id, order: []Track_Id) {
	to, listed := slice.linear_search(order, track)
	if !listed {
		select_one(s, track)
		return
	}
	from := to
	if anchor, ok := s.anchor.?; ok {
		if at, anchor_listed := slice.linear_search(order, anchor); anchor_listed do from = at
	}
	set_tracks(s, order[min(from, to):max(from, to) + 1])
	if from == to do s.anchor = track
	s.focus = track
}

// These tracks join the selection.
@(private)
add_to_selection :: proc(s: ^Selection, tracks: []Track_Id) {
	for track in tracks {
		if at, found := slice.binary_search(s.tracks[:], track); !found do inject_at(&s.tracks, at, track)
	}
}

// Every track the table lists, the focus kept.
@(private)
select_all :: proc(s: ^Selection, order: []Track_Id) {
	set_tracks(s, order)
}

// An arrow key: the selection moves to the track stepped to.
@(private)
move_selection :: proc(s: ^Selection, direction: Step, order: []Track_Id) {
	if track, ok := stepped(s, direction, order); ok do select_one(s, track)
}

// A Shift arrow: the selection grows or shrinks from the anchor to the track stepped to.
@(private)
extend_selection :: proc(s: ^Selection, direction: Step, order: []Track_Id) {
	if track, ok := stepped(s, direction, order); ok do select_range(s, track, order)
}

// The track an arrow key goes to in order, the tracks as the table lists them: the
// previous or next one from the focus, stopping at the ends, else the first or the
// last. False when order is empty.
@(private = "file")
stepped :: proc(s: ^Selection, direction: Step, order: []Track_Id) -> (track: Track_Id, ok: bool) {
	if len(order) == 0 do return
	last := len(order) - 1
	place := -1
	if focus, has_focus := s.focus.?; has_focus {
		if at, listed := slice.linear_search(order, focus); listed do place = at
	}
	switch {
	case place < 0 && direction == .Down:
		place = 0
	case place < 0:
		place = last
	case direction == .Up:
		place = max(place - 1, 0)
	case:
		place = min(place + 1, last)
	}
	return order[place], true
}

@(private = "file")
set_tracks :: proc(s: ^Selection, tracks: []Track_Id) {
	clear(&s.tracks)
	append(&s.tracks, ..tracks)
	slice.sort(s.tracks[:])
}
