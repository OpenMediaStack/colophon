package ui

// How long the mouse rests on a widget before its tooltip shows, in seconds.
TOOLTIP_DELAY :: 0.6

// A tooltip under rect, once the mouse has rested on the widget id for a moment and no
// button is down: the label of a toolbar button, a shortcut. A press hides it until
// the mouse leaves the widget.
tooltip :: proc(ui: ^Ui, id: Widget_Id, rect: Rect, text: string) {
	if ui.hot == id && ui.input.pressed != {} do ui.tooltip_hidden = id
	if ui.hot != id || ui.tooltip_hidden == id || ui.input.down != {} || len(text) == 0 do return
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
	push_outer_clip(r, rect_inset(box, -48, -48))
	defer pop_clip(r)
	draw_shadow(r, box, 6, 8, 24, th.shadow_menu)
	fill_rect(r, box, th.surface_2, 6)
	stroke_rect(r, box, th.border_strong, 6)
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
	// Whether it is ticked, for an item that is: a column shown or hidden.
	checked:   Maybe(bool),
}

// The context menu open, at most one at a time.
Menu_State :: struct {
	owner:       Widget_Id,
	open:        bool,
	at:          [2]f32,
	// The item the arrow keys reached; -1 for none.
	highlighted: int,
	// It was drawn this frame: a menu its owner no longer draws is closed.
	drawn:       bool,
	// The arrow key the menu took to go to the menu beside it: -1 for Left, 1 for Right,
	// 0 for none yet; its owner reads it with menu_step.
	step:        int,
}

@(private = "file")
MENU_ITEM_HEIGHT :: 26
@(private = "file")
MENU_INSET :: 4
@(private = "file")
MENU_SEPARATOR :: 9
@(private = "file")
MENU_MIN_WIDTH :: 180
// The room on the left of the labels for the ticks of checkable items.
@(private = "file")
MENU_CHECK_WIDTH :: 20

// Opens the context menu id at a point, a right click's.
open_menu :: proc(ui: ^Ui, id: Widget_Id, at: [2]f32) {
	ui.menu = {
		owner       = id,
		open        = true,
		at          = at,
		highlighted = -1,
		drawn       = true,
	}
}

// The way the open menu asked to go to the menu beside it with an arrow key, -1 for
// the one before and 1 for the one after, 0 when it did not; asking again gives 0. A
// menu bar reads it to open the neighbour.
menu_step :: proc(ui: ^Ui) -> int {
	step := ui.menu.step
	ui.menu.step = 0
	return step
}

// Closes the context menu, whichever is open.
close_menu :: proc(ui: ^Ui) {
	ui.menu.open = false
}

is_menu_open :: proc(ui: ^Ui, id: Widget_Id) -> bool {
	return ui.menu.open && ui.menu.owner == id
}

