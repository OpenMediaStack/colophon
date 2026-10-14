package ui

import "core:strings"

// The list of suggestions open under a combo box. Only one is open at a time.
Combo_State :: struct {
	owner:       Widget_Id,
	open:        bool,
	// What the suggestions match: the text typed, or nothing for every choice.
	filter:      [dynamic]u8,
	// The suggestion the arrow keys reached; -1 for none.
	highlighted: int,
	// How far the list has scrolled, in points.
	scroll:      f32,
}

@(private = "file")
ITEM_HEIGHT :: 24
@(private = "file")
LIST_INSET :: 4
@(private = "file")
VISIBLE_ITEMS :: 8
@(private = "file")
SHOW_ALL_WIDTH :: 22
// The room the field keeps for the button: its text runs under the button's edge, as
// in 1.0.0, and stops short of the chevron.
@(private = "file")
TEXT_TRAILING :: 14
@(private = "file")
LIST_GAP :: 2

// The choices that hold text, ignoring case and the spaces around it: those that
// start with it first, then the others, each group in the choices' order. Allocated
// with allocator; the strings are the choices'.
@(private)
suggest :: proc(choices: []string, text: string, allocator := context.allocator) -> []string {
	wanted := strings.to_lower(strings.trim_space(text), context.temp_allocator)
	starting := make([dynamic]string, allocator)
	holding := make([dynamic]string, context.temp_allocator)
	for choice in choices {
		at := strings.index(strings.to_lower(choice, context.temp_allocator), wanted)
		switch {
		case at == 0:
			append(&starting, choice)
		case at > 0:
			append(&holding, choice)
		}
	}
	append(&starting, ..holding[:])
	return starting[:]
}

// A text field that suggests choices as the user types, with a button that shows them
// all: the genre of the inspector. The arrow keys move through the suggestions, Enter
// or a click picks one, which commits the field with it. The list closes when the field
// loses the focus, drawn or not.
combo_box :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	value: string,
	label: string,
	choices: []string,
	options := Text_Field_Options{},
) -> (
	result: Text_Field_Result,
) {
	combo := &ui.combo
	focused := has_focus(ui, id)
	if combo.owner != id && focused do close_suggestions(combo, id)
	// A list left open when the field lost the focus, or was not drawn, is stale.
	if combo.owner == id && !focused do combo.open = false
	open := focused && combo.owner == id && combo.open
	shown := open ? suggest(choices, string(combo.filter[:]), context.temp_allocator) : nil
	// The list shows: the keys move through it. An open list that matches nothing
	// leaves the keys to the field.
	suggesting := open && len(shown) > 0
	picked: Maybe(string)
	if focused {
		switch {
		case suggesting && take_key(ui, .Escape):
			combo.open = false
		case suggesting && take_key(ui, .Down, repeats = true):
			combo.highlighted = min(combo.highlighted + 1, len(shown) - 1)
			reveal_highlighted(combo, len(shown))
		case suggesting && take_key(ui, .Up, repeats = true):
			// Back to none, where Enter commits the text typed.
			combo.highlighted = max(combo.highlighted - 1, -1)
			reveal_highlighted(combo, len(shown))
		case suggesting &&
		     combo.highlighted >= 0 &&
		     combo.highlighted < len(shown) &&
		     take_key(ui, .Enter):
			picked = shown[combo.highlighted]
		case !suggesting && take_key(ui, .Down):
			open_suggestions(combo, id, "")
		}
	}

	field_options := options
	field_options.trailing = TEXT_TRAILING
	result = text_field(ui, id, rect, value, label, field_options)
	if result.changed do open_suggestions(combo, id, result.text)
	if result.committed || result.cancelled do combo.open = false

	show_all := Rect{rect.x + rect.w - SHOW_ALL_WIDTH - 4, rect.y + 2, SHOW_ALL_WIDTH, rect.h - 4}
	if .Disabled not_in options.flags {
		show_id := child_id(id, "show all")
		interaction := interact(ui, show_id, show_all)
		if .Hovered in interaction do ui.cursor = .Pointer
		// Every choice, whatever was typed.
		if .Pressed in interaction {
			if !focused do request_focus(ui, id)
			open_suggestions(combo, id, "")
		}
		declare(ui, {id = show_id, role = .Button, label = "Show suggestions", rect = show_all})
	}
	color := .Disabled in options.flags ? ui.theme.text_disabled : ui.theme.text_tertiary
	draw_icon_centered(ui.renderer, .Chevron_Down, show_all, color)

	if combo.owner == id && combo.open && has_focus(ui, id) {
		shown = suggest(choices, string(combo.filter[:]), context.temp_allocator)
		if item, clicked := draw_suggestions(ui, id, rect, shown); clicked do picked = item
	}
	if item, was_picked := picked.?; was_picked {
		edit_reset(&ui.edit, item, false)
		result.text = edit_text(&ui.edit)
		result.committed = true
		result.changed = item != value
		// The field said it was done: losing the focus commits nothing more.
		ui.edit_reported = true
		combo.open = false
		release_focus(ui, id)
	}
	return
}

