package ui

import "core:math"
import "core:strings"

// How a text field looks besides its text, from the brief's component sheet.
Field_Flag :: enum u8 {
	// Its value waits to be saved.
	Modified,
	// The selected tracks do not share one value: the placeholder says so.
	Multiple_Values,
	// Its value is not one the field takes.
	Error,
	Disabled,
	// Numbers that line up: JetBrains Mono.
	Numeric,
	// On the toolbar, which is raised: the lower surface with the subtle border, as
	// 1.0.0's filter.
	Toolbar,
}

// How a text field looks besides its text.
Field_Flags :: bit_set[Field_Flag]

// What a text field shows besides its value.
Text_Field_Options :: struct {
	// Shown while the field is empty: a hint, or what multiple values hide.
	placeholder:   string,
	flags:         Field_Flags,
	// Enter does nothing: the field keeps the focus and its text, as the toolbar's filter
	// does, whose text applies as it is typed.
	stay_on_enter: bool,
	// Room kept at the right for a button inside the field, in points.
	trailing:      f32,
	// Room kept at the left for an icon inside the field, in points.
	leading:       f32,
	// A button that empties the field, shown while it has text: the toolbar's filter.
	clearable:     bool,
	// What assistive technologies call its clear button; "Clear" when empty.
	clear_label:   string,
	// Whether the text is a value the field takes; nil takes any. While it is not, the
	// field shows the error ring, and Enter and Tab keep the focus so that it shows
	// what is wrong; the text is given up when the focus leaves otherwise, the value
	// coming back as on Escape.
	accepts:       proc(text: string) -> bool,
}

// What happened to a text field this frame.
Text_Field_Result :: struct {
	// The text changed: the app may take it in as a change waiting to be saved.
	changed:   bool,
	// The user is done: Enter, Tab, or a click elsewhere.
	committed: bool,
	// Escape: the field goes back to the value it had when the focus came, which text
	// then holds, so that an app that took in each change can put it back.
	cancelled: bool,
	// The text being typed, while the field has the focus; it lasts until the next edit.
	text:      string,
}

@(private = "file")
FIELD_PADDING :: 8
// The side of the clear button, which fits a field 28 high.
@(private = "file")
CLEAR_BUTTON :: 20
@(private)
CARET_WIDTH :: 1.5
// The caret shows this long, then hides as long.
@(private)
BLINK :: 0.53

