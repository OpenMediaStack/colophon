package ui

// The look of a button, from the brief's component sheet.
Button_Kind :: enum u8 {
	// The main action of a screen or a dialog, in the accent colour.
	Primary,
	// Other actions, bordered.
	Secondary,
	// Actions that need little weight, in menus and lists: no border, no fill.
	Ghost,
	// An action that destroys something, in the error colour.
	Destructive,
	// An action inside a message, a toast's Retry: in the accent's text colour, a fill
	// on hover.
	Link,
}

// How a button is drawn: what the mouse, the keyboard and the app make of it.
Button_State :: enum u8 {
	Hovered,
	Pressed,
	Focused,
	Disabled,
	// A toggle that is on: a panel shown, a column visible.
	Checked,
}

Button_States :: bit_set[Button_State]

// What a button holds besides its label.
Button_Options :: struct {
	kind:     Button_Kind,
	icon:     Maybe(Icon),
	// A shortcut hint after the label, dimmed, for primary buttons.
	shortcut: string,
	disabled: bool,
	// Left and right of the content, in points; 12 when 0, the brief's inner padding.
	padding:  f32,
	// What assistive technologies call it when the label drawn says less, a shortcut
	// hint such as the command palette's; the label when empty.
	name:     string,
	// The label in the small style and the secondary text colour: a key shown as a
	// button.
	small:    bool,
}

// Heights of the brief: buttons and inputs 28, a toolbar button 28 square.
BUTTON_HEIGHT :: 28
TOOLBAR_BUTTON_SIZE :: 28

@(private = "file")
BUTTON_PADDING :: 12
@(private = "file")
ICON_GAP :: 6
@(private = "file")
SHORTCUT_GAP :: 10
@(private = "file")
RADIUS :: 4
// Around a focused widget, outside it: 2 points wide, 1 away.
@(private = "file")
FOCUS_RING :: 2
@(private = "file")
FOCUS_OFFSET :: 1

// A button labelled label at rect. True when it was clicked, or activated with Enter
// or Space while it had the keyboard focus. A disabled button does nothing.
button :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	label: string,
	options := Button_Options{},
) -> (
	clicked: bool,
) {
	states, activated := button_states(ui, id, rect, options.disabled)
	draw_button(ui.renderer, ui.theme, rect, label, options, states)
	declare(
		ui,
		{
			id = id,
			role = .Button,
			label = options.name != "" ? options.name : label,
			rect = rect,
			states = widget_states(states),
			focusable = !options.disabled,
		},
	)
	return activated
}

// The width a button needs for its label, icon and shortcut.
button_width :: proc(r: ^Renderer, label: string, options := Button_Options{}) -> f32 {
	style := button_style(options)
	width :=
		2 * (options.padding > 0 ? options.padding : BUTTON_PADDING) + text_width(r, label, style)
	if _, has_icon := options.icon.?; has_icon do width += 16 + ICON_GAP
	if options.shortcut != "" do width += SHORTCUT_GAP + text_width(r, options.shortcut, .Small)
	return width
}

// A toolbar button: an icon in a 28 by 28 square, its label read by screen readers and
// shown in its tooltip. A toggle, such as a panel's, says whether it is on: nil for a
// button that is not one.
toolbar_button :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	icon: Icon,
	label: string,
	checked: Maybe(bool) = nil,
	disabled := false,
) -> (
	clicked: bool,
) {
	states, activated := button_states(ui, id, rect, disabled)
	if checked == true do states += {.Checked}
	draw_toolbar_button(ui.renderer, ui.theme, rect, icon, states)
	tooltip(ui, id, rect, label)
	declared := widget_states(states)
	if checked != nil do declared += {.Checkable}
	declare(
		ui,
		{
			id = id,
			role = .Button,
			label = label,
			rect = rect,
			states = declared,
			focusable = !disabled,
		},
	)
	return activated
}

// Draws a button in states, without the Ui: for the component sheet's captures.
draw_button :: proc(
	r: ^Renderer,
	th: Theme,
	rect: Rect,
	label: string,
	options: Button_Options,
	states: Button_States,
) {
	fill, border, text: Color
	style := button_style(options)
	disabled := .Disabled in states
	switch options.kind {
	case .Primary, .Destructive:
		base, hover, on := th.accent, th.accent_hover, th.on_accent
		if options.kind == .Destructive do base, hover, on = th.error, lighter(th.error), th.on_error
		switch {
		case disabled:
			fill, text = th.surface_3, th.text_disabled
		case .Pressed in states:
			fill, text = base, on
		case .Hovered in states:
			fill, text = hover, on
		case:
			fill, text = base, on
		}
	case .Secondary:
		border = disabled ? th.border_subtle : th.border_strong
		text = disabled ? th.text_disabled : (options.small ? th.text_secondary : th.text_primary)
		if !disabled && .Pressed in states {
			fill = th.border_strong
		} else if !disabled && .Hovered in states {
			fill = th.surface_3
		}
	case .Ghost:
		text = disabled ? th.text_disabled : th.text_secondary
		if !disabled && .Pressed in states {
			fill, text = th.border_strong, th.text_primary
		} else if !disabled && .Hovered in states {
			fill, text = th.surface_3, th.text_primary
		}
	case .Link:
		text = disabled ? th.text_disabled : th.accent_text
		if !disabled && .Pressed in states {
			fill = th.border_strong
		} else if !disabled && .Hovered in states {
			fill = th.surface_3
		}
	}
	if fill.a > 0 do fill_rect(r, rect, fill, RADIUS)
	if border.a > 0 do stroke_rect(r, rect, border, RADIUS)
	if .Focused in states && !disabled do draw_focus_ring(r, th, rect, RADIUS)

	padding := options.padding > 0 ? options.padding : BUTTON_PADDING
	content := button_width(r, label, options) - 2 * padding
	x := rect.x + max((rect.w - content) / 2, padding)
	middle := rect.y + rect.h / 2
	if icon, has_icon := options.icon.?; has_icon {
		draw_icon(r, icon, {x, middle - 8, 16, 16}, text)
		x += 16 + ICON_GAP
	}
	room := rect.x + rect.w - padding - x
	draw_text_fit(r, label, x, middle, room, style, text)
	if options.shortcut != "" {
		x += text_width(r, label, style) + SHORTCUT_GAP
		hint := text
		hint.a *= 0.75
		draw_text(r, options.shortcut, x, middle, .Small, hint)
	}
}

