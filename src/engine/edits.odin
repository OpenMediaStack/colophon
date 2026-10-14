package engine

import "base:runtime"
import "core:slice"
import "core:strconv"
import "core:strings"

import lib "../library"

// A field of the inspector, which an edit changes.
Field :: enum u8 {
	Title,
	Artist,
	Album_Artist,
	Album,
	Year,
	Track,
	Track_Total,
	Disc,
	Disc_Total,
	Genre,
	Comment,
}

// Several fields, such as those with values waiting to be saved.
Fields :: bit_set[Field]

// A new value for one field: text for text fields, a number for number fields; nil,
// or empty text, empties the field.
Edit :: struct {
	field: Field,
	value: Edit_Value,
}

// The value of an edit: text for the text fields, a number from 1 for the number
// fields, a year from 1 to 9999. An edit whose value does not fit its field changes
// nothing.
Edit_Value :: union {
	string,
	int,
}

// A choice of the version to write one tag of the selected tracks in; nil removes
// the tag.
Version_Choice :: union {
	Id3v2_Choice,
	Id3v1_Choice,
}

// The ID3v2 version to write, or nil to remove the ID3v2 tag.
Id3v2_Choice :: struct {
	version: Maybe(lib.Id3v2_Version),
}

// The ID3v1 version to write, or nil to remove the ID3v1 tag.
Id3v1_Choice :: struct {
	version: Maybe(lib.Id3v1_Version),
}

// A new value for one field of every selected track.
Apply_Edit :: struct {
	edit: Edit,
}

// The same, typed on: it goes on with the latest step of the history when that step
// edited the same field of the same tracks.
Continue_Edit :: struct {
	edit: Edit,
}

// A new value for one field of these tracks rather than the selected ones: the tracks
// a cell's editor opened on, which it edits even once a scan has moved their rows or
// the selection has changed. When continues, the edit goes on with the latest step of
// the history, as Continue_Edit does. The engine copies the list.
Edit_Tracks :: struct {
	tracks:    []Track_Id,
	edit:      Edit,
	continues: bool,
}

Undo :: struct {}
Redo :: struct {}

// Brings the selected tracks back to their files' tags.
Revert :: struct {}

// Numbers the selected tracks in the table's order, from 1 on each disc.
Number_Tracks :: struct {}

// Every listed track of the albums of the selected tracks joins the selection.
Select_Album :: struct {}

// The version to write one tag of the selected tracks in, or none to remove it.
Choose_Version :: struct {
	choice: Version_Choice,
}

// What the user wants for each track, and the history of how they got there. The
// history holds values rather than "modified or not", so that undoing an edit already
// saved brings the old values back as a change to save.
Edits :: struct {
	// The tracks saving would change, with the tags to write into them.
	pending: map[Track_Id]lib.Tags,
	// The tag versions the user chose, kept once saved so that the next save writes
	// them again.
	chosen:  map[Track_Id]lib.Tag_Versions,
	// The versions to write the other tracks in.
	policy:  lib.Write_Policy,
	undo:    [dynamic]Action,
	redo:    [dynamic]Action,
}

// What the user wants for a track: its tags, and the tag versions to write them in
// if the user chose some rather than Colophon's.
@(private)
Wanted :: struct {
	tags:     lib.Tags,
	versions: Maybe(lib.Tag_Versions),
}

// One step of the history: what the user wanted for each track it changed, before
// and after, and the field it edited, if it came from an edit.
@(private)
Action :: struct {
	field:   Maybe(Field),
	changes: [dynamic]Change,
}

@(private)
Change :: struct {
	track:         Track_Id,
	before, after: Wanted,
}

@(private)
edits_init :: proc(edits: ^Edits, allocator: runtime.Allocator) {
	edits.pending = make(map[Track_Id]lib.Tags, allocator)
	edits.chosen = make(map[Track_Id]lib.Tag_Versions, allocator)
	edits.policy = lib.DEFAULT_WRITE_POLICY
	edits.undo = make([dynamic]Action, allocator)
	edits.redo = make([dynamic]Action, allocator)
}

@(private)
edits_destroy :: proc(edits: ^Edits) {
	for _, &tags in edits.pending do lib.destroy_tags(&tags)
	delete(edits.pending)
	delete(edits.chosen)
	for &action in edits.undo do destroy_action(&action)
	delete(edits.undo)
	for &action in edits.redo do destroy_action(&action)
	delete(edits.redo)
	edits^ = {}
}

