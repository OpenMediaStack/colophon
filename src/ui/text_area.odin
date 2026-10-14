package ui

import "core:math"
import "core:strings"

// The height of a line of a field of several lines.
@(private = "file")
AREA_LINE :: 18
@(private = "file")
AREA_PADDING :: 8
@(private = "file")
AREA_TOP :: 6
// The room the text leaves for the scroll bar at the right.
@(private = "file")
AREA_BAR :: 14

// A field of several lines, wrapped, showing value: the comment of the inspector. It
// edits as a text field does, Enter adding a line, Tab or a click elsewhere committing
// and Escape bringing the value back. The lines scroll with the wheel and with the bar
// at the right, and follow the caret; scroll is theirs to keep between frames.
text_area :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	value: string,
	label: string,
	scroll: ^Scroll,
	options := Text_Field_Options{},
) -> (
	result: Text_Field_Result,
) {
	disabled := .Disabled in options.flags
	inner := Rect {
		rect.x + AREA_PADDING,
		rect.y + AREA_TOP,
		rect.w - AREA_PADDING - AREA_BAR,
		rect.h - 2 * AREA_TOP,
	}
	interaction: Interaction
	if disabled {
		release_focus(ui, id)
	} else {
		interaction = interact(ui, id, rect)
		if .Hovered in interaction do ui.cursor = .Text
	}
	if ui.edit_ended == id {
		result.committed = true
		result.text = string(ui.edit_ended_text[:])
		ui.edit_ended = 0
	}
	focused := has_focus(ui, id) && !disabled
	if focused && ui.edit_owner != id {
		ui.edit.multiline = true
		edit_reset(&ui.edit, value, ui.focus_by_key)
		if click, clicked := ui.edit_click.?; clicked && click.owner == id do edit_move(&ui.edit, click.offset)
		ui.edit_click = nil
		clear(&ui.edit_start)
		append(&ui.edit_start, value)
		ui.edit_owner = id
		ui.caret_time = ui.input.time
	}
	if !focused && ui.edit_owner == id do ui.edit_owner = 0
	shown := focused ? edit_text(&ui.edit) : value
	r := ui.renderer
	th := ui.theme
	draw_field_box(r, th, rect, options.flags, .Hovered in interaction, focused)
	// The lines, and where each lies, for the caret and the clicks.
	spans := wrap_lines(r, shown, .Body, inner.w, context.temp_allocator)
	content := [2]f32{inner.w, f32(len(spans)) * AREA_LINE}
	clip := Rect{rect.x + 1, rect.y + 1, rect.w - 2, rect.h - 2}
	if .Pressed in interaction && !focused {
		request_focus(ui, id)
		at := offset_at(r, shown, spans, inner, scroll^, ui.input.mouse)
		ui.edit_click = Edit_Click{id, at}
	}
	if focused && !keys_blocked(ui) do result = edit_area(ui, id, rect, inner, spans, scroll, interaction)
	// The caret stays in view.
	if focused {
		line := line_of(spans, ui.edit.caret)
		scroll_into_view(scroll, f32(line) * AREA_LINE, AREA_LINE, inner.h)
	}
	push_clip(r, clip)
	origin := begin_scroll(ui, id, inner, content, scroll)
	if focused {
		draw_area_text(ui, shown, spans, inner, origin)
	} else if len(shown) == 0 {
		draw_text(
			r,
			options.placeholder,
			inner.x,
			origin.y + AREA_LINE / 2,
			.Body,
			th.text_tertiary,
		)
	} else {
		for span, i in spans {
			draw_text(
				r,
				shown[span.start:span.end],
				inner.x,
				origin.y + f32(i) * AREA_LINE + AREA_LINE / 2,
				.Body,
				th.text_primary,
			)
		}
	}
	end_scroll(ui, id, inner, content, scroll)
	pop_clip(r)
	declare(
		ui,
		{
			id = id,
			role = .Text_Field,
			label = label,
			value = shown,
			rect = rect,
			states = field_states(interaction, focused, disabled),
			focusable = !disabled,
		},
	)
	return
}

