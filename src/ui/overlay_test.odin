package ui

import "core:testing"

@(private = "file")
Overlays :: struct {
	menu_chosen:   Maybe(int),
	toast:         Toast_Result,
	dialog:        Dialog_Choice,
	show_dialog:   bool,
	// A second dialog over the first, as the unsaved changes over the settings.
	show_second:   bool,
	second:        Dialog_Choice,
	show_toast:    bool,
	destructive:   bool,
	behind_clicks: int,
	field_changes: int,
	field:         [dynamic]u8,
}

@(private = "file")
MENU_ITEMS := []Menu_Item {
	{label = "Play"},
	{label = "Show in Finder", disabled = true},
	{label = "Revert", shortcut = "⌘R", separator = true},
	{label = "Year", checked = true},
}

@(private = "file")
WINDOW :: Rect{0, 0, 1280, 800}

@(private = "file")
overlays_frame :: proc(ui: ^Ui, data: rawptr) {
	o := (^Overlays)(data)
	if button(ui, widget_id("Behind"), {500, 300, 200, 28}, "Behind") do o.behind_clicks += 1
	result := text_field(ui, widget_id("Field"), {500, 340, 200, 28}, string(o.field[:]), "Field")
	if result.changed do o.field_changes += 1
	tooltip(ui, widget_id("Behind"), {500, 300, 200, 28}, "Plays the track")
	toolbar_button(ui, widget_id("Sidebar"), {20, 20, 28, 28}, .Panel_Left, "Toggle sidebar")
	if chosen, ok := menu(ui, widget_id("Menu"), MENU_ITEMS, "Track").?; ok do o.menu_chosen = chosen
	if o.show_toast {
		if result := toast(ui, widget_id("Toast"), WINDOW, .Error, "2 files could not be saved", "Retry"); result != .None do o.toast = result
	}
	if o.show_dialog {
		options := Dialog_Options {
			title       = "Save the changes?",
			message     = "3 files have changes that are not saved.",
			primary     = "Save",
			cancel      = "Cancel",
			discard     = "Don't Save",
			destructive = o.destructive,
		}
		d := begin_dialog(ui, widget_id("Dialog"), WINDOW, options)
		if choice := end_dialog(ui, d); choice != .None do o.dialog = choice
	}
	if o.show_second {
		options := Dialog_Options {
			title   = "Quit Colophon?",
			primary = "Quit",
			cancel  = "Stay",
		}
		d := begin_dialog(ui, widget_id("Second"), WINDOW, options)
		if choice := end_dialog(ui, d); choice != .None do o.second = choice
	}
}

// The choice of the dialog's button that has the focus, if one has.
@(private = "file")
focused_choice :: proc(ui: ^Ui, dialog: Widget_Id) -> Dialog_Choice {
	for c in Dialog_Choice do if c != .None && ui.focus == child_id(dialog, "button", int(c)) do return c
	return .None
}

@(private = "file")
overlays_harness :: proc(h: ^Harness, o: ^Overlays) {
	o.field = make([dynamic]u8)
	harness_init(h, overlays_frame, o)
	run_frame(h)
}

@(private = "file")
destroy_overlays :: proc(h: ^Harness, o: ^Overlays) {
	harness_destroy(h)
	delete(o.field)
	free_all(context.temp_allocator)
}

@(test)
a_tooltip_shows_once_the_mouse_rests :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	move_mouse(&h, {600, 314})
	testing.expect(t, h.ui.wake_at <= h.ui.input.time + TOOLTIP_DELAY)
	drawn :: proc(h: ^Harness) -> bool {return len(h.renderer.lists[.Top].vertices) > 0}
	testing.expect(t, !drawn(&h))
	wait(&h, TOOLTIP_DELAY)
	testing.expect(t, drawn(&h))
	press(&h)
	testing.expect(t, !drawn(&h), "a press hides it")
}

@(test)
a_menu_item_is_chosen_by_click_or_by_keys :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	open_menu(&h.ui, widget_id("Menu"), {100, 100})
	run_frame(&h)
	testing.expect(t, click(&h, "Revert"))
	testing.expect_value(t, o.menu_chosen, 2)
	testing.expect(t, !is_menu_open(&h.ui, widget_id("Menu")))

	o.menu_chosen = nil
	open_menu(&h.ui, widget_id("Menu"), {100, 100})
	run_frame(&h)
	press_key(&h, .Down)
	press_key(&h, .Down)
	// The disabled item is skipped.
	testing.expect_value(t, h.ui.menu.highlighted, 2)
	press_key(&h, .Enter)
	testing.expect_value(t, o.menu_chosen, 2)
}