// A one-line text field showing value, labelled label for screen readers and tests.
// While it has the keyboard focus it edits its own copy of the text, which result.text
// gives; the app takes it in when it changes or is committed, and draws the field with
// the new value from then on.
text_field :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	value: string,
	label: string,
	options := Text_Field_Options{},
) -> (
	result: Text_Field_Result,
) {
	disabled := .Disabled in options.flags
	style := .Numeric in options.flags ? Text_Style.Numeric : Text_Style.Body
	text_rect := rect_inset(rect, FIELD_PADDING, 0)
	text_rect.x += options.leading
	text_rect.w = max(text_rect.w - options.trailing - options.leading, 0)
	interaction: Interaction
	if disabled {
		release_focus(ui, id)
	} else {
		interaction = interact(ui, id, rect)
		if .Hovered in interaction do ui.cursor = .Text
	}
	// The focus went to another widget's request while this field was typed in: what
	// was typed is committed, as a click elsewhere would.
	if ui.edit_ended == id {
		ended := string(ui.edit_ended_text[:])
		if accepted(options.accepts, ended) {
			result.committed = true
			result.text = ended
		} else {
			result.cancelled = true
			result.text = string(ui.edit_ended_start[:])
		}
		ui.edit_ended = 0
	}
	focused := has_focus(ui, id) && !disabled
	if focused && ui.edit_owner != id {
		// The focus just came: the field edits a copy of its value, all of it selected
		// when the focus came by Tab, else with the caret where the click was. The value
		// is kept, for Escape to bring back.
		ui.edit.multiline = false
		edit_reset(&ui.edit, value, ui.focus_by_key)
		if click, clicked := ui.edit_click.?; clicked && click.owner == id do edit_move(&ui.edit, click.offset)
		ui.edit_click = nil
		clear(&ui.edit_start)
		append(&ui.edit_start, value)
		ui.edit_owner = id
		ui.edit_scroll = 0
		ui.caret_time = ui.input.time
	}
	if !focused && ui.edit_owner == id do ui.edit_owner = 0
	if .Pressed in interaction && !focused {
		request_focus(ui, id)
		ui.edit_click = Edit_Click {
			id,
			offset_in(ui.renderer, value, text_rect, style, ui.input.mouse.x, 0),
		}
	}
	if focused && !keys_blocked(ui) {
		result = edit_field(
			ui,
			id,
			rect,
			text_rect,
			style,
			interaction,
			options.accepts,
			options.stay_on_enter,
		)
	}
	shown := focused ? edit_text(&ui.edit) : value
	options := options
	if !accepted(options.accepts, shown) do options.flags += {.Error}
	draw_text_field(ui, rect, text_rect, value, style, options, interaction, focused)
	if options.clearable && len(shown) > 0 && !disabled {
		// Inside the field's trailing room: a click on it is not a click elsewhere, and
		// the field keeps the focus if it had it.
		clear := Rect {
			rect.x + rect.w - CLEAR_BUTTON - 4,
			rect.y + (rect.h - CLEAR_BUTTON) / 2,
			CLEAR_BUTTON,
			CLEAR_BUTTON,
		}
		clear_label := options.clear_label != "" ? options.clear_label : "Clear"
		if icon_button(ui, child_id(id, "clear"), clear, .X, clear_label, 12, focusable = false) {
			if focused do edit_reset(&ui.edit, "", false)
			result.changed = true
			result.text = ""
			shown = ""
		}
	}
	declare(
		ui,
		{
			id = id,
			role = .Text_Field,
			label = label,
			value = shown,
			placeholder = options.placeholder,
			rect = rect,
			states = field_states(interaction, focused, disabled),
			focusable = !disabled,
		},
	)
	return
}

// Gives a field the focus with all its text selected, or selects all its text when it
// has the focus already: a shortcut that reaches the filter.
focus_field :: proc(ui: ^Ui, id: Widget_Id) {
	if has_focus(ui, id) && ui.edit_owner == id {
		edit_select_all(&ui.edit)
		return
	}
	request_focus(ui, id, by_key = true)
}

// Whether accepts takes the text; nil takes any.
@(private = "file")
accepted :: proc(accepts: proc(text: string) -> bool, text: string) -> bool {
	return accepts == nil || accepts(text)
}