// The tags to write into a track, if saving would change its file. The pointer is
// valid until the edits change.
pending_tags :: proc(e: ^Engine, track: Track_Id) -> (^lib.Tags, bool) {
	return &e.edits.pending[track]
}

// The tag versions to write a track in: those the user chose, or else the policy's;
// false for a track whose file could not be read.
versions_of :: proc(e: ^Engine, track: Track_Id) -> (versions: lib.Tag_Versions, ok: bool) {
	saved := saved_metadata(e, track) or_return
	if chosen, found := e.edits.chosen[track]; found do return chosen, true
	return lib.versions_following(e.edits.policy, saved.formats), true
}

// Whether there is a step to undo.
can_undo :: proc(e: ^Engine) -> bool {
	return len(e.edits.undo) > 0
}

// Whether there is an undone step to redo.
can_redo :: proc(e: ^Engine) -> bool {
	return len(e.edits.redo) > 0
}

// The fields of these tracks whose values differ from their files'.
modified_fields :: proc(e: ^Engine, tracks: []Track_Id) -> (fields: Fields) {
	for track in tracks {
		wanted := pending_tags(e, track) or_continue
		saved := saved_metadata(e, track) or_continue
		for field in Field do if differs(field, wanted, &saved.tags) do fields += {field}
	}
	return
}

// Whether two sets of tags hold different values for field.
differs :: proc(field: Field, a, b: ^lib.Tags) -> bool {
	switch field {
	case .Title:
		return a.title != b.title
	case .Artist:
		return a.artist != b.artist
	case .Album_Artist:
		return a.album_artist != b.album_artist
	case .Album:
		return a.album != b.album
	case .Year:
		return a.year != b.year
	case .Track:
		return a.track != b.track
	case .Track_Total:
		return a.track_total != b.track_total
	case .Disc:
		return a.disc != b.disc
	case .Disc_Total:
		return a.disc_total != b.disc_total
	case .Genre:
		return a.genre != b.genre
	case .Comment:
		return a.comment != b.comment
	}
	return false
}

// The edit that text typed in field makes: trimmed digits for a number, nothing to
// empty the field. false when the text is no value of the field: not a number, 0, or a
// year outside 1 to 9999.
parse_edit :: proc(field: Field, text: string) -> (edit: Edit, ok: bool) {
	edit.field = field
	switch field {
	case .Title, .Artist, .Album_Artist, .Album, .Genre, .Comment:
		if len(text) > 0 do edit.value = text
		return edit, true
	case .Year, .Track, .Track_Total, .Disc, .Disc_Total:
		digits := strings.trim_space(text)
		if len(digits) == 0 do return edit, true
		for c in digits do if c < '0' || c > '9' do return
		n := strconv.parse_int(digits, 10) or_return
		edit.value = n
		return edit, fits(edit)
	}
	return
}

// Whether the value of edit fits its field, as described for Edit_Value.
@(private)
fits :: proc(edit: Edit) -> bool {
	switch v in edit.value {
	case nil:
		return true
	case string:
		return edit.field in TEXT_FIELDS
	case int:
		if edit.field == .Year do return v >= 1 && v <= 9999
		return edit.field not_in TEXT_FIELDS && v >= 1 && v <= int(max(u32))
	}
	return false
}

@(private = "file")
TEXT_FIELDS :: Fields{.Title, .Artist, .Album_Artist, .Album, .Genre, .Comment}

// Applies edit to each of these tracks whose tags could be read. When continues, the
// edit goes on with the latest step, if that step edited the same field of the same
// tracks: typing a word makes one step, and typing back the old value makes none.
@(private)
edit_tracks :: proc(e: ^Engine, tracks: []Track_Id, edit: Edit, continues: bool) {
	if !fits(edit) do return
	changes := make([dynamic]Change)
	for track in tracks {
		change := begin_change(e, track) or_continue
		apply_edit(&change.after.tags, edit)
		append(&changes, change)
	}
	if continues && continue_last(e, edit.field, &changes) do return
	record(e, edit.field, &changes)
}