@(test)
a_disabled_item_or_a_click_elsewhere_chooses_nothing :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	open_menu(&h.ui, widget_id("Menu"), {100, 100})
	run_frame(&h)
	click(&h, "Show in Finder")
	testing.expect_value(t, o.menu_chosen, nil)
	testing.expect(t, is_menu_open(&h.ui, widget_id("Menu")))
	move_mouse(&h, {900, 700})
	press(&h)
	release(&h)
	testing.expect(t, !is_menu_open(&h.ui, widget_id("Menu")))
	press_key(&h, .Escape)
	testing.expect_value(t, o.menu_chosen, nil)
}

@(test)
a_menu_near_the_edge_opens_the_other_way :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	open_menu(&h.ui, widget_id("Menu"), {1270, 790})
	run_frame(&h)
	play, _ := find_widget(&h.ui, "Play")
	testing.expect(t, play.rect.x + play.rect.w <= 1270 && play.rect.y < 790)
}

@(test)
a_toast_reports_its_action_and_its_close :: proc(t: ^testing.T) {
	h: Harness
	o := Overlays {
		show_toast = true,
	}
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	click(&h, "Retry")
	testing.expect_value(t, o.toast, Toast_Result.Acted)
	click(&h, "Close")
	testing.expect_value(t, o.toast, Toast_Result.Closed)
}

@(test)
dialog_buttons_follow_the_platform :: proc(t: ^testing.T) {
	options := Dialog_Options {
		primary = "Save",
		cancel  = "Cancel",
		discard = "Don't Save",
	}
	left, right := dialog_buttons(options, .Mac)
	testing.expect(t, len(left) == 1 && left[0] == .Discard)
	testing.expect(t, len(right) == 2 && right[0] == .Cancel && right[1] == .Primary)
	left, right = dialog_buttons(options, .Windows)
	testing.expect_value(t, len(left), 0)
	testing.expect(t, len(right) == 3 && right[0] == .Primary && right[2] == .Cancel)
	free_all(context.temp_allocator)
}

@(test)
a_dialog_takes_the_clicks_and_the_keys_meant_for_the_window :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	click(&h, "Field")
	o.show_dialog = true
	run_frame(&h)
	type_text(&h, "x")
	testing.expect_value(t, o.field_changes, 0)
	move_mouse(&h, {600, 314})
	press(&h)
	release(&h)
	testing.expect_value(t, o.behind_clicks, 0)
	press_key(&h, .Enter)
	testing.expect_value(t, o.dialog, Dialog_Choice.Primary)
	o.dialog = .None
	press_key(&h, .Escape)
	testing.expect_value(t, o.dialog, Dialog_Choice.Cancel)
	click(&h, "Don't Save")
	testing.expect_value(t, o.dialog, Dialog_Choice.Discard)
}

@(test)
enter_never_chooses_a_destructive_button :: proc(t: ^testing.T) {
	h: Harness
	o := Overlays {
		show_dialog = true,
		destructive = true,
	}
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	press_key(&h, .Enter)
	testing.expect_value(t, o.dialog, Dialog_Choice.None)
}

@(test)
long_text_wraps_at_spaces :: proc(t: ^testing.T) {
	r := test_renderer(1)
	defer destroy_test_renderer(r)
	lines := wrap_text(
		r,
		"3 files have changes that are not saved yet",
		.Body,
		120,
		context.temp_allocator,
	)
	testing.expect(t, len(lines) >= 2)
	for line in lines do testing.expect(t, text_width(r, line, .Body) <= 120)
	testing.expect_value(t, lines[0][:1], "3")
	for width in ([]f32{90, 102, 131}) {
		for line in wrap_text(r, "Saved 3 files, kept 2 for later", .Body, width, context.temp_allocator) {
			testing.expectf(
				t,
				text_width(r, line, .Body) <= width,
				"%q is wider than %v",
				line,
				width,
			)
		}
	}
	// Narrower than a letter: a letter a line, never part of one.
	narrow := wrap_text(r, "été", .Body, 1, context.temp_allocator)
	testing.expect(
		t,
		len(narrow) == 3 && narrow[0] == "é" && narrow[1] == "t" && narrow[2] == "é",
	)
	paragraphs := wrap_text(r, "One.\nTwo.", .Body, 400, context.temp_allocator)
	testing.expect(t, len(paragraphs) == 2 && paragraphs[1] == "Two.")
}