// The keys, the typed text and the mouse on the focused field. Text that accepts
// refuses keeps the focus on Enter and Tab, and is given up on a click elsewhere. A field
// that stays on Enter ignores that key.
@(private = "file")
edit_field :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect, text_rect: Rect,
	style: Text_Style,
	interaction: Interaction,
	accepts: proc(text: string) -> bool,
	stay_on_enter: bool,
) -> (
	result: Text_Field_Result,
) {
	e := &ui.edit
	in_ := &ui.input
	moved_caret := e.caret
	if .Pressed in interaction {
		at := offset_in(ui.renderer, edit_text(e), text_rect, style, in_.mouse.x, ui.edit_scroll)
		switch {
		case in_.clicks >= 3:
			edit_select_all(e)
		case in_.clicks == 2:
			edit_select_word(e, at)
		case:
			edit_move(e, at, .Shift in in_.modifiers)
		}
	} else if .Held in interaction && .Left in in_.down && in_.clicks < 2 {
		at := offset_in(ui.renderer, edit_text(e), text_rect, style, in_.mouse.x, ui.edit_scroll)
		edit_move(e, at, true)
	}
	// A click in a popup, such as the field's suggestions, is not a click elsewhere.
	if .Left in in_.pressed && !mouse_over(ui, rect) && !mouse_in_popup(ui) {
		if accepted(accepts, edit_text(e)) {
			result.committed = true
		} else {
			result.cancelled = true
			edit_reset(e, string(ui.edit_start[:]), false)
		}
		release_focus(ui, id)
	}
	// The keys and the text in the order they came: a Backspace before a letter
	// deletes what was there before the letter.
	typed := strings.to_string(in_.text)
	inserted := 0
	insert_until :: proc(
		e: ^Text_Edit,
		typed: string,
		inserted: ^int,
		at: int,
		result: ^Text_Field_Result,
	) {
		end := clamp(at, inserted^, len(typed))
		if end > inserted^ {
			edit_insert(e, typed[inserted^:end])
			result.changed = true
		}
		inserted^ = end
	}
	for i := 0; i < len(in_.keys); {
		press := in_.keys[i]
		insert_until(e, typed, &inserted, press.text_at, &result)
		taken := true
		#partial switch press.key {
		case .Enter:
			if stay_on_enter do break
			if accepted(accepts, edit_text(e)) {
				result.committed = true
				release_focus(ui, id)
			}
		case .Tab:
			if accepted(accepts, edit_text(e)) {
				result.committed = true
				move_focus(ui, .Shift in press.modifiers ? .Back : .Forward)
			}
		case .Escape:
			result.cancelled = true
			edit_reset(e, string(ui.edit_start[:]), false)
			release_focus(ui, id)
		case:
			handled, changed := edit_key(e, press, ui.clipboard)
			// A key that types text belongs to the field, not to the shortcuts.
			taken = handled || types_text(press)
			if changed do result.changed = true
		}
		if taken {
			ordered_remove(&in_.keys, i)
		} else {
			i += 1
		}
	}
	insert_until(e, typed, &inserted, len(typed), &result)
	if result.committed || result.cancelled do ui.edit_reported = true
	if e.caret != moved_caret || result.changed do ui.caret_time = in_.time
	result.text = edit_text(e)
	return
}

// Whether a key types text: a letter, a digit, Space or punctuation, alone, with
// Shift, or with Control and Alt, which is AltGr on Windows.
@(private)
types_text :: proc(press: Key_Press) -> bool {
	m := press.modifiers - {.Shift}
	if m != {} && m != {.Control, .Alt} do return false
	#partial switch press.key {
	case .A ..= .Z, .Num_0 ..= .Num_9, .Space, .Comma, .Period, .Slash, .Minus, .Equals:
		return true
	}
	return false
}

// The offset in s, drawn from text_rect's left edge scrolled by scroll, nearest to x.
@(private)
offset_in :: proc(
	r: ^Renderer,
	s: string,
	text_rect: Rect,
	style: Text_Style,
	x, scroll: f32,
) -> int {
	xs := caret_positions(r, s, style, context.temp_allocator)
	target := x - text_rect.x + scroll
	best, best_distance := 0, f32(math.F32_MAX)
	for px, i in xs {
		if !is_char_boundary(s, i) do continue
		if d := abs(px - target); d < best_distance do best, best_distance = i, d
	}
	return best
}

