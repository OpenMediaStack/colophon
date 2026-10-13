package ui

import "core:testing"

@(private = "file")
edit_of :: proc(text: string, caret: int) -> (e: Text_Edit) {
	text_edit_init(&e)
	edit_reset(&e, text, false)
	edit_move(&e, caret)
	return
}

@(test)
typing_replaces_the_selection_and_drops_line_breaks :: proc(t: ^testing.T) {
	e := edit_of("Paper Satellites", 6)
	defer text_edit_destroy(&e)
	edit_move(&e, 16, extend = true)
	edit_insert(&e, "Moons\nof Jupiter")
	testing.expect_value(t, edit_text(&e), "Paper Moonsof Jupiter")
	testing.expect_value(t, e.caret, len("Paper Moonsof Jupiter"))
	testing.expect(t, !has_selection(&e))
}

@(test)
words_move_as_each_platform_moves_them :: proc(t: ^testing.T) {
	s := "Neon Overpass, Été"
	testing.expect_value(t, word_right(s, 0, .Mac), 4)
	testing.expect_value(t, word_right(s, 0, .Windows), 5)
	testing.expect_value(t, word_right(s, 5, .Mac), 13)
	testing.expect_value(t, word_right(s, 5, .Linux), 15)
	testing.expect_value(t, word_left(s, len(s)), 15)
	testing.expect_value(t, word_left(s, 15), 5)
	testing.expect_value(t, word_left(s, 0), 0)
}

@(test)
keys_move_and_delete_as_each_platform_does :: proc(t: ^testing.T) {
	e := edit_of("Neon Overpass", 13)
	defer text_edit_destroy(&e)
	edit_key(&e, {.Backspace, {.Alt}, false}, {}, .Mac)
	testing.expect_value(t, edit_text(&e), "Neon ")
	edit_key(&e, {.Left, {.Super}, false}, {}, .Mac)
	testing.expect_value(t, e.caret, 0)
	edit_key(&e, {.Right, {.Control, .Shift}, false}, {}, .Windows)
	testing.expect_value(t, selected_text(&e), "Neon ")
	edit_key(&e, {.Right, {}, false}, {}, .Windows)
	testing.expect_value(t, e.caret, 5)
	handled, _ := edit_key(&e, {.Left, {.Super}, false}, {}, .Windows)
	testing.expect(t, !handled, "Windows leaves Super+Left to the system")
}

@(test)
the_caret_moves_by_whole_characters :: proc(t: ^testing.T) {
	e := edit_of("Été 坂", 0)
	defer text_edit_destroy(&e)
	edit_key(&e, {.Right, {}, false}, {}, .Mac)
	testing.expect_value(t, e.caret, len("É"))
	edit_key(&e, {.End, {}, false}, {}, .Mac)
	edit_key(&e, {.Backspace, {}, false}, {}, .Mac)
	testing.expect_value(t, edit_text(&e), "Été ")
}

@(test)
a_double_click_selects_a_word_or_what_is_between_words :: proc(t: ^testing.T) {
	e := edit_of("Neon Overpass, Été", 0)
	defer text_edit_destroy(&e)
	edit_select_word(&e, 7)
	testing.expect_value(t, selected_text(&e), "Overpass")
	edit_select_word(&e, 13)
	testing.expect_value(t, selected_text(&e), ",")
	edit_select_word(&e, len(edit_text(&e)))
	testing.expect_value(t, selected_text(&e), "Été")
}

@(test)
typing_a_word_is_one_step_to_undo :: proc(t: ^testing.T) {
	e := edit_of("Neon", 4)
	defer text_edit_destroy(&e)
	for c in ([]string{" ", "O", "v", "e", "r"}) do edit_insert(&e, c)
	edit_key(&e, {.Backspace, {}, false}, {}, .Mac)
	edit_key(&e, {.Backspace, {}, false}, {}, .Mac)
	testing.expect_value(t, edit_text(&e), "Neon Ov")
	testing.expect(t, edit_undo(&e))
	testing.expect_value(t, edit_text(&e), "Neon Over")
	testing.expect(t, edit_undo(&e))
	testing.expect_value(t, edit_text(&e), "Neon")
	testing.expect(t, !edit_undo(&e))
	_, changed := edit_key(&e, {.Z, {.Super, .Shift}, false}, {}, .Mac)
	testing.expect(t, changed)
	testing.expect_value(t, edit_text(&e), "Neon Over")
	edit_insert(&e, "!")
	testing.expect(t, !edit_redo(&e), "a new edit forgets what could be redone")
}

@(test)
copy_cut_and_paste_go_through_the_clipboard :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, proc(ui: ^Ui, data: rawptr) {})
	defer harness_destroy(&h)
	e := edit_of("Paper Satellites", 0)
	defer text_edit_destroy(&e)
	edit_select_word(&e, 0)
	edit_key(&e, {.C, COMMAND, false}, h.ui.clipboard)
	testing.expect_value(t, string(h.clipboard.buf[:]), "Paper")
	edit_key(&e, {.X, COMMAND, false}, h.ui.clipboard)
	testing.expect_value(t, edit_text(&e), " Satellites")
	edit_key(&e, {.End, {}, false}, h.ui.clipboard)
	_, changed := edit_key(&e, {.V, COMMAND, false}, h.ui.clipboard)
	testing.expect(t, changed)
	testing.expect_value(t, edit_text(&e), " SatellitesPaper")
	free_all(context.temp_allocator)
}