@(test)
an_open_menu_takes_the_keys_and_the_click_that_closes_it :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	click(&h, "Field")
	open_menu(&h.ui, widget_id("Menu"), {100, 100})
	run_frame(&h)
	press_key(&h, .Down)
	testing.expect_value(t, h.ui.menu.highlighted, 0)
	type_text(&h, "x")
	testing.expect_value(t, o.field_changes, 0)
	press_key(&h, .Escape)
	testing.expect(t, !is_menu_open(&h.ui, widget_id("Menu")))
	testing.expect(t, has_focus(&h.ui, widget_id("Field")))

	open_menu(&h.ui, widget_id("Menu"), {100, 100})
	run_frame(&h)
	// Up from none goes to the last item.
	press_key(&h, .Up)
	testing.expect_value(t, h.ui.menu.highlighted, 3)
	testing.expect(t, click(&h, "Behind"))
	testing.expect(t, !is_menu_open(&h.ui, widget_id("Menu")))
	testing.expect_value(t, o.behind_clicks, 0)
}

@(test)
a_menu_is_declared_with_its_items_and_their_ticks :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	open_menu(&h.ui, widget_id("Menu"), {100, 100})
	run_frame(&h)
	m, declared := find_widget(&h.ui, "Track")
	testing.expect(t, declared && m.role == .Menu && m.parent == 0)
	year, _ := find_widget(&h.ui, "Year")
	testing.expect_value(t, year.parent, widget_id("Menu"))
	testing.expect(t, .Checkable in year.states && .Checked in year.states)
}

@(test)
a_menu_its_owner_no_longer_draws_closes :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	open_menu(&h.ui, widget_id("Other menu"), {100, 100})
	// The frame it opens in may draw it after asking for it.
	run_frame(&h)
	testing.expect(t, h.ui.menu.open)
	run_frame(&h)
	testing.expect(t, !h.ui.menu.open)
}

@(test)
tab_goes_into_a_dialog_and_the_focus_comes_back_after :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	click(&h, "Field")
	o.show_dialog = true
	run_frame(&h)
	run_frame(&h)
	press_key(&h, .Tab)
	dialog := widget_id("Dialog")
	focused := focused_choice(&h.ui, dialog)
	testing.expect(t, focused != .None)
	// Enter presses the focused button, whichever it is.
	press_key(&h, .Enter)
	testing.expect_value(t, o.dialog, focused)
	o.show_dialog = false
	run_frame(&h)
	run_frame(&h)
	testing.expect(t, has_focus(&h.ui, widget_id("Field")))
}

@(test)
the_dialog_on_top_takes_the_keys :: proc(t: ^testing.T) {
	h: Harness
	o := Overlays {
		show_dialog = true,
		show_second = true,
	}
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	run_frame(&h)
	press_key(&h, .Escape)
	testing.expect_value(t, o.second, Dialog_Choice.Cancel)
	testing.expect_value(t, o.dialog, Dialog_Choice.None)
}

@(test)
a_dialog_and_a_toast_are_declared_once_each :: proc(t: ^testing.T) {
	h: Harness
	o := Overlays {
		show_dialog = true,
		show_toast  = true,
	}
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	run_frame(&h)
	for w in h.ui.widgets do testing.expectf(t, w.parent != w.id, "%q is its own parent", w.label)
	dialog, _ := find_widget(&h.ui, "Save the changes?")
	testing.expect(t, dialog.role == .Dialog && dialog.parent == 0)
}

@(test)
a_dialog_under_a_toast_still_blocks_the_wheel :: proc(t: ^testing.T) {
	h: Harness
	o := Overlays {
		show_dialog = true,
		show_toast  = true,
	}
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	move_mouse(&h, {600, 314})
	testing.expect(t, mouse_in_popup(&h.ui))
	testing.expect_value(t, len(h.ui.popups), 2)
}

@(test)
a_toolbar_button_shows_its_tooltip_until_pressed :: proc(t: ^testing.T) {
	h: Harness
	o: Overlays
	overlays_harness(&h, &o)
	defer destroy_overlays(&h, &o)
	move_mouse(&h, {34, 34})
	testing.expect(t, h.ui.wake_at <= h.ui.input.time + TOOLTIP_DELAY)
	press(&h)
	release(&h)
	testing.expect_value(t, h.ui.tooltip_hidden, widget_id("Sidebar"))
	move_mouse(&h, {300, 300})
	testing.expect_value(t, h.ui.tooltip_hidden, 0)
}

