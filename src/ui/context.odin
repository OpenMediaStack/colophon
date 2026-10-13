package ui

import "base:runtime"
import "core:strings"

// A widget's identity across frames: a hash of a name and an index, so that a widget
// drawn again on the next frame has the same id. Never 0, which means no widget.
Widget_Id :: distinct u64

Mouse_Button :: enum u8 {
	Left,
	Middle,
	Right,
}

Mouse_Buttons :: bit_set[Mouse_Button]

Modifier :: enum u8 {
	Shift,
	Control,
	Alt,
	// Command on macOS, the Windows key elsewhere.
	Super,
}

Modifiers :: bit_set[Modifier]

// The platform's command modifier: Command on macOS, Control elsewhere.
COMMAND :: Modifiers{.Super} when ODIN_OS == .Darwin else Modifiers{.Control}

// The keys widgets and shortcuts react to; text arrives as typed text, not as keys.
Key :: enum u8 {
	None,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	Num_0,
	Num_1,
	Num_2,
	Num_3,
	Num_4,
	Num_5,
	Num_6,
	Num_7,
	Num_8,
	Num_9,
	Enter,
	Escape,
	Tab,
	Backspace,
	Delete,
	Space,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	Comma,
	Period,
	Slash,
	Minus,
	Equals,
}

Key_Press :: struct {
	key:       Key,
	modifiers: Modifiers,
	// Held down: the system repeats it.
	repeat:    bool,
}

// What the user did since the last frame. The app fills it from the system's events,
// and tests from a script; ui_end_frame empties what only lasts one frame.
Input :: struct {
	// In points, from the window's top left corner.
	mouse:     [2]f32,
	down:      Mouse_Buttons,
	pressed:   Mouse_Buttons,
	released:  Mouse_Buttons,
	// How many clicks the last press made: 2 for a double click.
	clicks:    int,
	// In points, positive to the right and down.
	wheel:     [2]f32,
	keys:      [dynamic]Key_Press,
	// The text typed, in UTF-8.
	text:      strings.Builder,
	modifiers: Modifiers,
	// In seconds, from any start.
	time:      f64,
}

// What a widget is, for the accessibility tree and for tests.
Role :: enum u8 {
	Group,
	Label,
	Button,
	Text_Field,
	Check_Box,
	Radio_Button,
	Combo_Box,
	Menu_Item,
	Table,
	Row,
	Cell,
	Slider,
	Image,
}

Widget_State :: enum u8 {
	Hovered,
	Pressed,
	Focused,
	Disabled,
	Selected,
	Checked,
}

Widget_States :: bit_set[Widget_State]

// What a widget declared this frame: the accessibility tree is built from it, and
// tests find widgets by their label in it. Its strings last until the next frame.
Widget_Info :: struct {
	id:     Widget_Id,
	role:   Role,
	label:  string,
	value:  string,
	rect:   Rect,
	states: Widget_States,
}

// The mouse pointer's shape the frame asks for.
Cursor :: enum u8 {
	Default,
	Pointer,
	Text,
	Resize_Horizontal,
	Resize_Vertical,
	Grab,
	Grabbing,
}

// The immediate mode context every widget gets. Hover is resolved from the previous
// frame: every widget under the mouse claims it for the next frame and the last one
// drawn wins, so an overlay drawn last takes the mouse from what lies under it. The
// widget pressed stays active until the button is released, and the others do not
// react meanwhile. Keyboard focus moves only between frames. Make it with ui_init,
// free it with ui_destroy.
Ui :: struct {
	allocator:   runtime.Allocator,
	input:       Input,
	renderer:    ^Renderer,
	theme:       Theme,
	// The widget under the mouse, from the previous frame, and the one this frame finds.
	hot:         Widget_Id,
	hot_next:    Widget_Id,
	// The widget the mouse button went down on, until it comes up.
	active:      Widget_Id,
	focus:       Widget_Id,
	// The focus the frame asked for: nil when it asked nothing, 0 to clear the focus.
	focus_next:  Maybe(Widget_Id),
	// Where the mouse went down, for drags.
	press_mouse: [2]f32,
	widgets:     [dynamic]Widget_Info,
	cursor:      Cursor,
}

// widgets and the input's lists use allocator.
ui_init :: proc(ui: ^Ui, renderer: ^Renderer, theme: Theme, allocator := context.allocator) {
	ui.allocator = allocator
	ui.renderer = renderer
	ui.theme = theme
	ui.input.keys = make([dynamic]Key_Press, allocator)
	ui.input.text = strings.builder_make(allocator)
	ui.widgets = make([dynamic]Widget_Info, allocator)
}

ui_destroy :: proc(ui: ^Ui) {
	delete(ui.input.keys)
	strings.builder_destroy(&ui.input.text)
	delete(ui.widgets)
	ui^ = {}
}

