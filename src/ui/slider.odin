package ui

import "core:fmt"

// The height of a slider's area, and of its thumb's travel.
SLIDER_HEIGHT :: 16
@(private = "file")
TRACK :: 4
@(private = "file")
THUMB :: 12

// What a scrub reports of the frame.
Scrub_Result :: struct {
	// The new position, from 0 to 1, when the mouse or a key moved it this frame.
	changed:                Maybe(f32),
	hovered, held, focused: bool,
}

// The behaviour of a bar to click or drag along, from 0 to 1, that the caller draws:
// the player's waveform, and slider's track. A click or a drag along it gives the
// position under the mouse, wherever the mouse goes while the button is down, and only
// when it goes; the keyboard reaches it with Tab, and with the focus, Left and Down take
// step off, Right and Up add it, Home gives 0 and End 1. A disabled bar does nothing and
// takes the clicks meant for it. It declares itself to the accessibility tree as a
// slider named label, whose value is its position as a percentage.
scrub :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	label: string,
	position: f32,
	disabled := false,
	step: f32 = 0.05,
) -> (
	result: Scrub_Result,
) {
	value := clamp(position, 0, 1)
	if disabled {
		block_mouse(ui, rect)
		release_focus(ui, id)
	} else {
		interaction := interact(ui, id, rect)
		result.hovered = .Hovered in interaction
		result.held = .Held in interaction
		if result.hovered do ui.cursor = .Pointer
		if rect.w > 0 && (.Pressed in interaction || result.held) {
			moved := clamp((ui.input.mouse.x - rect.x) / rect.w, 0, 1)
			// The press gives where it is; after it, only a mouse that moved gives a new
			// position: a held, still mouse must not ask again for the same one while what
			// the bar shows moves on, as the position of a playing track does.
			if .Pressed in interaction || moved != ui.drag_from do result.changed = moved
			ui.drag_from = moved
		}
		if has_focus(ui, id) {
			result.focused = true
			switch {
			case take_key(ui, .Left, repeats = true), take_key(ui, .Down, repeats = true):
				result.changed = max(value - step, 0)
			case take_key(ui, .Right, repeats = true), take_key(ui, .Up, repeats = true):
				result.changed = min(value + step, 1)
			case take_key(ui, .Home):
				result.changed = 0
			case take_key(ui, .End):
				result.changed = 1
			}
			if take_key(ui, .Tab) do move_focus(ui, .Forward)
			if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
		}
	}
	shown := result.changed.? or_else value
	states: Widget_States = disabled ? {.Disabled} : {}
	if result.focused do states += {.Focused}
	declare(
		ui,
		{
			id = id,
			role = .Slider,
			label = label,
			value = fmt.tprint(int(shown * 100 + 0.5)),
			rect = rect,
			states = states,
			focusable = !disabled,
		},
	)
	return
}

// A bar to click or drag along, from 0 to 1: the player's volume. It behaves as scrub
// does and draws a track, filled up to the position, with a thumb while the mouse is
// over it or the keyboard has it. Gives the new position the frame one of these moved
// it to, nil in the others. A disabled slider is grey.
slider :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	label: string,
	position: f32,
	disabled := false,
	step: f32 = 0.05,
) -> (
	changed: Maybe(f32),
) {
	r := ui.renderer
	th := ui.theme
	result := scrub(ui, id, rect, label, position, disabled, step)
	// What is drawn follows the position the frame ends with, not the one it began with.
	shown := result.changed.? or_else clamp(position, 0, 1)
	track := Rect{rect.x, rect.y + (rect.h - TRACK) / 2, rect.w, TRACK}
	fill_rect(r, track, th.border_strong, TRACK / 2)
	if shown > 0 {
		filled := Rect{track.x, track.y, track.w * shown, track.h}
		fill_rect(r, filled, disabled ? th.text_disabled : th.accent, TRACK / 2)
	}
	if !disabled && (result.hovered || result.held || result.focused) {
		x := rect.x + rect.w * shown - THUMB / 2
		thumb := Rect{x, rect.y + (rect.h - THUMB) / 2, THUMB, THUMB}
		fill_rect(r, thumb, th.text_primary, THUMB / 2)
		if result.focused && ui.focus_by_key do draw_focus_ring(r, th, thumb, THUMB / 2)
	}
	return result.changed
}
