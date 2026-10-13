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
	// How much of the input's text had come before it, so that keys and text keep
	// their order.
	text_at:   int,
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
	// A toggle, on or off, rather than a plain button.
	Checkable,
}

Widget_States :: bit_set[Widget_State]

// What a widget declared this frame: the accessibility tree is built from it, and
// tests find widgets by their label in it. Its strings last until the next frame.
Widget_Info :: struct {
	id:        Widget_Id,
	role:      Role,
	label:     string,
	value:     string,
	rect:      Rect,
	states:    Widget_States,
	// What assistive technologies may do to it; declare fills in those of its role.
	actions:   Actions,
	// The group it belongs to, declared by push_parent; 0 for the window.
	parent:    Widget_Id,
	// Tab and Shift+Tab move the focus through these, in the order they are declared.
	focusable: bool,
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
	allocator:       runtime.Allocator,
	input:           Input,
	renderer:        ^Renderer,
	theme:           Theme,
	// The widget under the mouse, from the previous frame, and the one this frame finds.
	hot:             Widget_Id,
	hot_next:        Widget_Id,
	// The layer of the widget that claimed the hover: one on a lower layer, drawn later,
	// does not take it.
	hot_layer:       Layer,
	// The widget the mouse button went down on, until it comes up.
	active:          Widget_Id,
	focus:           Widget_Id,
	// Whether the active and the focused widgets were drawn this frame: one that was not
	// is gone, and loses the mouse or the keyboard.
	active_seen:     bool,
	focus_seen:      bool,
	// The widget the last press went down on, so that a double click needs two presses on
	// the same widget.
	last_press:      Widget_Id,
	// The groups being declared, innermost last.
	parents:         [dynamic]Widget_Id,
	// The focus the frame asked for: nil when it asked nothing, 0 to clear the focus.
	focus_next:      Maybe(Widget_Id),
	// Where the mouse went down, for drags.
	press_mouse:     [2]f32,
	// The focus moved by Tab or Shift+Tab, rather than by the mouse: a text field then
	// selects all its text.
	focus_by_key:    bool,
	// Tab or Shift+Tab pressed in the focused widget, for the end of the frame.
	tab:             Maybe(Tab),
	widgets:         [dynamic]Widget_Info,
	cursor:          Cursor,
	// The text of the focused text field, which owns it, and how far it is scrolled.
	edit:            Text_Edit,
	edit_owner:      Widget_Id,
	// Where a click that asked for a text field's focus was, in its value.
	edit_click:      Maybe(Edit_Click),
	// The value the focused field had when the focus came, for Escape to bring back.
	edit_start:      [dynamic]u8,
	// The field the focus left for another widget's request while it was typed in, and
	// what it held: it commits that when next drawn.
	edit_ended:      Widget_Id,
	edit_ended_text: [dynamic]u8,
	// The focused field reported a commit or a cancel this frame.
	edit_reported:   bool,
	edit_scroll:     f32,
	// When the caret last moved, so that it shows at once and then blinks.
	caret_time:      f64,
	clipboard:       Clipboard,
	// The open popup's rect, from the last frame and for the next: the widgets under it
	// do not take the mouse, whatever their order. Only the popup's own widgets do.
	popup:           Maybe(Rect),
	popup_next:      Maybe(Rect),
	in_popup:        bool,
	popup_layer:     Layer,
	// The scroll area under the mouse along each axis, from the last frame, and the one
	// this frame finds: the innermost that can scroll along it wins, as it is drawn
	// after the one around it.
	scroll_hot:      [2]Widget_Id,
	scroll_hot_next: [2]Widget_Id,
	// What a drag started from: a scroll bar's offset when its thumb was pressed.
	drag_from:       f32,
	// The modal dialog shown last frame, and this frame's: while one is shown, only its
	// widgets take the keys.
	modal:           Widget_Id,
	modal_next:      Widget_Id,
	in_modal:        bool,
	// When the widget under the mouse became so, for tooltips.
	hot_since:       f64,
	// The window's area, in points: overlays stay inside it.
	viewport:        Rect,
	// When the Ui needs a frame without input, a tooltip to show or a caret to blink:
	// the app's loop waits for events until then.
	wake_at:         f64,
	// The context menu open, and its state.
	menu:            Menu_State,
	// The combo box whose suggestions are open, and its list's state.
	combo:           Combo_State,
}

// widgets and the input's lists use allocator.
ui_init :: proc(ui: ^Ui, renderer: ^Renderer, theme: Theme, allocator := context.allocator) {
	ui.allocator = allocator
	ui.renderer = renderer
	ui.theme = theme
	ui.viewport = {0, 0, 1e6, 1e6}
	ui.wake_at = max(f64)
	ui.input.keys = make([dynamic]Key_Press, allocator)
	ui.input.text = strings.builder_make(allocator)
	ui.widgets = make([dynamic]Widget_Info, allocator)
	ui.parents = make([dynamic]Widget_Id, allocator)
	text_edit_init(&ui.edit, allocator)
	ui.edit_start = make([dynamic]u8, allocator)
	ui.edit_ended_text = make([dynamic]u8, allocator)
	ui.combo.filter = make([dynamic]u8, allocator)
}

