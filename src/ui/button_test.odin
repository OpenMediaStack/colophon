package ui

import "core:testing"

@(private = "file")
Buttons :: struct {
	clicks:   map[string]int,
	disabled: bool,
	checked:  bool,
}

@(private = "file")
buttons_frame :: proc(ui: ^Ui, data: rawptr) {
	b := (^Buttons)(data)
	if button(
		ui,
		widget_id("Save"),
		{10, 10, 100, 28},
		"Save",
		{kind = .Primary, disabled = b.disabled},
	) {
		b.clicks["Save"] += 1
	}
	if button(ui, widget_id("Revert"), {120, 10, 80, 28}, "Revert") do b.clicks["Revert"] += 1
	if disc_button(ui, widget_id("Play"), {250, 10, 36, 36}, .Play, "Play", 1, b.disabled) {
		b.clicks["Play"] += 1
	}
	if toolbar_button(
		ui,
		widget_id("Sidebar"),
		{210, 10, 28, 28},
		.Panel_Left,
		"Sidebar",
		b.checked,
	) {
		b.clicks["Sidebar"] += 1
	}
}

@(private = "file")
buttons_harness :: proc(h: ^Harness, b: ^Buttons) {
	b.clicks = make(map[string]int, context.temp_allocator)
	harness_init(h, buttons_frame, b)
	run_frame(h)
}

@(private = "file")
destroy_buttons :: proc(h: ^Harness) {
	harness_destroy(h)
	free_all(context.temp_allocator)
}

@(test)
a_button_reports_its_click :: proc(t: ^testing.T) {
	h: Harness
	b: Buttons
	buttons_harness(&h, &b)
	defer destroy_buttons(&h)
	click(&h, "Revert")
	click(&h, "Sidebar")
	testing.expect_value(t, b.clicks["Revert"], 1)
	testing.expect_value(t, b.clicks["Sidebar"], 1)
	testing.expect_value(t, b.clicks["Save"], 0)
}

@(test)
a_disabled_button_does_nothing :: proc(t: ^testing.T) {
	h: Harness
	b := Buttons {
		disabled = true,
	}
	buttons_harness(&h, &b)
	defer destroy_buttons(&h)
	click(&h, "Save")
	testing.expect_value(t, b.clicks["Save"], 0)
	info, _ := find_widget(&h.ui, "Save")
	testing.expect(t, .Disabled in info.states)
}

@(test)
a_focused_button_activates_with_enter_or_space :: proc(t: ^testing.T) {
	h: Harness
	b: Buttons
	buttons_harness(&h, &b)
	defer destroy_buttons(&h)
	request_focus(&h.ui, widget_id("Revert"))
	ui_end_frame(&h.ui)
	press_key(&h, .Enter)
	press_key(&h, .Space)
	testing.expect_value(t, b.clicks["Revert"], 2)
	info, _ := find_widget(&h.ui, "Revert")
	testing.expect(t, .Focused in info.states)
}

@(test)
a_toggle_that_is_on_is_declared_checked :: proc(t: ^testing.T) {
	h: Harness
	b := Buttons {
		checked = true,
	}
	buttons_harness(&h, &b)
	defer destroy_buttons(&h)
	info, found := find_widget(&h.ui, "Sidebar")
	testing.expect(t, found && info.role == .Button && .Checked in info.states)
}

@(test)
a_button_is_as_wide_as_its_content :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	plain := button_width(r, "Save")
	with_icon := button_width(r, "Save", {icon = Icon.Save})
	testing.expect(t, plain > 2 * 12)
	testing.expect_value(t, with_icon, plain + 16 + 6)
}

// Every kind of button and the toolbar buttons, in every state of the brief's
// component sheet, in both themes.
@(test)
the_buttons_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{900, 260}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	draw_button_sheet(cap.renderer, {0, 0, size.x / 2, size.y}, theme(.Dark))
	draw_button_sheet(cap.renderer, {size.x / 2, 0, size.x / 2, size.y}, theme(.Light))
	finish_capture(t, &cap, "buttons.png")
}