// The context menu id, labelled label, drawn while it is open, which is drawn on Linux
// and wherever the system has none. Gives the item chosen by a click or by the arrow
// keys and Enter. While it is open it takes the keys, and the mouse over the whole
// window: Escape or a click elsewhere closes it, and the click goes no further.
menu :: proc(ui: ^Ui, id: Widget_Id, items: []Menu_Item, label := "") -> (chosen: Maybe(int)) {
	if !is_menu_open(ui, id) do return
	r := ui.renderer
	th := ui.theme
	state := &ui.menu
	state.drawn = true
	ui.in_menu = true
	defer ui.in_menu = false
	checkable := false
	for item in items do checkable ||= item.checked != nil
	gutter: f32 = checkable ? MENU_CHECK_WIDTH : 0
	width: f32 = MENU_MIN_WIDTH
	height: f32 = 2 * MENU_INSET
	for item in items {
		w := text_width(r, item.label, .Body) + 24 + gutter
		if item.shortcut != "" do w += text_width(r, item.shortcut, .Small) + 24
		width = max(width, w)
		height += MENU_ITEM_HEIGHT + (item.separator ? MENU_SEPARATOR : 0)
	}
	box := menu_rect(ui, state.at, {width, height})
	// The items may have changed since the arrow keys reached one.
	if state.highlighted >= len(items) ||
	   (state.highlighted >= 0 && items[state.highlighted].disabled) {
		state.highlighted = -1
	}
	if ui.input.moved && !rect_contains(box, ui.input.mouse) do state.highlighted = -1

	if take_key(ui, .Escape) do state.open = false
	if take_key(ui, .Left) do state.step = -1
	if take_key(ui, .Right) do state.step = 1
	if take_key(ui, .Down, repeats = true) do state.highlighted = next_item(items, state.highlighted, 1)
	if take_key(ui, .Up, repeats = true) do state.highlighted = next_item(items, state.highlighted, -1)
	if state.highlighted >= 0 && take_key(ui, .Enter) do chosen = state.highlighted
	if .Left in ui.input.pressed || .Right in ui.input.pressed {
		if !rect_contains(box, ui.input.mouse) do state.open = false
	}

	// The whole window is the popup: what lies under the menu gets nothing.
	begin_popup(ui, ui.viewport)
	defer end_popup(ui)
	draw_shadow(r, box, 6, 8, 24, th.shadow_menu)
	fill_rect(r, box, th.surface_2, 6)
	stroke_rect(r, box, th.border_subtle, 6)
	declare(ui, {id = id, role = .Menu, label = label, rect = box})
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
		if checked, is := item.checked.?; is {
			states += {.Checkable}
			if checked {
				states += {.Checked}
				draw_icon_centered(
					r,
					.Check,
					{row.x + 4, row.y, MENU_CHECK_WIDTH, row.h},
					color,
					12,
				)
			}
		}
		draw_text(r, item.label, row.x + 8 + gutter, middle, .Body, color)
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
// From none, Up goes to the last item.
@(private = "file")
next_item :: proc(items: []Menu_Item, i, step: int) -> int {
	at := i
	if i < 0 && step < 0 do at = len(items)
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

// A short message at the bottom of window, 16 points above it: a success, or an error
// with what to do about it. The app decides how long it stays. A message too long for
// the window is cut.
toast :: proc(
	ui: ^Ui,
	id: Widget_Id,
	window: Rect,
	kind: Toast_Kind,
	message: string,
	action := "",
	close_label := "",
) -> (
	result: Toast_Result,
) {
	TOAST_HEIGHT :: 36
	GAP :: 10
	r := ui.renderer
	th := ui.theme
	action_options := Button_Options {
		kind    = .Link,
		padding = 8,
	}
	action_width := action != "" ? button_width(r, action, action_options) : 0
	message_width := text_width(r, message, .Body)
	width := 12 + 16 + GAP + message_width + GAP + (action != "" ? action_width + GAP : 0) + 24 + 6
	if most := window.w - 32; width > most {
		message_width = max(message_width - (width - most), 0)
		width = most
	}
	box := Rect {
		window.x + (window.w - width) / 2,
		window.y + window.h - TOAST_HEIGHT - 16,
		width,
		TOAST_HEIGHT,
	}
	begin_popup(ui, box, .Top)
	defer end_popup(ui)
	declare(ui, {id = id, role = .Group, label = message, rect = box})
	push_parent(ui, id)
	defer pop_parent(ui)
	draw_shadow(r, box, 6, 8, 24, th.shadow_menu)
	fill_rect(r, box, th.surface_2, 6)
	stroke_rect(r, box, th.border_strong, 6)
	middle := box.y + box.h / 2
	x := box.x + 12
	icon: Icon = kind == .Error ? .Circle_Alert : .Check
	draw_icon(r, icon, {x, middle - 8, 16, 16}, kind == .Error ? th.error : th.accent_text)
	x += 16 + GAP
	draw_text_fit(r, message, x, middle, message_width, .Body, th.text_primary)
	x += message_width + GAP
	if action != "" {
		action_rect := Rect{x, middle - 12, action_width, 24}
		if button(ui, child_id(id, "action"), action_rect, action, action_options) do result = .Acted
		x += action_width + GAP
	}
	close := Rect{x, middle - 12, 24, 24}
	closing := close_label != "" ? close_label : tr("Close")
	if icon_button(ui, child_id(id, "close"), close, .X, closing) do result = .Closed
	return
}

// What a dialog shows, and the words of its buttons.
Dialog_Options :: struct {
	// What assistive technologies call the dialog; its title when empty.
	label:          string,
	title:          string,
	// Its text, wrapped to the dialog's width; a line break starts a new paragraph.
	message:        string,
	primary:        string,
	// The primary button removes or loses something: in the error colour, and Enter does
	// not choose it.
	destructive:    bool,
	// No Cancel button when empty: Escape still cancels.
	cancel:         string,
	// Another choice, apart from the others, such as not saving; none when empty.
	discard:        string,
	// How wide the dialog is, in points, within the window; 440 when 0.
	width:          f32,
	// The room the dialog keeps between its message and its buttons for what the caller
	// draws there, in points.
	content_height: f32,
	// Whose button order the dialog follows: the system's when nil; a capture pins one.
	platform:       Maybe(Platform),
}

// What the user chose in a dialog, by its buttons or by the keys.
Dialog_Choice :: enum u8 {
	None,
	Primary,
	Discard,
	Cancel,
}

// A dialog being drawn, from begin_dialog to end_dialog.
Dialog :: struct {
	id:      Widget_Id,
	box:     Rect,
	// Where the caller draws what the dialog holds besides its title and message.
	content: Rect,
	options: Dialog_Options,
}

// The buttons of a dialog from left to right, as each platform orders them: Windows
// puts the primary button first and Cancel last; macOS and Linux end on the primary
// one, with the discard choice apart on the left. The lists are temporary.
@(private)
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
// Between what the dialog says and its buttons.
@(private = "file")
DIALOG_BUTTONS_GAP :: 20

// Starts a modal dialog over window: a scrim that takes the clicks and the keys meant
// for the window, and a box with a title, a message and room for what the caller draws
// in the dialog's content rect. End it with end_dialog, which draws the buttons. The
// focus it finds goes back there when it closes. Run a frame at once after the first
// one, for the keys to go to the dialog: ui_end_frame asks for it.
begin_dialog :: proc(
	ui: ^Ui,
	id: Widget_Id,
	window: Rect,
	options: Dialog_Options,
) -> (
	d: Dialog,
) {
	r := ui.renderer
	th := ui.theme
	begin_modal(ui, id, window)
	width := dialog_width(window, options) - 2 * DIALOG_PADDING
	title_lines: []string
	if options.title != "" do title_lines = wrap_text(r, options.title, .Title, width, context.temp_allocator)
	// A dialog without a title or a message holds its content right under what it has.
	message_lines: []string
	if options.message != "" do message_lines = wrap_text(r, options.message, .Body, width, context.temp_allocator)
	title_line, message_line := line_height(r, .Title), line_height(r, .Body)
	box := dialog_box(
		window,
		options,
		f32(len(title_lines)) * title_line,
		f32(len(message_lines)) * message_line,
	)
	d.id = id
	d.box = box
	d.options = options
	draw_shadow(r, box, 8, 16, 48, th.shadow_dialog)
	fill_rect(r, box, th.surface_2, 8)
	stroke_rect(r, box, th.border_subtle, 8)
	label := options.label != "" ? options.label : options.title
	declare(ui, {id = id, role = .Dialog, label = label, rect = box})
	push_parent(ui, id)
	y := box.y + DIALOG_PADDING
	if len(title_lines) > 0 {
		for line in title_lines {
			draw_text(r, line, box.x + DIALOG_PADDING, y + title_line / 2, .Title, th.text_primary)
			y += title_line
		}
		y += DIALOG_GAP
	}
	if len(message_lines) > 0 {
		top := y
		for line in message_lines {
			draw_text(
				r,
				line,
				box.x + DIALOG_PADDING,
				y + message_line / 2,
				.Body,
				th.text_secondary,
			)
			y += message_line
		}
		declare(
			ui,
			{
				id = child_id(id, "message"),
				role = .Label,
				label = options.message,
				rect = {box.x + DIALOG_PADDING, top, width, y - top},
			},
		)
		y += DIALOG_GAP
	}
	d.content = {box.x + DIALOG_PADDING, y, width, options.content_height}
	return
}

// Ends the dialog begun with begin_dialog: its buttons, which take Enter and Space when
// they have the focus, then Escape for Cancel and Enter for the primary button unless
// it destroys something. Tab goes into the dialog when the focus is outside it. Gives
// the choice made this frame.
end_dialog :: proc(ui: ^Ui, d: Dialog) -> (choice: Dialog_Choice) {
	r := ui.renderer
	box := d.box
	options := d.options
	left, right := dialog_buttons(options, options.platform.? or_else PLATFORM)
	y := box.y + box.h - DIALOG_PADDING - BUTTON_HEIGHT
	x := box.x + DIALOG_PADDING
	for c in left {
		label, button_options := dialog_button(options, c)
		width := button_width(r, label, button_options)
		if button(ui, child_id(d.id, "button", int(c)), {x, y, width, BUTTON_HEIGHT}, label, button_options) do choice = c
		x += width + 8
	}
	x = box.x + box.w - DIALOG_PADDING
	#reverse for c in right {
		label, button_options := dialog_button(options, c)
		width := button_width(r, label, button_options)
		x -= width
		if button(ui, child_id(d.id, "button", int(c)), {x, y, width, BUTTON_HEIGHT}, label, button_options) do choice = c
		x -= 8
	}
	if choice == .None {
		if take_key(ui, .Escape) do choice = .Cancel
		if !options.destructive && take_key(ui, .Enter) do choice = .Primary
	}
	// The keys that reach here were not taken by a widget of the dialog: the focus is
	// outside it.
	if take_key(ui, .Tab) do move_focus(ui, .Forward)
	if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
	pop_parent(ui)
	end_modal(ui)
	return
}

// Starts a modal overlay over window, for a dialog or the command palette: a scrim that
// takes the clicks and the keys meant for what lies under it, drawn on the top layer,
// and the focus remembered for when the overlay closes, when it goes back where it
// was. The caller declares the widget id for what it draws, and ends with end_modal.
begin_modal :: proc(ui: ^Ui, id: Widget_Id, window: Rect) {
	// A menu left open under it would take the keys the overlay needs.
	if !ui.in_menu do ui.menu.open = false
	ui.modal_next = id
	ui.dialog = id
	remember_focus(ui, id)
	begin_popup(ui, window, .Top)
	fill_rect(ui.renderer, window, ui.theme.scrim)
}

end_modal :: proc(ui: ^Ui) {
	end_popup(ui)
	ui.dialog = 0
}

// Notes the focus a dialog found when it showed, for when it closes.
@(private = "file")
remember_focus :: proc(ui: ^Ui, id: Widget_Id) {
	for &f in ui.dialog_focus {
		if f.id == id {
			f.shown = true
			return
		}
	}
	append(&ui.dialog_focus, Dialog_Focus{id, ui.focus, true})
}

@(private = "file")
dialog_width :: proc(window: Rect, options: Dialog_Options) -> f32 {
	return min(options.width > 0 ? options.width : 440, window.w - 32)
}

// The box of a dialog: as wide as asked within the window, as high as what it holds,
// two fifths of the way down, and 16 points from the top at least.
@(private = "file")
dialog_box :: proc(
	window: Rect,
	options: Dialog_Options,
	title_height, message_height: f32,
) -> Rect {
	width := dialog_width(window, options)
	height: f32 = 2 * DIALOG_PADDING + BUTTON_HEIGHT + DIALOG_BUTTONS_GAP - DIALOG_GAP
	if title_height > 0 do height += title_height + DIALOG_GAP
	if message_height > 0 do height += message_height + DIALOG_GAP
	height += options.content_height + (options.content_height > 0 ? DIALOG_GAP : 0)
	y := window.y + max((window.h - height) * 0.4, 16)
	return {window.x + (window.w - width) / 2, y, width, height}
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