// The keys, the typed text and the mouse on the focused area.
@(private = "file")
edit_area :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect, inner: Rect,
	spans: []Line_Span,
	scroll: ^Scroll,
	interaction: Interaction,
) -> (
	result: Text_Field_Result,
) {
	e := &ui.edit
	in_ := &ui.input
	r := ui.renderer
	moved_caret := e.caret
	text := edit_text(e)
	if .Pressed in interaction {
		at := offset_at(r, text, spans, inner, scroll^, in_.mouse)
		switch {
		case in_.clicks >= 3:
			edit_select_all(e)
		case in_.clicks == 2:
			edit_select_word(e, at)
		case:
			edit_move(e, at, .Shift in in_.modifiers)
		}
	} else if .Held in interaction && .Left in in_.down && in_.clicks < 2 {
		edit_move(e, offset_at(r, text, spans, inner, scroll^, in_.mouse), true)
	}
	if .Left in in_.pressed && !mouse_over(ui, rect) && !mouse_in_popup(ui) {
		result.committed = true
		release_focus(ui, id)
	}
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
		shift := .Shift in press.modifiers
		#partial switch press.key {
		case .Enter:
			edit_insert(e, "\n")
			result.changed = true
		case .Tab:
			result.committed = true
			move_focus(ui, shift ? .Back : .Forward)
		case .Escape:
			result.cancelled = true
			edit_reset(e, string(ui.edit_start[:]), false)
			release_focus(ui, id)
		case .Up, .Down:
			// The same place on the line above or below: the lines as they are now.
			current := wrap_lines(r, edit_text(e), .Body, inner.w, context.temp_allocator)
			line := line_of(current, e.caret)
			x := caret_x(r, edit_text(e), current, line, e.caret)
			target := press.key == .Up ? line - 1 : line + 1
			switch {
			case target < 0:
				edit_move(e, 0, shift)
			case target >= len(current):
				edit_move(e, len(e.buffer), shift)
			case:
				edit_move(e, offset_on_line(r, edit_text(e), current[target], x), shift)
			}
		case .Home, .End:
			current := wrap_lines(r, edit_text(e), .Body, inner.w, context.temp_allocator)
			span := current[line_of(current, e.caret)]
			edit_move(e, press.key == .Home ? span.start : span.end, shift)
		case:
			handled, changed := edit_key(e, press, ui.clipboard)
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

// The focused area's lines, with the selection and the caret.
@(private = "file")
draw_area_text :: proc(ui: ^Ui, text: string, spans: []Line_Span, inner: Rect, origin: [2]f32) {
	r := ui.renderer
	th := ui.theme
	e := &ui.edit
	low, high := min(e.caret, e.anchor), max(e.caret, e.anchor)
	for span, i in spans {
		y := origin.y + f32(i) * AREA_LINE
		line := text[span.start:span.end]
		if low < high && low <= span.end && high >= span.start {
			from := clamp(low, span.start, span.end)
			to := clamp(high, span.start, span.end)
			a := text_width(r, text[span.start:from], .Body)
			b := text_width(r, text[span.start:to], .Body)
			// A selection that goes past the line's end shows a space for the break.
			if high > span.end do b += 4
			fill_rect(r, {inner.x + a, y, b - a, AREA_LINE}, th.accent_selection)
		}
		draw_text(r, line, inner.x, y + AREA_LINE / 2, .Body, th.text_primary)
	}
	line := line_of(spans, e.caret)
	x := caret_x(r, text, spans, line, e.caret)
	since := ui.input.time - ui.caret_time
	if math.mod(since, 2 * BLINK) < BLINK {
		fill_rect(
			r,
			{inner.x + x, origin.y + f32(line) * AREA_LINE + 1, CARET_WIDTH, AREA_LINE - 2},
			th.text_primary,
		)
	}
	wake_at(ui, ui.caret_time + (math.floor(since / BLINK) + 1) * BLINK)
}

// The line an offset lies on: the one holding it, or the one before a cut it falls in.
@(private = "file")
line_of :: proc(spans: []Line_Span, offset: int) -> int {
	for span, i in spans {
		if offset <= span.end do return i
	}
	return max(len(spans) - 1, 0)
}

// Where the caret is drawn on its line, from the line's start.
@(private = "file")
caret_x :: proc(r: ^Renderer, text: string, spans: []Line_Span, line, offset: int) -> f32 {
	if len(spans) == 0 do return 0
	span := spans[line]
	at := clamp(offset, span.start, span.end)
	return text_width(r, text[span.start:at], .Body)
}

// The offset on a line nearest to x from the line's start.
@(private = "file")
offset_on_line :: proc(r: ^Renderer, text: string, span: Line_Span, x: f32) -> int {
	line := text[span.start:span.end]
	return span.start + offset_in(r, line, {0, 0, 1e6, AREA_LINE}, .Body, x, 0)
}

// The offset in text nearest to a point of the window, over the lines as scrolled.
@(private = "file")
offset_at :: proc(
	r: ^Renderer,
	text: string,
	spans: []Line_Span,
	inner: Rect,
	scroll: Scroll,
	p: [2]f32,
) -> int {
	if len(spans) == 0 do return 0
	line := clamp(int((p.y - inner.y + scroll.offset.y) / AREA_LINE), 0, len(spans) - 1)
	return offset_on_line(r, text, spans[line], p.x - inner.x)
}