// Frees what ui_init made.
ui_destroy :: proc(ui: ^Ui) {
	delete(ui.parents)
	delete(ui.input.keys)
	strings.builder_destroy(&ui.input.text)
	delete(ui.widgets)
	text_edit_destroy(&ui.edit)
	delete(ui.edit_start)
	delete(ui.edit_ended_text)
	delete(ui.combo.filter)
	ui^ = {}
}

// Starts a frame drawn at scale pixels per point: the hover found last frame takes
// effect, and the renderer's lists start empty.
ui_begin_frame :: proc(ui: ^Ui, scale: f32) {
	if ui.hot_next != ui.hot do ui.hot_since = ui.input.time
	ui.hot = ui.hot_next
	ui.hot_next = 0
	ui.modal = ui.modal_next
	ui.modal_next = 0
	ui.wake_at = max(f64)
	ui.hot_layer = .Base
	ui.active_seen = false
	ui.focus_seen = false
	if ui.input.lost_focus do ui.active = 0
	ui.popup = ui.popup_next
	ui.popup_next = nil
	ui.scroll_hot = ui.scroll_hot_next
	ui.scroll_hot_next = {}
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
	// Tab moves the focus, unless a widget asked for it this frame.
	if direction, tabbed := ui.tab.?; tabbed && ui.focus_next == nil {
		if next, found := tab_target(ui, direction); found do ui.focus_next = next
	}
	if next, asked := ui.focus_next.?; asked {
		ui.focus_by_key = ui.tab != nil
		ui.focus = next
	}
	ui.focus_next = nil
	ui.tab = nil
	if ui.focus != focus do redraw = true
	// A field typed in lost the focus without saying it was done: it will.
	if focus != 0 && focus == ui.edit_owner && ui.focus != focus && !ui.edit_reported {
		ui.edit_ended = focus
		clear(&ui.edit_ended_text)
		append(&ui.edit_ended_text, edit_text(&ui.edit))
	}
	ui.edit_reported = false
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

// Whether the mouse is over rect and inside the clip drawn into, and not over an open
// popup that rect is not part of.
mouse_over :: proc(ui: ^Ui, rect: Rect) -> bool {
	p := ui.input.mouse
	if !rect_contains(rect, p) do return false
	if !ui.in_popup && mouse_in_popup(ui) do return false
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
	if keys_blocked(ui) do return false
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

// Tab moves the focus forward, Shift+Tab back.
Tab :: enum u8 {
	Forward,
	Back,
}

// Moves the focus to the next focusable widget, or the one before, at the end of the
// frame: Tab or Shift+Tab pressed in the focused widget.
move_focus :: proc(ui: ^Ui, direction: Tab) {
	ui.tab = direction
}

// The focusable widget after the focused one, or before it, wrapping around; the first
// or the last when none has the focus.
@(private = "file")
tab_target :: proc(ui: ^Ui, direction: Tab) -> (target: Widget_Id, found: bool) {
	focusable := make([dynamic]Widget_Id, context.temp_allocator)
	at := -1
	for w in ui.widgets {
		if !w.focusable || (ui.modal != 0 && w.parent != ui.modal) do continue
		if w.id == ui.focus do at = len(focusable)
		append(&focusable, w.id)
	}
	n := len(focusable)
	if n == 0 do return
	step := direction == .Forward ? 1 : -1
	if at < 0 do at = direction == .Forward ? -1 : n
	return focusable[(at + step + n) % n], true
}

// Where a click that asked for a text field's focus was, in that field's value.
Edit_Click :: struct {
	owner:  Widget_Id,
	offset: int,
}

// Starts drawing a popup at rect: a list of suggestions, a menu, a dialog's scrim. Its
// widgets take the mouse before those under it from the next frame on, whatever the
// order they are drawn in, and it is not clipped by what it is drawn in, but for a
// margin around it for its shadow. End it with end_popup.
begin_popup :: proc(ui: ^Ui, rect: Rect, layer := Layer.Overlay) {
	ui.popup_next = rect
	ui.in_popup = true
	ui.popup_layer = set_layer(ui.renderer, layer)
	block_mouse(ui, rect)
	SHADOW_MARGIN :: 64
	push_clip(
		ui.renderer,
		rect_inset(rect, -SHADOW_MARGIN, -SHADOW_MARGIN),
		inside_current = false,
	)
}

// Ends the popup begin_popup started.
end_popup :: proc(ui: ^Ui) {
	pop_clip(ui.renderer)
	ui.in_popup = false
	set_layer(ui.renderer, ui.popup_layer)
}

// Whether the keys belong to a modal dialog the widget drawn now is not part of.
keys_blocked :: proc(ui: ^Ui) -> bool {
	return ui.modal != 0 && !ui.in_modal
}

// Asks for a frame at time at the latest, without input: a tooltip to show, a caret to
// blink.
wake_at :: proc(ui: ^Ui, at: f64) {
	ui.wake_at = min(ui.wake_at, at)
}

// Whether the mouse is over the popup open in the last frame.
mouse_in_popup :: proc(ui: ^Ui) -> bool {
	popup, open := ui.popup.?
	return open && rect_contains(popup, ui.input.mouse)
}
