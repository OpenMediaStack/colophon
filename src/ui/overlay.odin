package ui

// How long the mouse rests on a widget before its tooltip shows, in seconds.
TOOLTIP_DELAY :: 0.6

// A tooltip under rect, once the mouse has rested on the widget id for a moment and no
// button is down: the label of a toolbar button, a shortcut.
tooltip :: proc(ui: ^Ui, id: Widget_Id, rect: Rect, text: string) {
	if ui.hot != id || ui.input.down != {} || len(text) == 0 do return
	shown_at := ui.hot_since + TOOLTIP_DELAY
	if ui.input.time < shown_at {
		wake_at(ui, shown_at)
		return
	}
	r := ui.renderer
	th := ui.theme
	size := [2]f32{text_width(r, text, .Small) + 16, 24}
	at := [2]f32{rect.x + rect.w / 2 - size.x / 2, rect.y + rect.h + 6}
	// Above the widget when there is no room under it.
	if at.y + size.y > ui.viewport.y + ui.viewport.h do at.y = rect.y - 6 - size.y
	box := keep_inside(ui, {at.x, at.y, size.x, size.y})
	previous := set_layer(r, .Top)
	defer set_layer(r, previous)
	push_clip(r, rect_inset(box, -32, -32), inside_current = false)
	defer pop_clip(r)
	draw_shadow(r, box, 4, 4, 12, th.shadow_menu)
	fill_rect(r, box, th.surface_2, 4)
	stroke_rect(r, box, th.border_strong, 4)
	draw_text(r, text, box.x + 8, box.y + box.h / 2, .Small, th.text_primary)
}

// One line of a context menu.
Menu_Item :: struct {
	label:     string,
	// The shortcut that does the same, as each platform writes it.
	shortcut:  string,
	disabled:  bool,
	// A line before it, between groups of items.
	separator: bool,
}

// The context menu open, at most one at a time.
Menu_State :: struct {
	owner:       Widget_Id,
	open:        bool,
	at:          [2]f32,
	// The item the arrow keys reached; -1 for none.
	highlighted: int,
}

@(private = "file")
MENU_ITEM_HEIGHT :: 26
@(private = "file")
MENU_INSET :: 4
@(private = "file")
MENU_SEPARATOR :: 9
@(private = "file")
MENU_MIN_WIDTH :: 180

// Opens the context menu id at a point, a right click's.
open_menu :: proc(ui: ^Ui, id: Widget_Id, at: [2]f32) {
	ui.menu = {
		owner       = id,
		open        = true,
		at          = at,
		highlighted = -1,
	}
}

close_menu :: proc(ui: ^Ui) {
	ui.menu.open = false
}

is_menu_open :: proc(ui: ^Ui, id: Widget_Id) -> bool {
	return ui.menu.open && ui.menu.owner == id
}