// The weight of a button's label: medium for the actions that stand out, small for a
// key.
@(private = "file")
button_style :: proc(options: Button_Options) -> Text_Style {
	if options.small do return .Small
	return options.kind == .Ghost || options.kind == .Secondary ? .Body : .Body_Strong
}

// A small button with an icon alone, a toast's close: the icon size points in the
// tertiary text colour, a fill on hover, its label read by screen readers.
icon_button :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	icon: Icon,
	label: string,
	size: f32 = 14,
	focusable := true,
) -> bool {
	r := ui.renderer
	th := ui.theme
	states, activated := button_states(ui, id, rect, false)
	switch {
	case .Pressed in states:
		fill_rect(r, rect, th.border_strong, RADIUS)
	case .Hovered in states:
		fill_rect(r, rect, th.surface_3, RADIUS)
	}
	if .Focused in states do draw_focus_ring(r, th, rect, RADIUS)
	draw_icon_centered(r, icon, rect, th.text_tertiary, size)
	declare(
		ui,
		{
			id = id,
			role = .Button,
			label = label,
			rect = rect,
			states = widget_states(states),
			focusable = focusable,
		},
	)
	return activated
}

// Draws a toolbar button in states, without the Ui.
draw_toolbar_button :: proc(
	r: ^Renderer,
	th: Theme,
	rect: Rect,
	icon: Icon,
	states: Button_States,
) {
	disabled := .Disabled in states
	color := th.text_secondary
	switch {
	case disabled:
		color = th.text_disabled
	case .Pressed in states:
		fill_rect(r, rect, th.border_strong, RADIUS)
		color = th.text_primary
	case .Checked in states || .Hovered in states:
		fill_rect(r, rect, th.surface_3, RADIUS)
		if .Checked in states do color = th.text_primary
	}
	if .Focused in states && !disabled do draw_focus_ring(r, th, rect, RADIUS)
	draw_icon_centered(r, icon, rect, color)
}

// The keyboard focus ring around rect, outside it.
draw_focus_ring :: proc(r: ^Renderer, th: Theme, rect: Rect, radius: f32) {
	grow: f32 = FOCUS_OFFSET + FOCUS_RING
	around := Rect{rect.x - grow, rect.y - grow, rect.w + 2 * grow, rect.h + 2 * grow}
	stroke_rect(r, around, th.focus_ring, radius + grow, FOCUS_RING)
}

// What the mouse and the keyboard make of a button this frame, and whether it was
// activated.
@(private = "file")
button_states :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	disabled: bool,
) -> (
	states: Button_States,
	activated: bool,
) {
	if disabled {
		// It still takes the clicks meant for it, which must not reach what lies under it.
		block_mouse(ui, rect)
		release_focus(ui, id)
		return {.Disabled}, false
	}
	result := interact(ui, id, rect)
	if .Hovered in result do states += {.Hovered}
	if .Held in result && .Hovered in result do states += {.Pressed}
	if has_focus(ui, id) {
		states += {.Focused}
		activated = take_key(ui, .Enter) || take_key(ui, .Space)
		if take_key(ui, .Tab) do move_focus(ui, .Forward)
		if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
	}
	return states, activated || .Clicked in result
}

// What a widget drawn in states is, for the accessibility tree.
@(private)
widget_states :: proc(states: Button_States) -> (w: Widget_States) {
	if .Hovered in states do w += {.Hovered}
	if .Pressed in states do w += {.Pressed}
	if .Focused in states do w += {.Focused}
	if .Disabled in states do w += {.Disabled}
	if .Checked in states do w += {.Checked}
	return
}

// A colour 10 percent brighter, as 1.0.0's Slint made the hover of a colour with no
// hover token: its HSV value times 1.1, which scales every channel alike.
@(private = "file")
lighter :: proc(c: Color) -> Color {
	value := max(c.r, c.g, c.b)
	if value <= 0 do return c
	k := min(value * 1.1, 1) / value
	return {c.r * k, c.g * k, c.b * k, c.a}
}
