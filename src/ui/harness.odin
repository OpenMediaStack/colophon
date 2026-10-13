package ui

import "base:runtime"
import "core:strings"

// Runs frames of a Ui without a window, with scripted input, for tests: the renderer
// records draw lists that nothing draws. Make it with harness_init, free it with
// harness_destroy; the Ui points into it, so it must not be copied once made.
Harness :: struct {
	renderer:  Renderer,
	ui:        Ui,
	// Draws one frame of what is tested.
	frame:     proc(ui: ^Ui, data: rawptr),
	data:      rawptr,
	scale:     f32,
	// What the Ui copies to its clipboard and pastes from it.
	clipboard: strings.Builder,
}

// Makes a harness that runs frame with data, in the theme of kind.
harness_init :: proc(
	h: ^Harness,
	frame: proc(ui: ^Ui, data: rawptr),
	data: rawptr = nil,
	kind := Theme_Kind.Dark,
	allocator := context.allocator,
) {
	renderer_init(&h.renderer, allocator)
	ui_init(&h.ui, &h.renderer, theme(kind), allocator)
	h.frame = frame
	h.data = data
	h.scale = 1
	h.clipboard = strings.builder_make(allocator)
	h.ui.clipboard = {
		data = &h.clipboard,
		get = proc(data: rawptr, allocator: runtime.Allocator) -> string {
			return strings.clone(strings.to_string((^strings.Builder)(data)^), allocator)
		},
		set = proc(data: rawptr, text: string) {
			b := (^strings.Builder)(data)
			strings.builder_reset(b)
			strings.write_string(b, text)
		},
	}
}

// Frees what harness_init made.
harness_destroy :: proc(h: ^Harness) {
	strings.builder_destroy(&h.clipboard)
	ui_destroy(&h.ui)
	renderer_destroy(&h.renderer)
}

// Runs one frame with the input given so far.
run_frame :: proc(h: ^Harness) {
	ui_begin_frame(&h.ui, h.scale)
	h.frame(&h.ui, h.data)
	ui_end_frame(&h.ui)
}

// The middle of the widget labelled label in the last frame; false when there is none.
widget_center :: proc(h: ^Harness, label: string) -> (center: [2]f32, found: bool) {
	info := find_widget(&h.ui, label) or_return
	return rect_center(info.rect), true
}

// Moves the mouse to p, and runs two frames: hover takes a frame to settle.
move_mouse :: proc(h: ^Harness, p: [2]f32) {
	h.ui.input.mouse = p
	run_frame(h)
	run_frame(h)
}

// Clicks the widget labelled label, clicks times in a row: the mouse moves onto it,
// then each click presses and releases the button over two frames. false when no
// widget has that label.
click :: proc(h: ^Harness, label: string, button := Mouse_Button.Left, clicks := 1) -> bool {
	p := widget_center(h, label) or_return
	move_mouse(h, p)
	for i in 1 ..= clicks {
		press(h, button, i)
		release(h, button)
	}
	return true
}

// Presses a mouse button where the mouse is, as the clicks-th click in a row, and runs
// a frame.
press :: proc(h: ^Harness, button := Mouse_Button.Left, clicks := 1) {
	h.ui.input.down += {button}
	h.ui.input.pressed += {button}
	h.ui.input.clicks = clicks
	run_frame(h)
}

// Releases a mouse button where the mouse is, and runs a frame.
release :: proc(h: ^Harness, button := Mouse_Button.Left) {
	h.ui.input.down -= {button}
	h.ui.input.released += {button}
	run_frame(h)
}

// Presses a key with modifiers, and runs a frame.
press_key :: proc(h: ^Harness, key: Key, modifiers := Modifiers{}) {
	append(&h.ui.input.keys, Key_Press{key, modifiers, false})
	run_frame(h)
}

// Lets time pass, as the caret's blink sees it.
wait :: proc(h: ^Harness, seconds: f64) {
	h.ui.input.time += seconds
	run_frame(h)
}

// Types text, and runs a frame.
type_text :: proc(h: ^Harness, text: string) {
	strings.write_string(&h.ui.input.text, text)
	run_frame(h)
}