// Numbers these tracks in this order from 1, disc by disc, each with the number of
// tracks of its disc as the total. A track without a disc number counts as on the
// first disc.
@(private)
number_tracks :: proc(e: ^Engine, ordered: []Track_Id) {
	Placed :: struct {
		track: Track_Id,
		disc:  int,
	}
	placed := make([dynamic]Placed, context.temp_allocator)
	for track in ordered {
		tags := shown_tags(e, track) or_continue
		append(&placed, Placed{track, tags.disc.? or_else 1})
	}
	slice.stable_sort_by(placed[:], proc(a, b: Placed) -> bool {return a.disc < b.disc})
	changes := make([dynamic]Change)
	for i := 0; i < len(placed); {
		end := i
		for end < len(placed) && placed[end].disc == placed[i].disc do end += 1
		for p, number in placed[i:end] {
			change := begin_change(e, p.track) or_continue
			change.after.tags.track = number + 1
			change.after.tags.track_total = end - i
			append(&changes, change)
		}
		i = end
	}
	record(e, nil, &changes)
}

// Writes these tracks in the version chosen for one tag, the other tag keeping its own.
@(private)
choose_versions :: proc(e: ^Engine, tracks: []Track_Id, choice: Version_Choice) {
	if choice == nil do return
	changes := make([dynamic]Change)
	for track in tracks {
		change := begin_change(e, track) or_continue
		versions := versions_of(e, track) or_continue
		switch c in choice {
		case Id3v2_Choice:
			versions.id3v2 = c.version
		case Id3v1_Choice:
			versions.id3v1 = c.version
		}
		change.after.versions = versions
		append(&changes, change)
	}
	record(e, nil, &changes)
}

// Brings these tracks back to their files' tags, written in Colophon's versions.
@(private)
revert_tracks :: proc(e: ^Engine, tracks: []Track_Id) {
	changes := make([dynamic]Change)
	for track in tracks {
		change := begin_change(e, track) or_continue
		saved := saved_metadata(e, track) or_continue
		lib.destroy_tags(&change.after.tags)
		change.after.tags = lib.clone_tags(saved.tags)
		change.after.versions = nil
		append(&changes, change)
	}
	record(e, nil, &changes)
}

@(private)
undo_step :: proc(e: ^Engine) {
	action, ok := pop_safe(&e.edits.undo)
	if !ok do return
	for change in action.changes do want(e, change.track, change.before)
	append(&e.edits.redo, action)
}

@(private)
redo_step :: proc(e: ^Engine) {
	action, ok := pop_safe(&e.edits.redo)
	if !ok do return
	for change in action.changes do want(e, change.track, change.after)
	append(&e.edits.undo, action)
}

// Forgets a track's pending tags once its file holds them, after a save.
@(private)
settle :: proc(e: ^Engine, track: Track_Id) {
	wanted, ok := wanted_of(e, track)
	if !ok do return
	defer destroy_wanted(&wanted)
	want(e, track, wanted)
}

// What the user wants for a track: the pending tags, or else its file's, and the
// versions they chose, cloned.
@(private)
wanted_of :: proc(e: ^Engine, track: Track_Id) -> (wanted: Wanted, ok: bool) {
	// A track whose file cannot be read takes no change, pending tags or not.
	saved_metadata(e, track) or_return
	tags := shown_tags(e, track) or_return
	wanted.tags = lib.clone_tags(tags^)
	if versions, chosen := e.edits.chosen[track]; chosen do wanted.versions = versions
	return wanted, true
}

// What a track's file holds, if it could be read.
@(private)
saved_metadata :: proc(e: ^Engine, track: Track_Id) -> (^lib.Metadata, bool) {
	if track < 0 || int(track) >= len(e.library.tracks) do return nil, false
	t := &e.library.tracks[track]
	if t.error != .None do return nil, false
	return &t.metadata, true
}

// A change of track whose after starts as its before: what the user wants now.
@(private = "file")
begin_change :: proc(e: ^Engine, track: Track_Id) -> (change: Change, ok: bool) {
	change.before = wanted_of(e, track) or_return
	change.after = clone_wanted(change.before)
	change.track = track
	return change, true
}

