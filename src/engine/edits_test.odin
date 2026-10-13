package engine

import "core:fmt"
import "core:strings"
import "core:testing"

import lib "../library"

// An engine whose library holds tracks titled titles, read from files that hold an
// ID3v2.3 tag when in_id3v2_3. A title "broken" gives an unreadable track.
@(private = "file")
engine_of :: proc(e: ^Engine, titles: []string, in_id3v2_3 := false) {
	init(e)
	for title in titles {
		track := lib.Track {
			path = strings.clone(fmt.tprintf("/music/%s.mp3", title)),
		}
		if title == "broken" {
			track.error = .Damaged
		} else {
			track.metadata.tags.title = strings.clone(title)
			if in_id3v2_3 do track.metadata.formats.id3v2 = .V2_3
		}
		append(&e.library.tracks, track)
	}
}

@(private = "file")
title_of :: proc(e: ^Engine, track: Track_Id) -> string {
	tags, ok := shown_tags(e, track)
	if !ok do return "?"
	return tags.title.? or_else ""
}

@(private = "file")
renamed :: proc(title: string) -> Edit {
	return {.Title, title}
}

@(private = "file")
set_title :: proc(e: ^Engine, tracks: []Track_Id, title: string, continues := false) {
	edit_tracks(e, tracks, renamed(title), continues)
}

@(test)
an_edit_changes_every_selected_track :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a", "b", "c"})
	defer destroy(&e)
	set_title(&e, {0, 2}, "New")
	testing.expect_value(t, title_of(&e, 0), "New")
	testing.expect_value(t, title_of(&e, 1), "b")
	testing.expect_value(t, title_of(&e, 2), "New")
	testing.expect_value(t, len(e.edits.pending), 2)
}

@(test)
a_total_goes_with_its_number :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	edit_tracks(&e, {0}, {.Track, 3}, false)
	edit_tracks(&e, {0}, {.Track_Total, 12}, false)
	edit_tracks(&e, {0}, {.Track, nil}, false)
	tags, _ := shown_tags(&e, 0)
	testing.expect_value(t, tags.track, nil)
	testing.expect_value(t, tags.track_total, nil)
}

@(test)
empty_text_empties_the_field :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "")
	tags, _ := shown_tags(&e, 0)
	testing.expect_value(t, tags.title, nil)
}

@(test)
going_back_to_the_files_value_is_no_change :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "New")
	set_title(&e, {0}, "a")
	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect(t, can_undo(&e))
}

@(test)
an_edit_that_changes_nothing_stays_out_of_the_history :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "a")
	testing.expect(t, !can_undo(&e))
}

@(test)
undo_and_redo_walk_the_history :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "One")
	set_title(&e, {0}, "Two")
	undo_step(&e)
	testing.expect_value(t, title_of(&e, 0), "One")
	undo_step(&e)
	testing.expect_value(t, title_of(&e, 0), "a")
	testing.expect_value(t, len(e.edits.pending), 0)
	redo_step(&e)
	testing.expect_value(t, title_of(&e, 0), "One")
}

@(test)
a_new_edit_forgets_what_could_be_redone :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "One")
	undo_step(&e)
	set_title(&e, {0}, "Two")
	testing.expect(t, !can_redo(&e))
}

@(test)
revert_brings_back_the_files_tags_and_can_be_undone :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a", "b"})
	defer destroy(&e)
	set_title(&e, {0, 1}, "New")
	revert_tracks(&e, {0})
	testing.expect_value(t, title_of(&e, 0), "a")
	testing.expect_value(t, len(e.edits.pending), 1)
	undo_step(&e)
	testing.expect_value(t, title_of(&e, 0), "New")
}

@(test)
unreadable_tracks_are_left_out :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a", "broken"})
	defer destroy(&e)
	set_title(&e, {0, 1}, "New")
	testing.expect_value(t, len(e.edits.pending), 1)
	_, pending := pending_tags(&e, 1)
	testing.expect(t, !pending)
}

@(test)
typing_goes_on_with_the_same_step :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "N")
	set_title(&e, {0}, "Ne", continues = true)
	set_title(&e, {0}, "New", continues = true)
	testing.expect_value(t, title_of(&e, 0), "New")
	undo_step(&e)
	testing.expect_value(t, title_of(&e, 0), "a")
	testing.expect(t, !can_undo(&e))
}

@(test)
typing_back_the_old_value_leaves_no_step :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "New")
	set_title(&e, {0}, "a", continues = true)
	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect(t, !can_undo(&e))
}

@(test)
another_field_starts_a_new_step :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "New")
	edit_tracks(&e, {0}, {.Year, 2024}, true)
	undo_step(&e)
	testing.expect_value(t, title_of(&e, 0), "New")
}

