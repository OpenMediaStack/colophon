package ui

import "core:strings"
import sdl "vendor:sdl3"

// How far one notch of a mouse wheel scrolls.
WHEEL_POINTS :: 40

// Adds what an SDL event says to input, and true when it was input at all. Mouse
// positions are in the window's points, as SDL gives them.
input_from_sdl :: proc(input: ^Input, event: ^sdl.Event) -> bool {
	#partial switch event.type {
	case .MOUSE_MOTION:
		input.mouse = {event.motion.x, event.motion.y}
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		e := event.button
		button, known := mouse_button(e.button)
		if !known do return false
		input.mouse = {e.x, e.y}
		if e.down {
			input.down += {button}
			input.pressed += {button}
			input.clicks = int(e.clicks)
		} else {
			input.down -= {button}
			input.released += {button}
		}
	case .MOUSE_WHEEL:
		e := event.wheel
		flip: f32 = e.direction == .FLIPPED ? -1 : 1
		input.wheel += {e.x * flip, -e.y * flip} * WHEEL_POINTS
		input.mouse = {e.mouse_x, e.mouse_y}
	case .KEY_DOWN:
		e := event.key
		input.modifiers = modifiers_of(e.mod)
		key := key_of(e.key)
		if key != .None do append(&input.keys, Key_Press{key, input.modifiers, e.repeat})
	case .KEY_UP:
		input.modifiers = modifiers_of(event.key.mod)
	case .TEXT_INPUT:
		strings.write_string(&input.text, string(event.text.text))
	case:
		return false
	}
	return true
}

@(private = "file")
mouse_button :: proc(button: u8) -> (Mouse_Button, bool) {
	switch button {
	case sdl.BUTTON_LEFT:
		return .Left, true
	case sdl.BUTTON_MIDDLE:
		return .Middle, true
	case sdl.BUTTON_RIGHT:
		return .Right, true
	}
	return {}, false
}

@(private = "file")
modifiers_of :: proc(mod: sdl.Keymod) -> (m: Modifiers) {
	if mod & sdl.KMOD_SHIFT != {} do m += {.Shift}
	if mod & sdl.KMOD_CTRL != {} do m += {.Control}
	if mod & sdl.KMOD_ALT != {} do m += {.Alt}
	if mod & sdl.KMOD_GUI != {} do m += {.Super}
	return
}

@(private = "file")
key_of :: proc(code: sdl.Keycode) -> Key {
	switch code {
	case sdl.K_A ..= sdl.K_Z:
		return Key(int(Key.A) + int(code - sdl.K_A))
	case sdl.K_0 ..= sdl.K_9:
		return Key(int(Key.Num_0) + int(code - sdl.K_0))
	case sdl.K_F1 ..= sdl.K_F12:
		return Key(int(Key.F1) + int(code - sdl.K_F1))
	case sdl.K_RETURN, sdl.K_KP_ENTER:
		return .Enter
	case sdl.K_ESCAPE:
		return .Escape
	case sdl.K_TAB:
		return .Tab
	case sdl.K_BACKSPACE:
		return .Backspace
	case sdl.K_DELETE:
		return .Delete
	case sdl.K_SPACE:
		return .Space
	case sdl.K_LEFT:
		return .Left
	case sdl.K_RIGHT:
		return .Right
	case sdl.K_UP:
		return .Up
	case sdl.K_DOWN:
		return .Down
	case sdl.K_HOME:
		return .Home
	case sdl.K_END:
		return .End
	case sdl.K_PAGEUP:
		return .Page_Up
	case sdl.K_PAGEDOWN:
		return .Page_Down
	case sdl.K_COMMA:
		return .Comma
	case sdl.K_PERIOD:
		return .Period
	case sdl.K_SLASH:
		return .Slash
	case sdl.K_MINUS:
		return .Minus
	case sdl.K_EQUALS:
		return .Equals
	}
	return .None
}