// The pair of numbers of the inspector, track 3 of 12 or disc 1 of 2: two numeric
// fields with a word between them, labelled labels for screen readers and tests.
number_pair :: proc(
	ui: ^Ui,
	id: Widget_Id,
	at: [2]f32,
	number, total: string,
	labels: [2]string,
	between: string,
	options := [2]Text_Field_Options{},
) -> (
	number_result, total_result: Text_Field_Result,
) {
	NUMBER_WIDTH :: 72
	TOTAL_WIDTH :: 52
	GAP :: 6
	number_options, total_options := options[0], options[1]
	number_options.flags += {.Numeric}
	total_options.flags += {.Numeric}
	row := Rect{at.x, at.y, NUMBER_WIDTH, BUTTON_HEIGHT}
	number_result = text_field(ui, child_id(id, "number"), row, number, labels[0], number_options)
	word := text_width(ui.renderer, between, .Body)
	word_rect := Rect{at.x + NUMBER_WIDTH + GAP, at.y, word, BUTTON_HEIGHT}
	declare(ui, {id = child_id(id, "between"), role = .Label, label = between, rect = word_rect})
	draw_text(
		ui.renderer,
		between,
		at.x + NUMBER_WIDTH + GAP,
		at.y + BUTTON_HEIGHT / 2,
		.Body,
		ui.theme.text_tertiary,
	)
	total_rect := Rect{at.x + NUMBER_WIDTH + 2 * GAP + word, at.y, TOTAL_WIDTH, BUTTON_HEIGHT}
	total_result = text_field(
		ui,
		child_id(id, "total"),
		total_rect,
		total,
		labels[1],
		total_options,
	)
	return
}

@(private = "file")
open_suggestions :: proc(combo: ^Combo_State, id: Widget_Id, filter: string) {
	combo.owner = id
	combo.open = true
	combo.highlighted = -1
	combo.scroll = 0
	clear(&combo.filter)
	append(&combo.filter, filter)
}

// Scrolls the least that shows the highlighted suggestion, among count: when the arrow
// keys move it, so that the wheel scrolls freely otherwise.
@(private = "file")
reveal_highlighted :: proc(combo: ^Combo_State, count: int) {
	if combo.highlighted < 0 do return
	view := f32(min(count, VISIBLE_ITEMS)) * ITEM_HEIGHT
	top := f32(combo.highlighted) * ITEM_HEIGHT
	if top < combo.scroll do combo.scroll = top
	if top + ITEM_HEIGHT > combo.scroll + view do combo.scroll = top + ITEM_HEIGHT - view
}

@(private = "file")
close_suggestions :: proc(combo: ^Combo_State, id: Widget_Id) {
	combo.owner = id
	combo.open = false
	clear(&combo.filter)
}

// Draws the suggestions under the field at rect, and gives the one clicked.
@(private = "file")
draw_suggestions :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	shown: []string,
) -> (
	picked: string,
	clicked: bool,
) {
	if len(shown) == 0 do return
	combo := &ui.combo
	th := ui.theme
	r := ui.renderer
	visible := min(len(shown), VISIBLE_ITEMS)
	list := Rect {
		rect.x,
		rect.y + rect.h + LIST_GAP,
		rect.w,
		f32(visible) * ITEM_HEIGHT + 2 * LIST_INSET,
	}
	inner := rect_inset(list, 1, LIST_INSET)
	content := f32(len(shown)) * ITEM_HEIGHT
	most := max(content - inner.h, 0)
	begin_popup(ui, list)
	defer end_popup(ui)
	if mouse_over(ui, list) do combo.scroll += ui.input.wheel.y
	combo.scroll = clamp(combo.scroll, 0, most)
	fill_rect(r, list, th.surface_2, 6)
	stroke_rect(r, list, th.border_subtle, 6)
	list_id := child_id(id, "suggestions")
	declare(ui, {id = list_id, role = .Group, label = "Suggestions", rect = list})
	push_parent(ui, list_id)
	defer pop_parent(ui)
	push_clip(r, inner)
	defer pop_clip(r)
	first := int(combo.scroll / ITEM_HEIGHT)
	for i in first ..< min(len(shown), first + visible + 1) {
		row := Rect{inner.x, inner.y + f32(i) * ITEM_HEIGHT - combo.scroll, inner.w, ITEM_HEIGHT}
		item_id := child_id(id, "suggestion", i)
		interaction := interact(ui, item_id, row)
		if .Hovered in interaction do ui.cursor = .Pointer
		switch {
		case i == combo.highlighted:
			fill_rect(r, row, th.accent_selection)
		case .Hovered in interaction:
			fill_rect(r, row, th.surface_3)
		}
		draw_text_fit(
			r,
			shown[i],
			row.x + 8,
			row.y + row.h / 2,
			row.w - 16,
			.Body,
			th.text_primary,
		)
		states: Widget_States = i == combo.highlighted ? {.Selected} : {}
		declare(
			ui,
			{id = item_id, role = .Menu_Item, label = shown[i], rect = row, states = states},
		)
		if .Clicked in interaction do picked, clicked = shown[i], true
	}
	return
}