// The context menu id, drawn while it is open, which is drawn on Linux and wherever
// the system has none. Gives the item chosen by a click or by the arrow keys and
// Enter; Escape or a click elsewhere closes it.
menu :: proc(ui: ^Ui, id: Widget_Id, items: []Menu_Item) -> (chosen: Maybe(int)) {
	if !is_menu_open(ui, id) do return
	r := ui.renderer
	th := ui.theme
	state := &ui.menu
	width: f32 = MENU_MIN_WIDTH
	height: f32 = 2 * MENU_INSET
	for item in items {
		w := text_width(r, item.label, .Body) + 24
		if item.shortcut != "" do w += text_width(r, item.shortcut, .Small) + 24
		width = max(width, w)
		height += MENU_ITEM_HEIGHT + (item.separator ? MENU_SEPARATOR : 0)
	}
	box := menu_rect(ui, state.at, {width, height})

	if take_key(ui, .Escape) do state.open = false
	if take_key(ui, .Down, repeats = true) do state.highlighted = next_item(items, state.highlighted, 1)
	if take_key(ui, .Up, repeats = true) do state.highlighted = next_item(items, state.highlighted, -1)
	if state.highlighted >= 0 && take_key(ui, .Enter) do chosen = state.highlighted
	if .Left in ui.input.pressed || .Right in ui.input.pressed {
		if !rect_contains(box, ui.input.mouse) do state.open = false
	}

	begin_popup(ui, box)
	defer end_popup(ui)
	draw_shadow(r, box, 6, 8, 24, th.shadow_menu)
	fill_rect(r, box, th.surface_2, 6)
	stroke_rect(r, box, th.border_subtle, 6)
	push_parent(ui, id)
	defer pop_parent(ui)
	y := box.y + MENU_INSET
	for item, i in items {
		if item.separator {
			fill_rect(r, {box.x + 8, y + MENU_SEPARATOR / 2, box.w - 16, 1}, th.border_subtle)
			y += MENU_SEPARATOR
		}
		row := Rect{box.x + MENU_INSET, y, box.w - 2 * MENU_INSET, MENU_ITEM_HEIGHT}
		y += MENU_ITEM_HEIGHT
		item_id := child_id(id, "item", i)
		states: Widget_States
		if item.disabled {
			states += {.Disabled}
		} else {
			interaction := interact(ui, item_id, row)
			if .Hovered in interaction && ui.input.moved do state.highlighted = i
			if .Clicked in interaction do chosen = i
		}
		if i == state.highlighted && !item.disabled {
			fill_rect(r, row, th.accent_selection, 4)
			states += {.Selected}
		}
		color := item.disabled ? th.text_disabled : th.text_primary
		middle := row.y + row.h / 2
		draw_text(r, item.label, row.x + 8, middle, .Body, color)
		if item.shortcut != "" {
			draw_text(
				r,
				item.shortcut,
				row.x + row.w - 8,
				middle,
				.Small,
				th.text_tertiary,
				.Right,
			)
		}
		declare(
			ui,
			{id = item_id, role = .Menu_Item, label = item.label, rect = row, states = states},
		)
	}
	if _, picked := chosen.?; picked do state.open = false
	return
}

// Where a menu of size opened at a point goes: right and down from it, or flipped to
// stay inside the window.
@(private = "file")
menu_rect :: proc(ui: ^Ui, at: [2]f32, size: [2]f32) -> Rect {
	v := ui.viewport
	x, y := at.x, at.y
	if x + size.x > v.x + v.w do x = at.x - size.x
	if y + size.y > v.y + v.h do y = at.y - size.y
	return keep_inside(ui, {x, y, size.x, size.y})
}

// The next item from i that can be chosen, going step; i itself when there is none.
@(private = "file")
next_item :: proc(items: []Menu_Item, i, step: int) -> int {
	at := i
	for _ in 0 ..< len(items) {
		at += step
		if at < 0 || at >= len(items) do return i
		if !items[at].disabled do return at
	}
	return i
}

// rect moved inside the window, as far as it fits.
@(private = "file")
keep_inside :: proc(ui: ^Ui, rect: Rect) -> Rect {
	v := ui.viewport
	moved := rect
	moved.x = clamp(moved.x, v.x + 4, max(v.x + v.w - rect.w - 4, v.x + 4))
	moved.y = clamp(moved.y, v.y + 4, max(v.y + v.h - rect.h - 4, v.y + 4))
	return moved
}

// A toast's look.
Toast_Kind :: enum u8 {
	Success,
	Error,
}

// What the user did to a toast.
Toast_Result :: enum u8 {
	None,
	// The action, Retry say.
	Acted,
	Closed,
}

