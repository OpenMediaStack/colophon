package ui

import "core:testing"

@(private = "file")
Pane :: struct {
	outer, inner:  Scroll,
	content:       [2]f32,
	inner_content: [2]f32,
}

@(private = "file")
OUTER :: Rect{0, 0, 300, 200}
@(private = "file")
INNER :: Rect{20, 20, 100, 80}

@(private = "file")
pane_frame :: proc(ui: ^Ui, data: rawptr) {
	p := (^Pane)(data)
	outer := widget_id("Outer")
	begin_scroll(ui, outer, OUTER, p.content, &p.outer)
	inner := widget_id("Inner")
	begin_scroll(ui, inner, INNER, p.inner_content, &p.inner)
	end_scroll(ui, inner, INNER, p.inner_content, &p.inner)
	end_scroll(ui, outer, OUTER, p.content, &p.outer)
}

@(private = "file")
pane_harness :: proc(h: ^Harness, p: ^Pane, content := [2]f32{600, 1000}) {
	p.content = content
	if p.inner_content == {} do p.inner_content = {100, 400}
	harness_init(h, pane_frame, p)
	run_frame(h)
}

@(private = "file")
scroll_wheel :: proc(h: ^Harness, at: [2]f32, wheel: [2]f32, modifiers := Modifiers{}) {
	move_mouse(h, at)
	h.ui.input.wheel = wheel
	h.ui.input.modifiers = modifiers
	run_frame(h)
	h.ui.input.modifiers = {}
}

@(test)
the_wheel_scrolls_the_innermost_area_under_the_mouse :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p)
	defer harness_destroy(&h)
	scroll_wheel(&h, {50, 50}, {0, 30})
	testing.expect_value(t, p.inner.offset.y, 30)
	testing.expect_value(t, p.outer.offset.y, 0)
	scroll_wheel(&h, {200, 150}, {0, 5000})
	// Clamped to the content, and the room of the horizontal bar under it.
	testing.expect_value(t, p.outer.offset.y, 810)
}

@(test)
an_area_that_cannot_scroll_leaves_the_wheel_to_the_one_around_it :: proc(t: ^testing.T) {
	h: Harness
	p := Pane {
		inner_content = {100, 50},
	}
	pane_harness(&h, &p)
	defer harness_destroy(&h)
	scroll_wheel(&h, {50, 50}, {0, 30})
	testing.expect_value(t, p.outer.offset.y, 30)
	// Sideways, the inner area cannot scroll either.
	scroll_wheel(&h, {50, 50}, {0, 20}, {.Shift})
	testing.expect_value(t, p.outer.offset, [2]f32{20, 30})
}

@(test)
the_offset_follows_content_that_shrinks :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p)
	defer harness_destroy(&h)
	scroll_wheel(&h, {200, 150}, {0, 700})
	p.content = {300, 300}
	run_frame(&h)
	testing.expect_value(t, p.outer.offset.y, 100)
}

@(test)
both_bars_stop_short_of_each_other :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p)
	defer harness_destroy(&h)
	run_frame(&h)
	bars: [2]Rect
	for w in h.ui.widgets {
		for axis in 0 ..< 2 do if w.id == child_id(widget_id("Outer"), "scroll bar", axis) do bars[axis] = w.rect
	}
	testing.expect_value(t, bars[1], Rect{290, 0, 10, 190})
	testing.expect_value(t, bars[0], Rect{0, 190, 290, 10})
}

@(test)
dragging_the_horizontal_thumb_scrolls_sideways :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p, {1200, 200})
	defer harness_destroy(&h)
	// The thumb is 300 / 1200 of the 300 point track, 75 points, at its left.
	move_mouse(&h, {30, 195})
	press(&h)
	move_mouse(&h, {105, 195})
	release(&h)
	// 75 points of the 225 the thumb travels are a third of the 900 the content scrolls.
	testing.expect_value(t, p.outer.offset.x, 300)
}

@(test)
shift_turns_the_wheel_sideways :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p)
	defer harness_destroy(&h)
	scroll_wheel(&h, {200, 150}, {0, 40}, {.Shift})
	testing.expect_value(t, p.outer.offset, [2]f32{40, 0})
}

@(test)
scroll_bars_show_only_where_the_content_does_not_fit :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p, {300, 1000})
	defer harness_destroy(&h)
	run_frame(&h)
	_, vertical := find_widget(&h.ui, "Vertical scroll bar")
	testing.expect(t, vertical)
	horizontal := 0
	for w in h.ui.widgets do if w.label == "Horizontal scroll bar" do horizontal += 1
	testing.expect_value(t, horizontal, 0)
}

@(test)
dragging_the_thumb_scrolls_in_proportion :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p, {300, 1000})
	defer harness_destroy(&h)
	// The thumb is 200 / 1000 of the 200 point track, 40 points, at its top.
	move_mouse(&h, {295, 10})
	press(&h)
	move_mouse(&h, {295, 90})
	release(&h)
	// 80 points of the 160 the thumb travels are half of the 800 the content scrolls.
	testing.expect_value(t, p.outer.offset.y, 400)
}

@(test)
a_click_on_the_track_brings_the_thumb_under_it :: proc(t: ^testing.T) {
	h: Harness
	p: Pane
	pane_harness(&h, &p, {300, 1000})
	defer harness_destroy(&h)
	move_mouse(&h, {295, 180})
	press(&h)
	release(&h)
	testing.expect_value(t, p.outer.offset.y, 800)
}

@(test)
a_span_scrolls_into_view_the_least_it_can :: proc(t: ^testing.T) {
	s: Scroll
	scroll_into_view(&s, 300, 26, 200)
	testing.expect_value(t, s.offset.y, 126)
	scroll_into_view(&s, 140, 26, 200)
	testing.expect_value(t, s.offset.y, 126)
	scroll_into_view(&s, 100, 26, 200)
	testing.expect_value(t, s.offset.y, 100)
	// Longer than the view: its start shows.
	scroll_into_view(&s, 400, 500, 200)
	testing.expect_value(t, s.offset.y, 400)
}

// The thumb in its states, in both themes.
@(test)
the_scroll_bars_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{240, 240}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	for kind, i in Theme_Kind {
		th := theme(kind)
		area := Rect{f32(i) * size.x / 2, 0, size.x / 2, size.y}
		fill_rect(cap.renderer, area, th.surface_1)
		states := [?]Button_States{{}, {.Hovered}, {.Pressed}}
		for state, k in states {
			x := area.x + 20 + f32(k) * 30
			draw_scroll_thumb(cap.renderer, th, {x + 2, 16, SCROLL_BAR - 4, 60}, state)
		}
		draw_scroll_thumb(cap.renderer, th, {area.x + 12, 102, 80, SCROLL_BAR - 4}, {})
		// An area scrolled to its end both ways: the content stops short of the bars.
		ui: Ui
		ui_init(&ui, cap.renderer, th)
		rect := Rect{area.x + 12, 124, 96, 96}
		content := [2]f32{200, 200}
		s := Scroll {
			offset = {1000, 1000},
		}
		origin := begin_scroll(&ui, widget_id("Both"), rect, content, &s)
		fill_rect(cap.renderer, {origin.x, origin.y, content.x, content.y}, th.surface_3)
		fill_rect(
			cap.renderer,
			{origin.x + 4, origin.y + 4, content.x - 8, content.y - 8},
			th.surface_2,
		)
		end_scroll(&ui, widget_id("Both"), rect, content, &s)
		stroke_rect(cap.renderer, rect, th.border_subtle)
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "scroll-bars.png")
}
