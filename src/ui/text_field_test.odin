package ui

import "core:strings"
import "core:testing"

// Two fields and what they reported.
@(private = "file")
Form :: struct {
	values:   [2]strings.Builder,
	changes:  [2]int,
	commits:  [2]int,
	cancels:  [2]int,
	disabled: bool,
}

@(private = "file")
FIELD_LABELS := [2]string{"Title", "Artist"}

@(private = "file")
form_frame :: proc(ui: ^Ui, data: rawptr) {
	f := (^Form)(data)
	for label, i in FIELD_LABELS {
		options := Text_Field_Options {
			placeholder = "Multiple values",
		}
		if i == 1 && f.disabled do options.flags += {.Disabled}
		value := strings.to_string(f.values[i])
		result := text_field(
			ui,
			widget_id(label),
			{10, 10 + f32(i) * 40, 200, 28},
			value,
			label,
			options,
		)
		if result.changed do f.changes[i] += 1
		if result.cancelled do f.cancels[i] += 1
		if result.committed {
			f.commits[i] += 1
			strings.builder_reset(&f.values[i])
			strings.write_string(&f.values[i], result.text)
		}
	}
}

@(private = "file")
form_harness :: proc(
	h: ^Harness,
	f: ^Form,
	title := "Paper Satellites",
	artist := "Marlowe Kite",
) {
	for &v, i in f.values {
		v = strings.builder_make()
		strings.write_string(&v, i == 0 ? title : artist)
	}
	harness_init(h, form_frame, f)
	run_frame(h)
}

@(private = "file")
destroy_form :: proc(h: ^Harness, f: ^Form) {
	harness_destroy(h)
	for &v in f.values do strings.builder_destroy(&v)
	free_all(context.temp_allocator)
}

@(private = "file")
value_of :: proc(f: ^Form, i: int) -> string {
	return strings.to_string(f.values[i])
}

// Clicks at a point of the field labelled label, x from its left edge.
@(private = "file")
click_at :: proc(h: ^Harness, label: string, x: f32, clicks := 1) {
	info, _ := find_widget(&h.ui, label)
	move_mouse(h, {info.rect.x + x, info.rect.y + info.rect.h / 2})
	for i in 1 ..= clicks {
		press(h, .Left, i)
		release(h, .Left)
	}
}

@(test)
a_click_focuses_a_field_with_the_caret_where_it_was :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click_at(&h, "Title", 2)
	testing.expect(t, has_focus(&h.ui, widget_id("Title")))
	testing.expect_value(t, h.ui.edit.caret, 0)
	type_text(&h, "The ")
	testing.expect_value(t, edit_text(&h.ui.edit), "The Paper Satellites")
	testing.expect_value(t, f.changes[0], 1)
	// The value waits for the commit.
	testing.expect_value(t, value_of(&f, 0), "Paper Satellites")
	press_key(&h, .Enter)
	testing.expect_value(t, f.commits[0], 1)
	testing.expect_value(t, value_of(&f, 0), "The Paper Satellites")
	testing.expect(t, !has_focus(&h.ui, widget_id("Title")))
}

@(test)
escape_brings_the_value_back :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click(&h, "Title")
	type_text(&h, "!")
	press_key(&h, .Escape)
	testing.expect_value(t, f.cancels[0], 1)
	testing.expect_value(t, value_of(&f, 0), "Paper Satellites")
	info, _ := find_widget(&h.ui, "Title")
	testing.expect_value(t, info.value, "Paper Satellites")
}

@(test)
tab_commits_and_moves_to_the_next_field_selecting_its_text :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click(&h, "Title")
	type_text(&h, "!")
	press_key(&h, .Tab)
	testing.expect_value(t, f.commits[0], 1)
	testing.expect(t, has_focus(&h.ui, widget_id("Artist")))
	run_frame(&h)
	testing.expect_value(t, selected_text(&h.ui.edit), "Marlowe Kite")
	press_key(&h, .Tab, {.Shift})
	testing.expect(t, has_focus(&h.ui, widget_id("Title")))
}

