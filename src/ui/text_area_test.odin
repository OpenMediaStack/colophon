package ui

import "core:strings"
import "core:testing"

@(private = "file")
Note :: struct {
	text:    strings.Builder,
	scroll:  Scroll,
	commits: int,
	cancels: int,
}

@(private = "file")
note_frame :: proc(ui: ^Ui, data: rawptr) {
	n := (^Note)(data)
	result := text_area(
		ui,
		widget_id("Comment"),
		{10, 10, 200, 64},
		strings.to_string(n.text),
		"Comment",
		&n.scroll,
	)
	if result.changed || result.committed {
		strings.builder_reset(&n.text)
		strings.write_string(&n.text, result.text)
	}
	if result.committed do n.commits += 1
	if result.cancelled do n.cancels += 1
	button(ui, widget_id("Elsewhere"), {10, 100, 100, 28}, "Elsewhere")
}

@(private = "file")
note_harness :: proc(h: ^Harness, n: ^Note, text := "") {
	n.text = strings.builder_make()
	strings.write_string(&n.text, text)
	harness_init(h, note_frame, n)
	run_frame(h)
}

@(private = "file")
destroy_note :: proc(h: ^Harness, n: ^Note) {
	harness_destroy(h)
	strings.builder_destroy(&n.text)
	free_all(context.temp_allocator)
}

@(test)
enter_adds_a_line_and_the_arrows_move_between_lines :: proc(t: ^testing.T) {
	h: Harness
	n: Note
	note_harness(&h, &n)
	defer destroy_note(&h, &n)
	click(&h, "Comment")
	type_text(&h, "first")
	press_key(&h, .Enter)
	type_text(&h, "second")
	testing.expect_value(t, strings.to_string(n.text), "first\nsecond")
	// Up from the end of the second line: the same place on the first.
	press_key(&h, .Up)
	testing.expect_value(t, h.ui.edit.caret, 5)
	press_key(&h, .Home)
	testing.expect_value(t, h.ui.edit.caret, 0)
	press_key(&h, .Down)
	press_key(&h, .End)
	testing.expect_value(t, h.ui.edit.caret, 12)
	// Tab commits and moves on.
	press_key(&h, .Tab)
	testing.expect_value(t, n.commits, 1)
	testing.expect(t, has_focus(&h.ui, widget_id("Elsewhere")))
}

@(test)
long_text_wraps_and_a_click_lands_on_its_line :: proc(t: ^testing.T) {
	h: Harness
	n: Note
	note_harness(
		&h,
		&n,
		"Remastered from the original tapes, 2025 reissue, with notes by the band.",
	)
	defer destroy_note(&h, &n)
	spans := wrap_lines(
		&h.renderer,
		strings.to_string(n.text),
		.Body,
		200 - 8 - 14,
		context.temp_allocator,
	)
	testing.expect(t, len(spans) >= 2)
	// A click on the second line puts the caret there.
	move_mouse(&h, {20, 10 + 6 + 18 + 9})
	press(&h)
	release(&h)
	testing.expect(t, has_focus(&h.ui, widget_id("Comment")))
	testing.expect(t, h.ui.edit.caret >= spans[1].start && h.ui.edit.caret <= spans[1].end)
	// Escape puts the text back after typing.
	type_text(&h, "X")
	testing.expect(t, strings.contains(strings.to_string(n.text), "X"))
	press_key(&h, .Escape)
	testing.expect_value(t, n.cancels, 1)
	testing.expect_value(t, h.ui.focus, 0)
}

@(test)
a_line_break_kept_in_a_field_of_several_lines_only :: proc(t: ^testing.T) {
	e: Text_Edit
	text_edit_init(&e)
	defer text_edit_destroy(&e)
	edit_insert(&e, "a\nb")
	testing.expect_value(t, edit_text(&e), "ab")
	e.multiline = true
	edit_reset(&e, "", false)
	edit_insert(&e, "a\nb\r")
	testing.expect_value(t, edit_text(&e), "a\nb")
}