@(private = "file")
draw_button_sheet :: proc(r: ^Renderer, area: Rect, th: Theme) {
	fill_rect(r, area, th.surface_1)
	states := [?]Button_States{{}, {.Hovered}, {.Hovered, .Pressed}, {.Focused}, {.Disabled}}
	kinds := [?]Button_Kind{.Primary, .Secondary, .Ghost, .Destructive}
	labels := [?]string{"Save", "Revert", "Reset", "Remove"}
	y := area.y + 12
	for kind, k in kinds {
		options := Button_Options {
			kind = kind,
		}
		if kind == .Primary do options.icon = Icon.Save
		width := button_width(r, labels[k], options)
		x := area.x + 12
		for state in states {
			draw_button(r, th, {x, y, width, BUTTON_HEIGHT}, labels[k], options, state)
			x += width + 10
		}
		y += 36
	}
	toolbar := Rect{area.x, y, area.w, 40}
	fill_rect(r, toolbar, th.surface_2)
	x := area.x + 12
	toolbar_states := [?]Button_States {
		{},
		{.Hovered},
		{.Hovered, .Pressed},
		{.Focused},
		{.Disabled},
		{.Checked},
	}
	for state in toolbar_states {
		draw_toolbar_button(
			r,
			th,
			{x, y + 6, TOOLBAR_BUTTON_SIZE, TOOLBAR_BUTTON_SIZE},
			.Panel_Left,
			state,
		)
		x += 36
	}
	y += 52
	options := Button_Options {
		kind     = .Primary,
		shortcut = "⌘O",
	}
	width := button_width(r, "Open folder…", options)
	draw_button(r, th, {area.x + 12, y, width, 32}, "Open folder…", options, {})
}

@(test)
tab_goes_through_the_buttons_that_are_enabled :: proc(t: ^testing.T) {
	h: Harness
	b := Buttons {
		disabled = true,
	}
	buttons_harness(&h, &b)
	defer destroy_buttons(&h)
	request_focus(&h.ui, widget_id("Revert"))
	ui_end_frame(&h.ui)
	run_frame(&h)
	press_key(&h, .Tab)
	testing.expect(t, has_focus(&h.ui, widget_id("Sidebar")))
	press_key(&h, .Tab)
	// The disabled Save is skipped.
	testing.expect(t, has_focus(&h.ui, widget_id("Revert")))
	press_key(&h, .Tab, {.Shift})
	testing.expect(t, has_focus(&h.ui, widget_id("Sidebar")))
}

@(test)
a_disabled_button_keeps_its_clicks_from_what_lies_under_it :: proc(t: ^testing.T) {
	h: Harness
	clicked := false
	harness_init(&h, proc(ui: ^Ui, data: rawptr) {
			if button(ui, widget_id("Under"), {0, 0, 200, 100}, "Under") do (^bool)(data)^ = true
			button(ui, widget_id("Over"), {10, 10, 80, 28}, "Over", {disabled = true})
		}, &clicked)
	defer harness_destroy(&h)
	run_frame(&h)
	click(&h, "Over")
	testing.expect(t, !clicked)
}

@(test)
a_toggle_says_it_is_one_even_when_off :: proc(t: ^testing.T) {
	h: Harness
	b: Buttons
	buttons_harness(&h, &b)
	defer destroy_buttons(&h)
	info, _ := find_widget(&h.ui, "Sidebar")
	testing.expect(t, .Checkable in info.states && .Checked not_in info.states)
	revert, _ := find_widget(&h.ui, "Revert")
	testing.expect(t, .Checkable not_in revert.states)
}

@(test)
the_disc_button_clicks_and_a_disabled_one_does_not :: proc(t: ^testing.T) {
	h: Harness
	b: Buttons
	buttons_harness(&h, &b)
	defer harness_destroy(&h)
	testing.expect(t, click(&h, "Play"))
	testing.expect_value(t, b.clicks["Play"], 1)
	info, _ := find_widget(&h.ui, "Play")
	testing.expect_value(t, info.role, Role.Button)
	b.disabled = true
	run_frame(&h)
	testing.expect(t, click(&h, "Play"))
	testing.expect_value(t, b.clicks["Play"], 1)
	info, _ = find_widget(&h.ui, "Play")
	testing.expect(t, .Disabled in info.states)
}