// Starts a frame drawn at scale pixels per point: the hover found last frame takes
// effect, and the renderer's lists start empty.
ui_begin_frame :: proc(ui: ^Ui, scale: f32) {
	ui.hot = ui.hot_next
	ui.hot_next = 0
	ui.cursor = .Default
	clear(&ui.widgets)
	renderer_begin_frame(ui.renderer, scale)
}

// Ends a frame: a released button ends the active widget, the focus the frame asked
// for takes effect, and the input of the frame is emptied.
ui_end_frame :: proc(ui: ^Ui) {
	in_ := &ui.input
	if .Left in in_.released || in_.down == {} do ui.active = 0
	if next, asked := ui.focus_next.?; asked do ui.focus = next
	ui.focus_next = nil
	in_.pressed = {}
	in_.released = {}
	in_.clicks = 0
	in_.wheel = {}
	clear(&in_.keys)
	strings.builder_reset(&in_.text)
}

// The id of a widget named name, the index-th of its kind.
widget_id :: proc "contextless" (name: string, index := 0) -> Widget_Id {
	return child_id(0, name, index)
}

// The id of a widget inside another, such as a table's cell.
child_id :: proc "contextless" (parent: Widget_Id, name: string, index := 0) -> Widget_Id {
	// FNV-1a over the parent, the name and the index.
	h := u64(0xcbf29ce484222325) ~ u64(parent) * 0x9E3779B97F4A7C15
	for b in transmute([]u8)name do h = (h ~ u64(b)) * 0x100000001b3
	h = (h ~ u64(index)) * 0x100000001b3
	return Widget_Id(h | 1)
}

// Whether the mouse is over rect and inside the clip drawn into.
mouse_over :: proc(ui: ^Ui, rect: Rect) -> bool {
	p := ui.input.mouse
	if !rect_contains(rect, p) do return false
	if clip, clipped := current_clip(ui.renderer); clipped && !rect_contains(clip, p) do return false
	return true
}

// What the mouse did to a widget this frame.
Interaction_Flag :: enum u8 {
	// The mouse is over it, and no other widget is active.
	Hovered,
	// The left button went down on it: it is active until the button comes up.
	Pressed,
	// The press was the second of a double click.
	Double_Clicked,
	// The left button came up over it, after going down on it.
	Clicked,
	// It is active: the left button went down on it and is still down.
	Held,
	// The right button went down on it.
	Right_Clicked,
}

Interaction :: bit_set[Interaction_Flag]

// The mouse on the widget id drawn at rect.
interact :: proc(ui: ^Ui, id: Widget_Id, rect: Rect) -> (result: Interaction) {
	in_ := &ui.input
	over := mouse_over(ui, rect)
	if over do ui.hot_next = id
	if over && ui.hot == id && (ui.active == 0 || ui.active == id) do result += {.Hovered}
	if .Hovered in result {
		if .Left in in_.pressed {
			ui.active = id
			ui.press_mouse = in_.mouse
			result += {.Pressed}
			if in_.clicks >= 2 do result += {.Double_Clicked}
		}
		if .Right in in_.pressed do result += {.Right_Clicked}
	}
	if ui.active == id {
		result += {.Held}
		if .Left in in_.released && over do result += {.Clicked}
	}
	return
}

// Takes the mouse over rect, so that the widgets under it do not react: an overlay's
// background, a dialog's scrim.
block_mouse :: proc(ui: ^Ui, rect: Rect) {
	if mouse_over(ui, rect) do ui.hot_next = widget_id("block")
}

// Moves the keyboard focus to id at the end of the frame.
request_focus :: proc(ui: ^Ui, id: Widget_Id) {
	ui.focus_next = id
}

// Clears the focus at the end of the frame, if id has it and no widget asked for it
// in this frame: a field losing the focus never cancels another's request, whatever
// the order they are drawn in.
release_focus :: proc(ui: ^Ui, id: Widget_Id) {
	if ui.focus != id do return
	if next, asked := ui.focus_next.?; asked && next != id do return
	ui.focus_next = Widget_Id(0)
}

has_focus :: proc(ui: ^Ui, id: Widget_Id) -> bool {
	return ui.focus == id && id != 0
}

// Whether key was pressed with exactly these modifiers this frame. The press is taken:
// the widgets drawn after it, and the shortcuts handled at the end of the frame, do
// not see it.
take_key :: proc(ui: ^Ui, key: Key, modifiers := Modifiers{}) -> bool {
	for press, i in ui.input.keys {
		if press.key != key || press.modifiers != modifiers do continue
		ordered_remove(&ui.input.keys, i)
		return true
	}
	return false
}

// Tells the Ui what a widget is, for the accessibility tree and for tests. label and
// value must last until the next frame.
declare :: proc(ui: ^Ui, info: Widget_Info) {
	append(&ui.widgets, info)
}

// The widget declared with label in the last frame.
find_widget :: proc(ui: ^Ui, label: string) -> (info: Widget_Info, found: bool) {
	for w in ui.widgets do if w.label == label do return w, true
	return
}
