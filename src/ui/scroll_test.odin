package ui

import "core:testing"

@(private = "file")
Pane :: struct {
	outer, inner: Scroll,
	content:      [2]f32,
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
	begin_scroll(ui, inner, INNER, {100, 400}, &p.inner)
	end_scroll(ui, inner, INNER, {100, 400}, &p.inner)
	end_scroll(ui, outer, OUTER, p.content, &p.outer)
}

@(private = "file")
pane_harness :: proc(h: ^Harness, p: ^Pane, content := [2]f32{600, 1000}) {
	p.content = content
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
	// Clamped to the content.
	testing.expect_value(t, p.outer.offset.y, 800)
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
}

// The thumb in its states, in both themes.
@(test)
the_scroll_bars_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{240, 120}
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
		draw_scroll_thumb(cap.renderer, th, {area.x + 12, size.y - 18, 80, SCROLL_BAR - 4}, {})
	}
	finish_capture(t, &cap, "scroll-bars.png")
}