@(test)
a_toast_fits_a_narrow_window :: proc(t: ^testing.T) {
	h: Harness
	narrow_frame :: proc(ui: ^Ui, data: rawptr) {
		message := "12 files could not be saved, they keep their changes"
		toast(ui, widget_id("Toast"), {0, 0, 240, 400}, .Error, message, "Retry")
	}
	harness_init(&h, narrow_frame)
	defer destroy_overlays_harness(&h)
	run_frame(&h)
	for w in h.ui.widgets do testing.expectf(t, w.rect.x >= 0 && w.rect.x + w.rect.w <= 240, "%q leaves the window", w.label)
}

@(private = "file")
destroy_overlays_harness :: proc(h: ^Harness) {
	harness_destroy(h)
	free_all(context.temp_allocator)
}

// A menu, a tooltip, the toasts and a dialog over its scrim, in both themes.
@(test)
the_overlays_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{1000, 420}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	for kind, i in Theme_Kind {
		area := Rect{f32(i) * size.x / 2, 0, size.x / 2, size.y}
		ui: Ui
		ui_init(&ui, cap.renderer, theme(kind))
		ui.viewport = area
		fill_rect(cap.renderer, area, ui.theme.surface_1)
		open_menu(&ui, widget_id("Menu"), {area.x + 16, 16})
		ui.menu.highlighted = 0
		menu(&ui, widget_id("Menu"), MENU_ITEMS)
		ui.hot = widget_id("Tip")
		ui.input.time = 10
		tooltip(&ui, widget_id("Tip"), {area.x + 300, 16, 28, 28}, "Toggle sidebar  ⌥⌘S")
		toast(&ui, widget_id("Saved"), {area.x + 220, 0, 280, 130}, .Success, "Saved 3 files")
		toast(
			&ui,
			widget_id("Failed"),
			{area.x, 0, area.w, 212},
			.Error,
			"2 files could not be saved",
			"Retry",
		)
		options := Dialog_Options {
			title    = "Save the changes?",
			message  = "3 files have changes that are not saved. Saving writes their tags.",
			primary  = "Save",
			cancel   = "Cancel",
			discard  = "Don't Save",
			// The same capture on every system.
			platform = .Mac,
		}
		dialog_window := Rect{area.x, 200, area.w, 220}
		end_dialog(&ui, begin_dialog(&ui, widget_id("Dialog"), dialog_window, options))
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "overlays.png")
}

@(private = "file")
Plain :: struct {
	message:  string,
	below_by: f32,
}

@(private = "file")
plain_frame :: proc(ui: ^Ui, data: rawptr) {
	p := (^Plain)(data)
	d := begin_dialog(
		ui,
		widget_id("Plain"),
		WINDOW,
		{title = "Settings", message = p.message, primary = "Done"},
	)
	p.below_by = d.content.y - d.box.y
	end_dialog(ui, d)
}

@(private = "file")
untitled_frame :: proc(ui: ^Ui, data: rawptr) {
	p := (^Plain)(data)
	d := begin_dialog(ui, widget_id("Untitled"), WINDOW, {label = "About", primary = "Close"})
	p.below_by = d.content.y - d.box.y
	end_dialog(ui, d)
}

// A dialog without a title or a message starts its content at its top, and is still
// named for assistive technologies by its label.
@(test)
a_dialog_without_a_title_starts_its_content_at_its_top :: proc(t: ^testing.T) {
	titled_harness: Harness
	titled: Plain
	harness_init(&titled_harness, plain_frame, &titled)
	defer harness_destroy(&titled_harness)
	run_frame(&titled_harness)
	h: Harness
	p: Plain
	harness_init(&h, untitled_frame, &p)
	defer harness_destroy(&h)
	run_frame(&h)
	testing.expect(t, p.below_by < titled.below_by)
	_, named := find_widget(&h.ui, "About")
	testing.expect(t, named)
}

// A dialog without a message holds its content right under its title.
@(test)
a_dialog_without_a_message_holds_its_content_under_its_title :: proc(t: ^testing.T) {
	h: Harness
	p: Plain
	harness_init(&h, plain_frame, &p)
	defer harness_destroy(&h)
	run_frame(&h)
	bare := p.below_by
	p.message = "A line of explanation."
	run_frame(&h)
	testing.expect(t, bare > 0 && p.below_by > bare)
	// The padding, a title line and the gap: no empty message line.
	testing.expect_value(t, bare, 50)
	free_all(context.temp_allocator)
}