@(test)
a_version_that_changes_the_file_waits_to_be_saved :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"}, in_id3v2_3 = true)
	defer destroy(&e)
	choose_versions(&e, {0}, Id3v2_Choice{.V2_4})
	testing.expect_value(t, len(e.edits.pending), 1)
	versions, _ := versions_of(&e, 0)
	testing.expect_value(t, versions.id3v2, Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_4))
	undo_step(&e)
	testing.expect_value(t, len(e.edits.pending), 0)
}

@(test)
the_version_a_file_has_changes_nothing_but_is_kept_for_the_next_save :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"}, in_id3v2_3 = true)
	defer destroy(&e)
	choose_versions(&e, {0}, Id3v2_Choice{.V2_3})
	testing.expect_value(t, len(e.edits.pending), 0)
	set_title(&e, {0}, "New")
	versions, _ := versions_of(&e, 0)
	testing.expect_value(t, versions.id3v2, Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_3))
}

@(test)
a_chosen_version_outlives_the_save_that_wrote_it :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"}, in_id3v2_3 = true)
	defer destroy(&e)
	choose_versions(&e, {0}, Id3v2_Choice{.V2_2})
	e.library.tracks[0].metadata.formats.id3v2 = .V2_2
	settle(&e, 0)
	testing.expect_value(t, len(e.edits.pending), 0)
	versions, _ := versions_of(&e, 0)
	testing.expect_value(t, versions.id3v2, Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_2))
}

@(test)
revert_drops_the_chosen_versions :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"}, in_id3v2_3 = true)
	defer destroy(&e)
	choose_versions(&e, {0}, Id3v1_Choice{.V1_1})
	revert_tracks(&e, {0})
	testing.expect_value(t, len(e.edits.pending), 0)
	versions, _ := versions_of(&e, 0)
	testing.expect_value(t, versions, lib.Tag_Versions{id3v2 = .V2_4, id3v1 = nil})
}

@(test)
modified_fields_are_those_that_differ_from_the_file :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a", "b"})
	defer destroy(&e)
	set_title(&e, {0}, "New")
	edit_tracks(&e, {1}, {.Year, 2024}, false)
	testing.expect_value(t, modified_fields(&e, {0}), Fields{.Title})
	testing.expect_value(t, modified_fields(&e, {0, 1}), Fields{.Title, .Year})
}

@(test)
numbering_counts_disc_by_disc :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a", "b", "c"})
	defer destroy(&e)
	edit_tracks(&e, {2}, {.Disc, 2}, false)
	number_tracks(&e, {2, 0, 1})
	tags, _ := shown_tags(&e, 0)
	testing.expect_value(t, tags.track, 1)
	testing.expect_value(t, tags.track_total, 2)
	tags, _ = shown_tags(&e, 2)
	testing.expect_value(t, tags.track, 1)
	testing.expect_value(t, tags.track_total, 1)
}

@(test)
typed_text_makes_the_edit_of_its_field :: proc(t: ^testing.T) {
	Case :: struct {
		field: Field,
		text:  string,
		edit:  Maybe(Edit),
	}
	cases := [?]Case {
		{.Title, "New", Edit{.Title, "New"}},
		{.Title, "", Edit{.Title, nil}},
		{.Track, " 7 ", Edit{.Track, 7}},
		{.Track, "", Edit{.Track, nil}},
		{.Track, "0", nil},
		{.Track, "7a", nil},
		{.Track, "-3", nil},
		{.Year, "2024", Edit{.Year, 2024}},
		{.Year, "10000", nil},
	}
	for c in cases {
		edit, ok := parse_edit(c.field, c.text)
		want, valid := c.edit.?
		testing.expectf(t, ok == valid, "%v %q: %v", c.field, c.text, ok)
		if ok && valid do testing.expectf(t, edit == want, "%v %q: %v", c.field, c.text, edit)
	}
}

@(test)
an_edit_whose_value_does_not_fit_changes_nothing :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	edit_tracks(&e, {0}, {.Title, 5}, false)
	edit_tracks(&e, {0}, {.Year, "2024"}, false)
	edit_tracks(&e, {0}, {.Track, -3}, false)
	edit_tracks(&e, {0}, {.Year, 0}, false)
	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect(t, !can_undo(&e))
}

@(test)
no_version_choice_changes_nothing :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	choose_versions(&e, {0}, nil)
	testing.expect(t, !can_undo(&e))
	testing.expect_value(t, len(e.edits.chosen), 0)
}

@(test)
a_track_whose_file_cannot_be_read_takes_no_change :: proc(t: ^testing.T) {
	e: Engine
	engine_of(&e, {"a"})
	defer destroy(&e)
	set_title(&e, {0}, "New")
	e.library.tracks[0].error = .Damaged
	revert_tracks(&e, {0})
	choose_versions(&e, {0}, Id3v1_Choice{.V1_1})
	set_title(&e, {0}, "Newer")
	testing.expect_value(t, len(e.edits.undo), 1)
}
