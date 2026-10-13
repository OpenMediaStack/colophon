package ui

import "base:runtime"
import "core:strings"

// A widget's identity across frames: a hash of a name and an index, so that a widget
// drawn again on the next frame has the same id. Never 0, which means no widget.
Widget_Id :: distinct u64

// A mouse button. On macOS, a Control click is a right click.
Mouse_Button :: enum u8 {
	Left,
	Middle,
	Right,
}

Mouse_Buttons :: bit_set[Mouse_Button]

// A key held with another key or a click.
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

// A key pressed, with the modifiers held.
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
	mouse:      [2]f32,
	down:       Mouse_Buttons,
	pressed:    Mouse_Buttons,
	released:   Mouse_Buttons,
	// How many clicks the last press made: 2 for a double click.
	clicks:     int,
	// In points, positive to the right and down.
	wheel:      [2]f32,
	keys:       [dynamic]Key_Press,
	// The text typed, in UTF-8.
	text:       strings.Builder,
	modifiers:  Modifiers,
	// In seconds, from any start.
	time:       f64,
	// What changed this frame, so that a button that changes after a move, or twice,
	// waits for the next frame: each frame sees one change of each.
	moved:      bool,
	changed:    Mouse_Buttons,
	// The window lost the focus: the active widget ends without a click.
	lost_focus: bool,
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

// What a widget is going through, for the accessibility tree and for tests.
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
	id:      Widget_Id,
	role:    Role,
	label:   string,
	value:   string,
	rect:    Rect,
	states:  Widget_States,
	// What assistive technologies may do to it; declare fills in those of its role.
	actions: Actions,
	// The group it belongs to, declared by push_parent; 0 for the window.
	parent:  Widget_Id,
}

// What assistive technologies may do to a widget.
Action :: enum u8 {
	Press,
	Focus,
	Set_Value,
	Increment,
	Decrement,
	Scroll_Into_View,
}

Actions :: bit_set[Action]

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
// drawn on the highest layer wins, so an overlay takes the mouse from what lies under
// it. A widget that is not drawn in a frame loses the mouse and the keyboard. The
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
	// The layer of the widget that claimed the hover: one on a lower layer, drawn later,
	// does not take it.
	hot_layer:   Layer,
	// The widget the mouse button went down on, until it comes up.
	active:      Widget_Id,
	focus:       Widget_Id,
	// Whether the active and the focused widgets were drawn this frame: one that was not
	// is gone, and loses the mouse or the keyboard.
	active_seen: bool,
	focus_seen:  bool,
	// The widget the last press went down on, so that a double click needs two presses on
	// the same widget.
	last_press:  Widget_Id,
	// The groups being declared, innermost last.
	parents:     [dynamic]Widget_Id,
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
	ui.parents = make([dynamic]Widget_Id, allocator)
}

// Frees what ui_init made.
ui_destroy :: proc(ui: ^Ui) {
	delete(ui.parents)
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
	ui.hot_layer = .Base
	ui.active_seen = false
	ui.focus_seen = false
	if ui.input.lost_focus do ui.active = 0
	ui.cursor = .Default
	clear(&ui.widgets)
	renderer_begin_frame(ui.renderer, scale)
}

