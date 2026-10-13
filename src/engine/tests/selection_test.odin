package engine_tests

import "core:fmt"
import "core:testing"

import "../../engine"

@(private = "file")
engine_with :: proc(t: ^testing.T, e: ^engine.Engine, files: []string) -> (folder: string) {
	folder = folder_with(t, files)
	engine_reading(t, e, folder)
	return
}

@(private = "file")
expect_selected :: proc(
	t: ^testing.T,
	e: ^engine.Engine,
	want: []engine.Track_Id,
	loc := #caller_location,
) {
	got := e.selection.tracks[:]
	if !testing.expectf(t, len(got) == len(want), "selected %v, want %v", got, want, loc = loc) do return
	for track, i in got do testing.expectf(t, track == want[i], "selected %v, want %v", got, want, loc = loc)
}

@(test)
nothing_is_selected_at_first :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := engine_with(t, &e, {"a.mp3", "b.mp3"})
	defer remove_folder(folder)
	defer engine.destroy(&e)
	testing.expect_value(t, len(e.selection.tracks), 0)
}

@(test)
clicks_and_keys_change_the_selection :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := engine_with(t, &e, {"a.mp3", "b.mp3", "c.mp3", "d.mp3"})
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{1})
	engine.execute(&e, engine.Toggle_Selected{3})
	expect_selected(t, &e, {1, 3})
	engine.execute(&e, engine.Select_Range{0})
	expect_selected(t, &e, {0, 1, 2, 3})
	engine.execute(&e, engine.Move_Selection{.Down})
	engine.execute(&e, engine.Extend_Selection{.Down})
	expect_selected(t, &e, {1, 2})
	engine.execute(&e, engine.Select_All{})
	expect_selected(t, &e, {0, 1, 2, 3})
}

@(test)
a_track_that_does_not_exist_cannot_be_selected :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := engine_with(t, &e, {"a.mp3", "b.mp3"})
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{2})
	engine.execute(&e, engine.Toggle_Selected{7})
	engine.execute(&e, engine.Select_Range{9})
	engine.execute(&e, engine.Select{-1})
	testing.expect_value(t, len(e.selection.tracks), 0)
}

@(test)
opening_another_folder_keeps_the_selection :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := engine_with(t, &e, {"a.mp3", "b.mp3"})
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	other := folder_with(t, {"c.mp3"})
	defer remove_folder(other)
	engine.execute(&e, engine.Open_Folder{other})
	testing.expect_value(t, len(e.selection.tracks), 2)
	poll_until_done(t, &e)
	testing.expect_value(t, len(e.selection.tracks), 2)
}

@(test)
select_all_and_the_arrows_follow_the_table :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Sort_By{.Title})
	engine.execute(&e, engine.Filter{".mp3"})
	engine.execute(&e, engine.Move_Selection{.Down})
	expect_selected(t, &e, {3})
	engine.execute(&e, engine.Filter{"a/"})
	engine.execute(&e, engine.Select_All{})
	testing.expect_value(t, len(e.selection.tracks), len(e.listed))
}

@(test)
selection_commands_keep_the_ids_of_1_0 :: proc(t: ^testing.T) {
	ids := [?][2]string {
		{engine.command_id(engine.Select{}), "selection.select"},
		{engine.command_id(engine.Toggle_Selected{}), "selection.toggle"},
		{engine.command_id(engine.Select_Range{}), "selection.select_range"},
		{engine.command_id(engine.Select_All{}), "selection.select_all"},
		{engine.command_id(engine.Move_Selection{}), "selection.move"},
		{engine.command_id(engine.Extend_Selection{}), "selection.extend"},
	}
	for id in ids do testing.expect_value(t, id[0], id[1])
}

@(test)
a_shift_click_whose_anchor_is_filtered_out_starts_from_the_click :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{0})
	engine.execute(&e, engine.Show_Source{engine.Folder{fmt.tprintf("%s/b", folder)}})
	engine.execute(&e, engine.Select_Range{3})
	expect_selected(t, &e, {3})
	testing.expect_value(t, e.selection.anchor, engine.Track_Id(3))
}

@(test)
a_shift_click_on_a_track_not_listed_selects_it_alone :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{2})
	engine.execute(&e, engine.Show_Source{engine.Folder{fmt.tprintf("%s/b", folder)}})
	engine.execute(&e, engine.Select_Range{0})
	expect_selected(t, &e, {0})
}

@(test)
arrows_whose_focus_is_filtered_out_start_from_an_end :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{0})
	engine.execute(&e, engine.Show_Source{engine.Folder{fmt.tprintf("%s/b", folder)}})
	engine.execute(&e, engine.Move_Selection{.Down})
	expect_selected(t, &e, {2})
	engine.execute(&e, engine.Select{0})
	engine.execute(&e, engine.Move_Selection{.Up})
	expect_selected(t, &e, {3})
}

@(test)
selecting_all_of_an_empty_table_keeps_the_anchor_and_focus :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := library(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{1})
	engine.execute(&e, engine.Filter{"nothing at all"})
	engine.execute(&e, engine.Select_All{})
	expect_selected(t, &e, {})
	testing.expect_value(t, e.selection.anchor, engine.Track_Id(1))
	testing.expect_value(t, e.selection.focus, engine.Track_Id(1))
}
