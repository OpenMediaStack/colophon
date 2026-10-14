package ui

import "core:strings"
import sdl "vendor:sdl3"

// How far one notch of a mouse wheel scrolls.
WHEEL_POINTS :: 40

// What input_from_sdl did with an event.
Event_Use :: enum u8 {
	// Not input: a window or a system event, left to the app.
	Other,
	// Added to the input of this frame.
	Taken,
	// A button that changes after the mouse moved, or a second change of a button, in
	// this frame: keep the event for the next frame, so that each frame sees one change
	// and the hover has settled where the click is.
	Wait,
}

// Adds what an SDL event says to input. SDL gives mouse positions in points on macOS
// and Wayland but in pixels on Windows and X11: points_per_unit, which is the window's
// pixel density divided by its display scale, turns them into points.
input_from_sdl :: proc(input: ^Input, event: ^sdl.Event, points_per_unit: f32 = 1) -> Event_Use {
	#partial switch event.type {
	case .MOUSE_MOTION:
		if input.changed != {} do return .Wait
		input.mouse = {event.motion.x, event.motion.y} * points_per_unit
		input.moved = true
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		e := event.button
		button, known := mouse_button(e.button)
		if !known do return .Other
		input.modifiers = modifiers_of(sdl.GetModState())
		// A Control click is a right click on macOS.
		if ODIN_OS == .Darwin && button == .Left && .Control in input.modifiers {
			button = .Right
			input.modifiers -= {.Control}
		}
		if input.moved || button in input.changed do return .Wait
		input.mouse = [2]f32{e.x, e.y} * points_per_unit
		input.changed += {button}
		if e.down {
			input.down += {button}
			input.pressed += {button}
			input.clicks = int(e.clicks)
		} else {
			input.down -= {button}
			input.released += {button}
		}
	case .MOUSE_WHEEL:
		// SDL gives the direction the user set, natural scrolling included.
		e := event.wheel
		input.wheel += {e.x, -e.y} * WHEEL_POINTS
		input.mouse = {e.mouse_x, e.mouse_y} * points_per_unit
	case .KEY_DOWN:
		e := event.key
		input.modifiers = modifiers_of(e.mod)
		key := key_of(e.key)
		if key != .None do append(&input.keys, Key_Press{key, input.modifiers, e.repeat, len(input.text.buf)})
	case .KEY_UP:
		input.modifiers = modifiers_of(event.key.mod)
	case .TEXT_INPUT:
		strings.write_string(&input.text, string(event.text.text))
	case .WINDOW_MOUSE_LEAVE:
		// The pointer is gone: nothing is under it, unless a drag holds a button.
		if input.down == {} do input.mouse = OUTSIDE
		return .Other
	case .WINDOW_FOCUS_LOST:
		// Another window may take the release: the buttons count as up, without a click.
		input.down = {}
		input.lost_focus = true
		return .Other
	case:
		return .Other
	}
	return .Taken
}

// Where the mouse is when it is not over the window.
OUTSIDE :: [2]f32{-1e6, -1e6}

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