// A short message at the bottom of window: a success, or an error with what to do
// about it. The app decides how long it stays.
toast :: proc(
	ui: ^Ui,
	id: Widget_Id,
	window: Rect,
	kind: Toast_Kind,
	message: string,
	action := "",
	close_label := "Close",
) -> (
	result: Toast_Result,
) {
	r := ui.renderer
	th := ui.theme
	action_width := action != "" ? button_width(r, action, {kind = .Ghost}) : 0
	width :=
		12 +
		16 +
		10 +
		text_width(r, message, .Body) +
		10 +
		(action != "" ? action_width + 4 : 0) +
		24 +
		6
	box := Rect{window.x + (window.w - width) / 2, window.y + window.h - 36 - 24, width, 36}
	begin_popup(ui, box, .Top)
	defer end_popup(ui)
	push_parent(ui, id)
	defer pop_parent(ui)
	draw_shadow(r, box, 6, 8, 24, th.shadow_menu)
	fill_rect(r, box, th.surface_2, 6)
	stroke_rect(r, box, th.border_strong, 6)
	middle := box.y + box.h / 2
	x := box.x + 12
	icon: Icon = kind == .Error ? .Circle_Alert : .Check
	draw_icon(r, icon, {x, middle - 8, 16, 16}, kind == .Error ? th.error : th.accent_text)
	x += 26
	x += draw_text(r, message, x, middle, .Body, th.text_primary) + 10
	declare(ui, {id = id, role = .Group, label = message, rect = box})
	if action != "" {
		action_rect := Rect{x, middle - 12, action_width, 24}
		if button(ui, child_id(id, "action"), action_rect, action, {kind = .Ghost}) do result = .Acted
		x += action_width + 4
	}
	close := Rect{x, middle - 12, 24, 24}
	if toolbar_button(ui, child_id(id, "close"), close, .X, close_label) do result = .Closed
	return
}

// What a dialog shows, and the words of its buttons.
Dialog_Options :: struct {
	// What assistive technologies call the dialog; its title when empty.
	label:          string,
	title:          string,
	message:        string,
	primary:        string,
	// The primary button removes or loses something: in the error colour, and Enter does
	// not choose it.
	destructive:    bool,
	// No Cancel button when empty: Escape still cancels.
	cancel:         string,
	// Another choice, apart from the others, such as not saving; none when empty.
	discard:        string,
	width:          f32,
	// The room the dialog keeps between its message and its buttons for what the caller
	// draws there, in points.
	content_height: f32,
}

Dialog_Choice :: enum u8 {
	None,
	Primary,
	Discard,
	Cancel,
}

// The buttons of a dialog from left to right, as each platform orders them: Windows
// puts the primary button first and Cancel last; macOS and Linux end on the primary
// one, with the discard choice apart on the left.
dialog_buttons :: proc(
	options: Dialog_Options,
	platform := PLATFORM,
) -> (
	left, right: [dynamic]Dialog_Choice,
) {
	left = make([dynamic]Dialog_Choice, context.temp_allocator)
	right = make([dynamic]Dialog_Choice, context.temp_allocator)
	if platform == .Windows {
		append(&right, Dialog_Choice.Primary)
		if options.discard != "" do append(&right, Dialog_Choice.Discard)
		if options.cancel != "" do append(&right, Dialog_Choice.Cancel)
	} else {
		if options.discard != "" do append(&left, Dialog_Choice.Discard)
		if options.cancel != "" do append(&right, Dialog_Choice.Cancel)
		append(&right, Dialog_Choice.Primary)
	}
	return
}

@(private = "file")
DIALOG_PADDING :: 20
@(private = "file")
DIALOG_GAP :: 10

