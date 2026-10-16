package ui

import "core:fmt"

// The height of a slider's area, and of its thumb's travel.
SLIDER_HEIGHT :: 16
@(private = "file")
TRACK :: 4
@(private = "file")
THUMB :: 12

// A bar to click or drag along, from 0 to 1: the player's volume, and where it is in a
// track. A click or a drag along it gives the value under the mouse, wherever the
// mouse goes while the button is down; with the focus, Left and Down take step off,
// Right and Up add it, Home gives 0 and End 1. Gives the new value the frame one of
// these moved it to, nil in the others. A disabled slider is grey and does nothing.
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
	value := clamp(position, 0, 1)
	hovered, held, focused := false, false, false
	if disabled {
		block_mouse(ui, rect)
		release_focus(ui, id)
	} else {
		interaction := interact(ui, id, rect)
		hovered = .Hovered in interaction
		held = .Held in interaction
		if hovered do ui.cursor = .Pointer
		if rect.w > 0 && (.Pressed in interaction || held) {
			moved := clamp((ui.input.mouse.x - rect.x) / rect.w, 0, 1)
			// The press gives where it is; after it, only a mouse that moved gives a new
			// position: a held, still mouse must not ask again for the same one while what
			// the bar shows moves on, as the position of a playing track does.
			if .Pressed in interaction || moved != ui.drag_from do changed = moved
			ui.drag_from = moved
		}
		if has_focus(ui, id) {
			focused = true
			switch {
			case take_key(ui, .Left, repeats = true), take_key(ui, .Down, repeats = true):
				changed = max(value - step, 0)
			case take_key(ui, .Right, repeats = true), take_key(ui, .Up, repeats = true):
				changed = min(value + step, 1)
			case take_key(ui, .Home):
				changed = 0
			case take_key(ui, .End):
				changed = 1
			}
			if take_key(ui, .Tab) do move_focus(ui, .Forward)
			if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
		}
	}
	// What is drawn follows the value the frame ends with, not the one it began with.
	shown := changed.? or_else value
	track := Rect{rect.x, rect.y + (rect.h - TRACK) / 2, rect.w, TRACK}
	fill_rect(r, track, th.border_strong, TRACK / 2)
	if shown > 0 {
		filled := Rect{track.x, track.y, track.w * shown, track.h}
		fill_rect(r, filled, disabled ? th.text_disabled : th.accent, TRACK / 2)
	}
	if !disabled && (hovered || held || focused) {
		x := rect.x + rect.w * shown - THUMB / 2
		thumb := Rect{x, rect.y + (rect.h - THUMB) / 2, THUMB, THUMB}
		fill_rect(r, thumb, th.text_primary, THUMB / 2)
		if focused && ui.focus_by_key do draw_focus_ring(r, th, thumb, THUMB / 2)
	}
	states: Widget_States = disabled ? {.Disabled} : {}
	if focused do states += {.Focused}
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