@(private = "file")
draw_text_field :: proc(
	ui: ^Ui,
	rect, text_rect: Rect,
	value: string,
	style: Text_Style,
	options: Text_Field_Options,
	interaction: Interaction,
	focused: bool,
) {
	th := ui.theme
	r := ui.renderer
	states: Field_Flags = options.flags
	field_box(r, th, rect, states, .Hovered in interaction, focused)
	middle := rect.y + rect.h / 2
	push_clip(r, {text_rect.x - 1, rect.y, text_rect.w + 2, rect.h})
	defer pop_clip(r)
	if !focused {
		draw_field_value(r, th, text_rect, value, style, options)
		return
	}
	s := edit_text(&ui.edit)
	xs := caret_positions(r, s, style, context.temp_allocator)
	caret_x := xs[ui.edit.caret]
	// The caret stays in view: the text scrolls under it.
	if caret_x - ui.edit_scroll > text_rect.w - CARET_WIDTH do ui.edit_scroll = caret_x - text_rect.w + CARET_WIDTH
	if caret_x < ui.edit_scroll do ui.edit_scroll = caret_x
	if xs[len(xs) - 1] <= text_rect.w do ui.edit_scroll = 0
	x := text_rect.x - ui.edit_scroll
	if has_selection(&ui.edit) {
		a := xs[min(ui.edit.caret, ui.edit.anchor)]
		b := xs[max(ui.edit.caret, ui.edit.anchor)]
		fill_rect(r, {x + a, middle - 9, b - a, 18}, th.accent_selection)
	}
	if len(s) == 0 do draw_field_value(r, th, text_rect, "", style, options)
	draw_text(r, s, x, middle, style, th.text_primary)
	// Behind a dialog or an open menu, the field takes no keys: no caret, no blinking.
	if keys_blocked(ui) do return
	since := ui.input.time - ui.caret_time
	if math.mod(since, 2 * BLINK) < BLINK {
		fill_rect(r, {x + caret_x, middle - 8, CARET_WIDTH, 16}, th.text_primary)
	}
	// The next time the caret shows or hides.
	wake_at(ui, ui.caret_time + (math.floor(since / BLINK) + 1) * BLINK)
}

// The background and border of a field in its states: the text field, the number
// pair and the combo box share it.
draw_field_box :: proc(
	r: ^Renderer,
	th: Theme,
	rect: Rect,
	flags: Field_Flags,
	hovered, focused: bool,
) {
	field_box(r, th, rect, flags, hovered, focused)
}

@(private = "file")
field_box :: proc(
	r: ^Renderer,
	th: Theme,
	rect: Rect,
	flags: Field_Flags,
	hovered, focused: bool,
) {
	disabled := .Disabled in flags
	on_toolbar := .Toolbar in flags
	fill_rect(r, rect, disabled || on_toolbar ? th.surface_1 : th.surface_2, 4)
	border := on_toolbar ? th.border_subtle : th.border_strong
	switch {
	case disabled:
		border = th.border_subtle
	case .Error in flags:
		border = th.error
	case .Modified in flags:
		border = th.modified_border
	case hovered:
		border = th.text_tertiary
	}
	switch {
	case focused && .Error in flags:
		// The error says more than the focus while the user types an invalid value.
		stroke_rect(r, rect, th.error, 4, 2)
	case focused:
		stroke_rect(r, rect, th.focus_ring, 4, 2)
	case:
		stroke_rect(r, rect, border, 4)
	}
}

// A field's value, or its placeholder when it has none, cut to fit.
@(private = "file")
draw_field_value :: proc(
	r: ^Renderer,
	th: Theme,
	text_rect: Rect,
	value: string,
	style: Text_Style,
	options: Text_Field_Options,
) {
	middle := text_rect.y + text_rect.h / 2
	if len(value) > 0 {
		color := .Disabled in options.flags ? th.text_disabled : th.text_primary
		draw_text_fit(r, value, text_rect.x, middle, text_rect.w, style, color)
	} else if len(options.placeholder) > 0 {
		// In Inter whatever the value's font, as 1.0.0's: a hint is words, not numbers.
		draw_text_fit(
			r,
			options.placeholder,
			text_rect.x,
			middle,
			text_rect.w,
			.Body,
			th.text_tertiary,
		)
	}
}

@(private)
field_states :: proc(interaction: Interaction, focused, disabled: bool) -> (w: Widget_States) {
	if .Hovered in interaction do w += {.Hovered}
	if focused do w += {.Focused}
	if disabled do w += {.Disabled}
	return
}
