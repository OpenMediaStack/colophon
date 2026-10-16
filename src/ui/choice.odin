package ui

// A box to tick with its label beside it, as wide as rect. True when it was toggled,
// by a click or by Space while it had the focus.
checkbox :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	label: string,
	checked: bool,
	disabled := false,
) -> (
	toggled: bool,
) {
	states: Button_States
	if checked do states += {.Checked}
	if disabled {
		states += {.Disabled}
		// It still takes the clicks meant for it, which must not reach what lies under it.
		block_mouse(ui, rect)
		release_focus(ui, id)
	} else {
		interaction := interact(ui, id, rect)
		if .Hovered in interaction {
			states += {.Hovered}
			ui.cursor = .Pointer
		}
		toggled = .Clicked in interaction
		if has_focus(ui, id) {
			states += {.Focused}
			if take_key(ui, .Space) do toggled = true
			if take_key(ui, .Tab) do move_focus(ui, .Forward)
			if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
		}
	}
	draw_checkbox(ui.renderer, ui.theme, rect, label, states)
	declare(
		ui,
		{
			id = id,
			role = .Check_Box,
			label = label,
			rect = rect,
			states = widget_states(states) + {.Checkable},
			focusable = !disabled,
		},
	)
	return
}

// Draws a checkbox in states, without the Ui.
draw_checkbox :: proc(r: ^Renderer, th: Theme, rect: Rect, label: string, states: Button_States) {
	BOX :: 16
	box := Rect{rect.x, rect.y + f32(int((rect.h - BOX) / 2)), BOX, BOX}
	checked := .Checked in states
	disabled := .Disabled in states
	hovered := .Hovered in states && !disabled
	switch {
	case checked && disabled:
		fill_rect(r, box, th.surface_3, 4)
	case checked:
		fill_rect(r, box, hovered ? th.accent_hover : th.accent, 4)
	case:
		fill_rect(r, box, th.surface_1, 4)
		border := hovered ? th.text_tertiary : th.border_strong
		if disabled do border = th.border_subtle
		stroke_rect(r, box, border, 4)
	}
	if checked {
		draw_icon_centered(r, .Check, box, disabled ? th.text_disabled : th.on_accent, 12)
	}
	if .Focused in states && !disabled do draw_focus_ring(r, th, box, 4)
	color := disabled ? th.text_disabled : th.text_primary
	draw_text_fit(r, label, box.x + BOX + 8, rect.y + rect.h / 2, rect.w - BOX - 8, .Body, color)
}

// One choice of a segmented control.
Segment :: struct {
	label:   string,
	// Numbers that line up, such as versions: JetBrains Mono.
	numeric: bool,
}

// A row of choices, one of them selected, or none while the selection mixes several:
// the tag versions of the inspector, the write policy of the settings. Gives the
// choice clicked, or picked with the arrow keys while it had the focus. The segments
// share the width equally, or by the length of their labels when fit_labels, for
// labels of very different lengths, which are then smaller.
segmented :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	label: string,
	segments: []Segment,
	selected: Maybe(int),
	disabled := false,
	fit_labels := false,
) -> (
	chosen: Maybe(int),
) {
	r := ui.renderer
	th := ui.theme
	fill_rect(r, rect, disabled ? th.surface_1 : th.surface_2, 4)
	stroke_rect(r, rect, disabled ? th.border_subtle : th.border_strong, 4)
	focused := has_focus(ui, id) && !disabled
	if disabled do release_focus(ui, id)
	if focused && len(segments) > 0 {
		current := selected.? or_else -1
		if take_key(ui, .Left) do chosen = max(current - 1, 0)
		if take_key(ui, .Right) do chosen = min(current + 1, len(segments) - 1)
		if take_key(ui, .Tab) do move_focus(ui, .Forward)
		if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
	}
	// The ring shows when the focus came by the keyboard: a click chooses, and leaves
	// the arrow keys to move on from there.
	if focused && ui.focus_by_key do draw_focus_ring(r, th, rect, 4)
	declare(
		ui,
		{
			id = id,
			role = .Group,
			label = label,
			rect = rect,
			states = disabled ? {.Disabled} : {},
			focusable = !disabled,
		},
	)
	push_parent(ui, id)
	defer pop_parent(ui)
	inner := rect_inset(rect, 2, 2)
	widths := segment_widths(r, segments, inner.w, fit_labels)
	x := inner.x
	for segment, i in segments {
		cell := Rect{x, inner.y, widths[i], inner.h}
		x += widths[i] + SEGMENT_GAP
		cell_id := child_id(id, "segment", i)
		is_selected := selected == i
		hovered := false
		if !disabled {
			interaction := interact(ui, cell_id, cell)
			hovered = .Hovered in interaction
			if hovered do ui.cursor = .Pointer
			if .Clicked in interaction {
				chosen = i
				request_focus(ui, id)
			}
		}
		switch {
		case is_selected:
			fill_rect(r, cell, th.surface_3, 3)
		case hovered:
			fill_rect(r, cell, th.border_subtle, 3)
		}
		style := segment_style(segment, is_selected, fit_labels)
		color := is_selected ? th.text_primary : th.text_secondary
		if disabled do color = th.text_disabled
		draw_text_fit(
			r,
			segment.label,
			cell.x + 2,
			cell.y + cell.h / 2,
			cell.w - 4,
			style,
			color,
			.Center,
		)
		states: Widget_States = {.Checkable}
		if is_selected do states += {.Checked}
		if hovered do states += {.Hovered}
		if disabled do states += {.Disabled}
		declare(
			ui,
			{
				id = cell_id,
				role = .Radio_Button,
				label = segment.label,
				rect = cell,
				states = states,
			},
		)
	}
	if chosen == selected do chosen = nil
	return
}

@(private = "file")
SEGMENT_GAP :: 2

// The widths of the segments in width: equal shares, or when fit_labels each label's
// own width and an equal share of what is left, as 1.0.0's fit-labels.
@(private = "file")
segment_widths :: proc(r: ^Renderer, segments: []Segment, width: f32, fit_labels: bool) -> []f32 {
	widths := make([]f32, len(segments), context.temp_allocator)
	if len(segments) == 0 do return widths
	spare := width - SEGMENT_GAP * f32(len(segments) - 1)
	if fit_labels {
		for segment, i in segments {
			widths[i] = text_width(r, segment.label, segment_style(segment, false, true)) + 6
			spare -= widths[i]
		}
	}
	for &w in widths do w += spare / f32(len(segments))
	return widths
}

// Numbers in JetBrains Mono, words in Inter, smaller when the labels set the widths, and
// medium for the selected segment.
@(private = "file")
segment_style :: proc(segment: Segment, selected, fit_labels: bool) -> Text_Style {
	switch {
	case segment.numeric:
		return selected ? .Numeric_Strong : .Numeric
	case fit_labels:
		return selected ? .Small_Strong : .Small
	}
	return selected ? .Body_Strong : .Body
}
