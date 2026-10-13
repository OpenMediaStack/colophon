package ui

import "core:testing"

@(private = "file")
Overlays :: struct {
	menu_chosen:   Maybe(int),
	toast:         Toast_Result,
	dialog:        Dialog_Choice,
	show_dialog:   bool,
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
	if chosen, ok := menu(ui, widget_id("Menu"), MENU_ITEMS).?; ok do o.menu_chosen = chosen
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
		begin_dialog(ui, widget_id("Dialog"), WINDOW, options)
		if choice := end_dialog(ui, widget_id("Dialog"), WINDOW, options); choice != .None do o.dialog = choice
	}
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
		toast(&ui, widget_id("Saved"), {area.x, 0, area.w, 160}, .Success, "Saved 3 files")
		toast(
			&ui,
			widget_id("Failed"),
			{area.x, 0, area.w, 220},
			.Error,
			"2 files could not be saved",
			"Retry",
		)
		options := Dialog_Options {
			title   = "Save the changes?",
			message = "3 files have changes that are not saved. Saving writes their tags.",
			primary = "Save",
			cancel  = "Cancel",
			discard = "Don't Save",
		}
		dialog_window := Rect{area.x, 200, area.w, 220}
		begin_dialog(&ui, widget_id("Dialog"), dialog_window, options)
		end_dialog(&ui, widget_id("Dialog"), dialog_window, options)
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "overlays.png")
}