// Applies an edit's value to tags. A file holds a total only with its number, both in
// one frame.
@(private = "file")
apply_edit :: proc(tags: ^lib.Tags, edit: Edit) {
	text :: proc(slot: ^Maybe(string), value: Edit_Value) {
		if old, ok := slot.?; ok do delete(old)
		slot^ = nil
		if s, ok := value.(string); ok && len(s) > 0 do slot^ = strings.clone(s)
	}
	number :: proc(slot: ^Maybe(int), value: Edit_Value) {
		n, ok := value.(int)
		slot^ = ok ? n : nil
	}
	switch edit.field {
	case .Title:
		text(&tags.title, edit.value)
	case .Artist:
		text(&tags.artist, edit.value)
	case .Album_Artist:
		text(&tags.album_artist, edit.value)
	case .Album:
		text(&tags.album, edit.value)
	case .Genre:
		text(&tags.genre, edit.value)
	case .Comment:
		text(&tags.comment, edit.value)
	case .Year:
		number(&tags.year, edit.value)
	case .Track:
		number(&tags.track, edit.value)
	case .Track_Total:
		number(&tags.track_total, edit.value)
	case .Disc:
		number(&tags.disc, edit.value)
	case .Disc_Total:
		number(&tags.disc_total, edit.value)
	}
	if tags.track == nil do tags.track_total = nil
	if tags.disc == nil do tags.disc_total = nil
}

// Folds changes into the latest step, if it edited field of the same tracks. Takes
// ownership of changes either way when it returns true.
@(private = "file")
continue_last :: proc(e: ^Engine, field: Field, changes: ^[dynamic]Change) -> bool {
	if len(e.edits.undo) == 0 do return false
	last := &e.edits.undo[len(e.edits.undo) - 1]
	last_field, edited := last.field.?
	if !edited || last_field != field || len(last.changes) != len(changes) do return false
	for c, i in changes do if last.changes[i].track != c.track do return false
	undone := true
	for &c, i in changes {
		destroy_wanted(&last.changes[i].after)
		last.changes[i].after = c.after
		c.after = {}
		if !same_wanted(last.changes[i].before, last.changes[i].after) do undone = false
	}
	for &c in changes do destroy_change(&c)
	delete(changes^)
	for c in last.changes do want(e, c.track, c.after)
	if undone {
		action := pop(&e.edits.undo)
		destroy_action(&action)
	}
	clear_redo(e)
	return true
}

// Takes in changes that do change something as the latest step of the history.
// Takes ownership of changes.
@(private = "file")
record :: proc(e: ^Engine, field: Maybe(Field), changes: ^[dynamic]Change) {
	kept := 0
	for &c in changes {
		if same_wanted(c.before, c.after) {
			destroy_change(&c)
			continue
		}
		changes[kept] = c
		kept += 1
	}
	resize(changes, kept)
	if len(changes) == 0 {
		delete(changes^)
		return
	}
	for c in changes do want(e, c.track, c.after)
	append(&e.edits.undo, Action{field, changes^})
	clear_redo(e)
}

// Takes wanted in for a track: it waits to be saved if saving would change the file,
// with other tags or in other versions. wanted is copied.
@(private)
want :: proc(e: ^Engine, track: Track_Id, wanted: Wanted) {
	if versions, chosen := wanted.versions.?; chosen {
		e.edits.chosen[track] = versions
	} else {
		delete_key(&e.edits.chosen, track)
	}
	saved, readable := saved_metadata(e, track)
	if !readable do return
	wanted := wanted
	rewritten := false
	if versions, chosen := wanted.versions.?; chosen {
		rewritten = lib.formats_after_write(saved.formats, &wanted.tags, versions) != saved.formats
	}
	if old, pending := &e.edits.pending[track]; pending do lib.destroy_tags(old)
	if wanted.tags != saved.tags || rewritten {
		e.edits.pending[track] = lib.clone_tags(wanted.tags)
	} else {
		delete_key(&e.edits.pending, track)
	}
}

@(private = "file")
clear_redo :: proc(e: ^Engine) {
	for &action in e.edits.redo do destroy_action(&action)
	clear(&e.edits.redo)
}

@(private = "file")
same_wanted :: proc(a, b: Wanted) -> bool {
	return a.tags == b.tags && a.versions == b.versions
}

@(private = "file")
clone_wanted :: proc(w: Wanted) -> Wanted {
	return {lib.clone_tags(w.tags), w.versions}
}

@(private)
destroy_wanted :: proc(w: ^Wanted) {
	lib.destroy_tags(&w.tags)
}

@(private = "file")
destroy_change :: proc(c: ^Change) {
	destroy_wanted(&c.before)
	destroy_wanted(&c.after)
}

@(private = "file")
destroy_action :: proc(action: ^Action) {
	for &c in action.changes do destroy_change(&c)
	delete(action.changes)
}