// Ends a frame: a released button ends the active widget, the focus the frame asked
// for takes effect, a widget that was not drawn loses the mouse and the keyboard, and
// the input of the frame is emptied. redraw is true when the hover or the focus moved:
// the next frame should come at once rather than wait for input.
ui_end_frame :: proc(ui: ^Ui) -> (redraw: bool) {
	in_ := &ui.input
	if .Left not_in in_.down || !ui.active_seen do ui.active = 0
	if !ui.focus_seen do ui.focus = 0
	focus := ui.focus
	redraw = ui.hot_next != ui.hot
	if next, asked := ui.focus_next.?; asked do ui.focus = next
	ui.focus_next = nil
	if ui.focus != focus do redraw = true
	in_.pressed = {}
	in_.released = {}
	in_.clicks = 0
	in_.wheel = {}
	in_.moved = false
	in_.changed = {}
	in_.lost_focus = false
	clear(&in_.keys)
	strings.builder_reset(&in_.text)
	return
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

// What the mouse did to a widget this frame: Interaction holds them.
Interaction_Flag :: enum u8 {
	// The mouse is over it, and no other widget is active.
	Hovered,
	// The left button went down on it: it is active until the button comes up.
	Pressed,
	// The press was the second of a double click on this widget, or a later one: the
	// input's clicks say how many.
	Double_Clicked,
	// The left button came up over it, after going down on it.
	Clicked,
	// It is active: the left button went down on it and is still down.
	Held,
	// The right button went down on it.
	Right_Clicked,
}

// What the mouse did to a widget this frame.
Interaction :: bit_set[Interaction_Flag]

// The mouse on the widget id drawn at rect.
interact :: proc(ui: ^Ui, id: Widget_Id, rect: Rect) -> (result: Interaction) {
	in_ := &ui.input
	seen(ui, id)
	over := mouse_over(ui, rect)
	if over do claim_hover(ui, id)
	if over && ui.hot == id && (ui.active == 0 || ui.active == id) do result += {.Hovered}
	if .Hovered in result {
		if .Left in in_.pressed {
			if in_.clicks >= 2 && ui.last_press == id do result += {.Double_Clicked}
			ui.active = id
			ui.active_seen = true
			ui.last_press = id
			ui.press_mouse = in_.mouse
			result += {.Pressed}
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
	if mouse_over(ui, rect) do claim_hover(ui, widget_id("block"))
}

// Claims the hover for the next frame, unless a widget on a higher layer did.
@(private = "file")
claim_hover :: proc(ui: ^Ui, id: Widget_Id) {
	layer := ui.renderer.layer
	if layer < ui.hot_layer do return
	ui.hot_next = id
	ui.hot_layer = layer
}

// Notes that the focused or the active widget was drawn this frame.
@(private = "file")
seen :: proc(ui: ^Ui, id: Widget_Id) {
	if id == 0 do return
	if id == ui.focus do ui.focus_seen = true
	if id == ui.active do ui.active_seen = true
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

// Whether id has the keyboard focus.
has_focus :: proc(ui: ^Ui, id: Widget_Id) -> bool {
	seen(ui, id)
	return ui.focus == id && id != 0
}

// Whether key was pressed with exactly these modifiers this frame; a key held down and
// repeated by the system counts only when repeats, for moves rather than actions. The
// press is taken: the widgets drawn after it, and the shortcuts handled at the end of
// the frame, do not see it.
take_key :: proc(ui: ^Ui, key: Key, modifiers := Modifiers{}, repeats := false) -> bool {
	for press, i in ui.input.keys {
		if press.key != key || press.modifiers != modifiers || (press.repeat && !repeats) do continue
		ordered_remove(&ui.input.keys, i)
		return true
	}
	return false
}

// Tells the Ui what a widget is, for the accessibility tree and for tests: the actions
// of its role unless it names its own, and the group being declared as its parent.
// label and value must last until the next frame.
declare :: proc(ui: ^Ui, info: Widget_Info) {
	seen(ui, info.id)
	info := info
	if info.actions == {} do info.actions = ROLE_ACTIONS[info.role]
	if info.parent == 0 && len(ui.parents) > 0 do info.parent = ui.parents[len(ui.parents) - 1]
	append(&ui.widgets, info)
}

// What assistive technologies may do to each role of widget.
@(rodata)
ROLE_ACTIONS := [Role]Actions {
	.Group        = {},
	.Label        = {},
	.Button       = {.Press, .Focus},
	.Text_Field   = {.Focus, .Set_Value},
	.Check_Box    = {.Press, .Focus},
	.Radio_Button = {.Press},
	.Combo_Box    = {.Focus, .Set_Value},
	.Menu_Item    = {.Press},
	.Table        = {.Focus},
	.Row          = {.Press, .Scroll_Into_View},
	.Cell         = {.Press},
	.Slider       = {.Increment, .Decrement, .Set_Value},
	.Image        = {},
}

// Declares the widgets drawn until pop_parent as children of id: a list, a dialog.
push_parent :: proc(ui: ^Ui, id: Widget_Id) {
	append(&ui.parents, id)
}

pop_parent :: proc(ui: ^Ui) {
	pop(&ui.parents)
}

// The widget declared with label in the last frame.
find_widget :: proc(ui: ^Ui, label: string) -> (info: Widget_Info, found: bool) {
	for w in ui.widgets do if w.label == label do return w, true
	return
}
