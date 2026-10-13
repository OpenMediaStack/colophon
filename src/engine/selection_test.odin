package engine

import "core:testing"

@(private = "file")
ORDER :: [10]Track_Id{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
@(private = "file")
FIVE :: [5]Track_Id{0, 1, 2, 3, 4}

@(private = "file")
expect_selected :: proc(t: ^testing.T, s: ^Selection, want: []Track_Id, loc := #caller_location) {
	if !testing.expectf(t, len(s.tracks) == len(want), "selected %v, want %v", s.tracks[:], want, loc = loc) do return
	for track, i in s.tracks do testing.expectf(t, track == want[i], "selected %v, want %v", s.tracks[:], want, loc = loc)
}

@(test)
a_click_selects_one_track :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	select_one(&s, 3)
	select_one(&s, 5)
	expect_selected(t, &s, {5})
	testing.expect_value(t, s.focus, Maybe(Track_Id)(5))
}

@(test)
a_command_click_adds_then_removes_a_track :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	select_one(&s, 1)
	toggle_selected(&s, 4)
	expect_selected(t, &s, {1, 4})
	toggle_selected(&s, 1)
	expect_selected(t, &s, {4})
}

@(test)
a_shift_click_selects_from_the_anchor_in_either_direction :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	order := ORDER
	select_one(&s, 5)
	select_range(&s, 8, order[:])
	expect_selected(t, &s, {5, 6, 7, 8})
	select_range(&s, 3, order[:])
	expect_selected(t, &s, {3, 4, 5})
	testing.expect_value(t, s.focus, Maybe(Track_Id)(3))
}

@(test)
a_shift_click_after_a_command_click_starts_from_that_track :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	order := ORDER
	select_one(&s, 1)
	toggle_selected(&s, 6)
	select_range(&s, 8, order[:])
	expect_selected(t, &s, {6, 7, 8})
}

@(test)
select_all_keeps_the_focus :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	select_one(&s, 2)
	select_all(&s, {0, 1, 2, 3})
	expect_selected(t, &s, {0, 1, 2, 3})
	testing.expect_value(t, s.focus, Maybe(Track_Id)(2))
}

@(test)
the_arrows_start_from_either_end :: proc(t: ^testing.T) {
	down, up: Selection
	defer destroy_selection(&down)
	defer destroy_selection(&up)
	five := FIVE
	move_selection(&down, .Down, five[:])
	move_selection(&up, .Up, five[:])
	expect_selected(t, &down, {0})
	expect_selected(t, &up, {4})
}

@(test)
the_arrows_move_the_selection_and_stop_at_the_ends :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	five := FIVE
	select_one(&s, 1)
	move_selection(&s, .Up, five[:])
	move_selection(&s, .Up, five[:])
	expect_selected(t, &s, {0})
	select_one(&s, 4)
	move_selection(&s, .Down, five[:])
	expect_selected(t, &s, {4})
}

@(test)
shift_arrows_grow_then_shrink_the_selection :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	five := FIVE
	select_one(&s, 2)
	extend_selection(&s, .Down, five[:])
	extend_selection(&s, .Down, five[:])
	expect_selected(t, &s, {2, 3, 4})
	extend_selection(&s, .Up, five[:])
	expect_selected(t, &s, {2, 3})
}

@(test)
a_range_and_the_arrows_follow_the_order_of_the_table :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	order := []Track_Id{4, 0, 3, 1}
	select_one(&s, 0)
	select_range(&s, 1, order)
	expect_selected(t, &s, {0, 1, 3})
	select_one(&s, 4)
	move_selection(&s, .Down, order)
	expect_selected(t, &s, {0})
}

@(test)
the_arrows_do_nothing_without_tracks :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	move_selection(&s, .Down, {})
	testing.expect_value(t, len(s.tracks), 0)
	testing.expect_value(t, s.focus, nil)
}

@(test)
added_tracks_keep_the_library_order :: proc(t: ^testing.T) {
	s: Selection
	defer destroy_selection(&s)
	select_one(&s, 5)
	add_to_selection(&s, {9, 1, 5})
	expect_selected(t, &s, {1, 5, 9})
	testing.expect(t, is_selected(&s, 9))
	testing.expect(t, !is_selected(&s, 2))
}
