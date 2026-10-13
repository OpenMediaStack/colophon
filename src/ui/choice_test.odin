package ui

import "core:testing"

@(private = "file")
Settings :: struct {
	keep_id3v1: bool,
	version:    Maybe(int),
	disabled:   bool,
}

@(private = "file")
VERSIONS := []Segment{{"2.2", true}, {"2.3", true}, {"2.4", true}}

@(private = "file")
settings_frame :: proc(ui: ^Ui, data: rawptr) {
	s := (^Settings)(data)
	if checkbox(
		ui,
		widget_id("Keep ID3v1"),
		{10, 10, 160, 20},
		"Keep ID3v1",
		s.keep_id3v1,
		s.disabled,
	) {
		s.keep_id3v1 = !s.keep_id3v1
	}
	if chosen, ok := segmented(
		   ui,
		   widget_id("ID3v2"),
		   {10, 40, 180, 28},
		   "ID3v2",
		   VERSIONS,
		   s.version,
		   s.disabled,
	   ).?; ok {
		s.version = chosen
	}
}

@(test)
a_checkbox_toggles_by_click_and_by_space :: proc(t: ^testing.T) {
	h: Harness
	s: Settings
	harness_init(&h, settings_frame, &s)
	defer harness_destroy(&h)
	run_frame(&h)
	click(&h, "Keep ID3v1")
	testing.expect(t, s.keep_id3v1)
	run_frame(&h)
	info, _ := find_widget(&h.ui, "Keep ID3v1")
	testing.expect(t, info.role == .Check_Box && .Checked in info.states)
	request_focus(&h.ui, widget_id("Keep ID3v1"))
	ui_end_frame(&h.ui)
	press_key(&h, .Space)
	testing.expect(t, !s.keep_id3v1)
}

@(test)
a_segment_is_chosen_by_click_and_by_the_arrows :: proc(t: ^testing.T) {
	h: Harness
	s := Settings {
		version = 2,
	}
	harness_init(&h, settings_frame, &s)
	defer harness_destroy(&h)
	run_frame(&h)
	click(&h, "2.3")
	testing.expect_value(t, s.version, 1)
	testing.expect(t, has_focus(&h.ui, widget_id("ID3v2")))
	press_key(&h, .Left)
	testing.expect_value(t, s.version, 0)
	press_key(&h, .Left)
	testing.expect_value(t, s.version, 0)
	info, _ := find_widget(&h.ui, "2.2")
	testing.expect(t, .Checked in info.states)
}

@(test)
disabled_choices_do_nothing :: proc(t: ^testing.T) {
	h: Harness
	s := Settings {
		disabled = true,
	}
	harness_init(&h, settings_frame, &s)
	defer harness_destroy(&h)
	run_frame(&h)
	click(&h, "Keep ID3v1")
	click(&h, "2.4")
	testing.expect(t, !s.keep_id3v1)
	testing.expect_value(t, s.version, nil)
}

// The checkbox and the segmented control in every state, in both themes.
@(test)
the_choices_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{520, 200}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	for kind, i in Theme_Kind {
		th := theme(kind)
		area := Rect{f32(i) * size.x / 2, 0, size.x / 2, size.y}
		r := cap.renderer
		fill_rect(r, area, th.surface_1)
		states := [?]Button_States {
			{},
			{.Hovered},
			{.Checked},
			{.Checked, .Hovered},
			{.Focused},
			{.Disabled},
			{.Checked, .Disabled},
		}
		for state, k in states {
			x := area.x + 16 + f32(k % 2) * 120
			y := 12 + f32(k / 2) * 28
			draw_checkbox(r, th, {x, y, 110, 20}, "Keep ID3v1", state)
		}
		ui: Ui
		ui_init(&ui, r, th)
		segmented(&ui, widget_id("Versions"), {area.x + 16, 128, 200, 28}, "ID3v2", VERSIONS, 2)
		segmented(&ui, widget_id("Mixed"), {area.x + 16, 162, 200, 28}, "Mixed", VERSIONS, nil)
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "choices.png")
}