// Starts a modal dialog over window: a scrim that takes the clicks and the keys meant
// for the window, and a box with a title, a message and room for what the caller draws
// in the content rect it gives. End it with end_dialog, which draws the buttons.
begin_dialog :: proc(
	ui: ^Ui,
	id: Widget_Id,
	window: Rect,
	options: Dialog_Options,
) -> (
	content: Rect,
) {
	r := ui.renderer
	th := ui.theme
	ui.modal_next = id
	ui.in_modal = true
	begin_popup(ui, window, .Top)
	fill_rect(r, window, th.scrim)
	push_parent(ui, id)
	box := dialog_box(ui, window, options)
	draw_shadow(r, box, 8, 16, 48, th.shadow_dialog)
	fill_rect(r, box, th.surface_2, 8)
	stroke_rect(r, box, th.border_subtle, 8)
	label := options.label != "" ? options.label : options.title
	declare(ui, {id = id, role = .Group, label = label, rect = box})
	width := box.w - 2 * DIALOG_PADDING
	y := box.y + DIALOG_PADDING
	if options.title != "" {
		for line in wrap_text(r, options.title, .Title, width, context.temp_allocator) {
			draw_text(r, line, box.x + DIALOG_PADDING, y + 10, .Title, th.text_primary)
			y += 20
		}
		y += DIALOG_GAP
	}
	if options.message != "" {
		for line in wrap_text(r, options.message, .Body, width, context.temp_allocator) {
			draw_text(r, line, box.x + DIALOG_PADDING, y + 9, .Body, th.text_secondary)
			y += 18
		}
		y += DIALOG_GAP
	}
	return {box.x + DIALOG_PADDING, y, width, options.content_height}
}

// Ends the dialog begun with begin_dialog: its buttons, Escape for Cancel and Enter for
// the primary button unless it destroys something. Gives the choice made this frame.
end_dialog :: proc(
	ui: ^Ui,
	id: Widget_Id,
	window: Rect,
	options: Dialog_Options,
) -> (
	choice: Dialog_Choice,
) {
	r := ui.renderer
	box := dialog_box(ui, window, options)
	if take_key(ui, .Escape) do choice = .Cancel
	if !options.destructive && take_key(ui, .Enter) do choice = .Primary
	left, right := dialog_buttons(options)
	y := box.y + box.h - DIALOG_PADDING - BUTTON_HEIGHT
	x := box.x + DIALOG_PADDING
	for c in left {
		label, button_options := dialog_button(options, c)
		width := button_width(r, label, button_options)
		if button(ui, child_id(id, "button", int(c)), {x, y, width, BUTTON_HEIGHT}, label, button_options) do choice = c
		x += width + 8
	}
	x = box.x + box.w - DIALOG_PADDING
	#reverse for c in right {
		label, button_options := dialog_button(options, c)
		width := button_width(r, label, button_options)
		x -= width
		if button(ui, child_id(id, "button", int(c)), {x, y, width, BUTTON_HEIGHT}, label, button_options) do choice = c
		x -= 8
	}
	pop_parent(ui)
	end_popup(ui)
	ui.in_modal = false
	return
}

// The box of a dialog: as wide as asked within the window, as high as what it holds,
// two fifths of the way down.
@(private = "file")
dialog_box :: proc(ui: ^Ui, window: Rect, options: Dialog_Options) -> Rect {
	r := ui.renderer
	width := min(options.width > 0 ? options.width : 440, window.w - 32)
	inner := width - 2 * DIALOG_PADDING
	height: f32 = 2 * DIALOG_PADDING + BUTTON_HEIGHT
	if options.title != "" do height += 20 * f32(len(wrap_text(r, options.title, .Title, inner, context.temp_allocator))) + DIALOG_GAP
	if options.message != "" do height += 18 * f32(len(wrap_text(r, options.message, .Body, inner, context.temp_allocator))) + DIALOG_GAP
	height += options.content_height + (options.content_height > 0 ? DIALOG_GAP : 0)
	return {window.x + (window.w - width) / 2, window.y + (window.h - height) * 0.4, width, height}
}

@(private = "file")
dialog_button :: proc(
	options: Dialog_Options,
	choice: Dialog_Choice,
) -> (
	label: string,
	button_options: Button_Options,
) {
	switch choice {
	case .Primary:
		return options.primary, {kind = options.destructive ? .Destructive : .Primary}
	case .Discard:
		return options.discard, {kind = .Secondary}
	case .Cancel:
		return options.cancel, {kind = .Secondary}
	case .None:
	}
	return
}