@(test)
a_click_elsewhere_commits :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click(&h, "Title")
	type_text(&h, "!")
	move_mouse(&h, {500, 500})
	press(&h)
	release(&h)
	testing.expect_value(t, f.commits[0], 1)
	testing.expect_value(t, h.ui.focus, 0)
}

@(test)
a_double_click_selects_a_word_and_a_triple_click_everything :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click(&h, "Title")
	click_at(&h, "Title", 14, clicks = 2)
	testing.expect_value(t, selected_text(&h.ui.edit), "Paper")
	click_at(&h, "Title", 14, clicks = 3)
	testing.expect_value(t, selected_text(&h.ui.edit), "Paper Satellites")
}

@(test)
dragging_selects :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click_at(&h, "Title", 2)
	press(&h)
	move_mouse(&h, {300, 24})
	release(&h)
	testing.expect_value(t, selected_text(&h.ui.edit), "Paper Satellites")
}

@(test)
a_disabled_field_takes_no_focus :: proc(t: ^testing.T) {
	h: Harness
	f := Form {
		disabled = true,
	}
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click(&h, "Artist")
	testing.expect_value(t, h.ui.focus, 0)
	click(&h, "Title")
	press_key(&h, .Tab)
	testing.expect(t, has_focus(&h.ui, widget_id("Title")), "Tab skips the disabled field")
}

@(test)
the_caret_blinks :: proc(t: ^testing.T) {
	h: Harness
	f: Form
	form_harness(&h, &f)
	defer destroy_form(&h, &f)
	click(&h, "Title")
	caret_drawn :: proc(h: ^Harness) -> bool {
		th := h.ui.theme
		for list in h.renderer.lists {
			for v in list.vertices do if v.color == th.accent do return true
		}
		return false
	}
	testing.expect(t, caret_drawn(&h))
	wait(&h, 0.6)
	testing.expect(t, !caret_drawn(&h))
	wait(&h, 0.6)
	testing.expect(t, caret_drawn(&h))
}

// Every state of the text field in the brief's component sheet, in both themes.
@(test)
the_text_fields_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{520, 300}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	draw_field_sheet(cap.renderer, {0, 0, size.x / 2, size.y}, .Dark)
	draw_field_sheet(cap.renderer, {size.x / 2, 0, size.x / 2, size.y}, .Light)
	finish_capture(t, &cap, "text-fields.png")
}

@(private = "file")
draw_field_sheet :: proc(r: ^Renderer, area: Rect, kind: Theme_Kind) {
	ui: Ui
	ui_init(&ui, r, theme(kind))
	defer ui_destroy(&ui)
	fill_rect(r, area, ui.theme.surface_1)
	Sample :: struct {
		value:   string,
		flags:   Field_Flags,
		hovered: bool,
		focused: bool,
	}
	samples := [?]Sample {
		{value = "Paper Satellites"},
		{value = "Paper Satellites", hovered = true},
		{value = "Paper Satellites", focused = true},
		{value = "Analog Hearts", flags = {.Modified}},
		{flags = {.Multiple_Values}},
		{value = "13 of 12", flags = {.Error}},
		{value = "Small Hours", flags = {.Disabled}},
		{value = "2019", flags = {.Numeric}},
	}
	y := area.y + 12
	for sample, i in samples {
		id := widget_id("Sample", i)
		rect := Rect{area.x + 16, y, area.w - 32, BUTTON_HEIGHT}
		ui.input.mouse = sample.hovered ? rect_center(rect) : {-1, -1}
		ui.hot = sample.hovered ? id : 0
		if sample.focused {
			ui.focus = id
			ui.edit_owner = id
			edit_reset(&ui.edit, sample.value, false)
			edit_move(&ui.edit, 6)
			edit_move(&ui.edit, len(sample.value), extend = true)
		}
		text_field(
			&ui,
			id,
			rect,
			sample.value,
			"Sample",
			{placeholder = "Multiple values", flags = sample.flags},
		)
		y += 36
	}
}
