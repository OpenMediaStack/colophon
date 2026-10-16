package ui

import "core:testing"

@(private = "file")
Bar :: struct {
	value:    f32,
	disabled: bool,
	moves:    int,
}

@(private = "file")
BAR :: Rect{100, 50, 200, SLIDER_HEIGHT}

@(private = "file")
bar_frame :: proc(ui: ^Ui, data: rawptr) {
	b := (^Bar)(data)
	if moved, did := slider(ui, widget_id("Bar"), BAR, "Position", b.value, b.disabled).?; did {
		b.value = moved
		b.moves += 1
	}
}

@(private = "file")
bar_harness :: proc(h: ^Harness, b: ^Bar) {
	harness_init(h, bar_frame, b)
	run_frame(h)
}

@(test)
a_click_gives_the_value_under_the_mouse :: proc(t: ^testing.T) {
	h: Harness
	b: Bar
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	move_mouse(&h, {200, 58})
	press(&h)
	release(&h)
	testing.expect_value(t, b.value, 0.5)
	move_mouse(&h, {100, 58})
	press(&h)
	release(&h)
	testing.expect_value(t, b.value, 0)
	slider_info, found := find_widget(&h.ui, "Position")
	testing.expect(t, found)
	testing.expect_value(t, slider_info.role, Role.Slider)
	testing.expect_value(t, slider_info.value, "0")
}

@(test)
a_drag_follows_the_mouse_even_outside_the_bar :: proc(t: ^testing.T) {
	h: Harness
	b: Bar
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	move_mouse(&h, {120, 58})
	press(&h)
	testing.expect_value(t, b.value, 0.1)
	move_mouse(&h, {250, 300})
	testing.expect_value(t, b.value, 0.75)
	// Past the ends it stops at them.
	move_mouse(&h, {900, 58})
	testing.expect_value(t, b.value, 1)
	move_mouse(&h, {-50, 58})
	testing.expect_value(t, b.value, 0)
	release(&h)
}

@(test)
the_arrow_keys_home_and_end_move_it_with_the_focus :: proc(t: ^testing.T) {
	h: Harness
	b := Bar {
		value = 0.5,
	}
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	// The keyboard reaches it with the focus, which a click does not give.
	request_focus(&h.ui, widget_id("Bar"))
	ui_end_frame(&h.ui)
	run_frame(&h)
	press_key(&h, .Right)
	testing.expect(t, abs(b.value - 0.55) < 1e-5)
	press_key(&h, .Left)
	press_key(&h, .Left)
	testing.expect(t, abs(b.value - 0.45) < 1e-5)
	press_key(&h, .End)
	testing.expect_value(t, b.value, 1)
	press_key(&h, .Right)
	testing.expect_value(t, b.value, 1)
	press_key(&h, .Home)
	testing.expect_value(t, b.value, 0)
	press_key(&h, .Left)
	testing.expect_value(t, b.value, 0)
}

@(test)
a_disabled_slider_does_nothing :: proc(t: ^testing.T) {
	h: Harness
	b := Bar {
		value    = 0.3,
		disabled = true,
	}
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	move_mouse(&h, {250, 58})
	press(&h)
	release(&h)
	press_key(&h, .Right)
	testing.expect_value(t, b.value, 0.3)
	testing.expect_value(t, b.moves, 0)
	info, _ := find_widget(&h.ui, "Position")
	testing.expect(t, .Disabled in info.states)
	testing.expect_value(t, info.value, "30")
}

@(test)
a_value_out_of_range_is_kept_within_it :: proc(t: ^testing.T) {
	h: Harness
	b := Bar {
		value = 7,
	}
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	info, _ := find_widget(&h.ui, "Position")
	testing.expect_value(t, info.value, "100")
}

// What the bar shows can move on while the mouse is held still, as a playing track's
// position does: only a mouse that moves asks for a new position, not each frame.
@(test)
a_held_mouse_that_does_not_move_asks_once :: proc(t: ^testing.T) {
	h: Harness
	b: Bar
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	move_mouse(&h, {200, 58})
	press(&h)
	testing.expect_value(t, b.moves, 1)
	for _ in 0 ..< 4 {
		b.value += 0.1
		run_frame(&h)
	}
	testing.expect_value(t, b.moves, 1)
	move_mouse(&h, {250, 58})
	testing.expect_value(t, b.moves, 2)
	testing.expect_value(t, b.value, 0.75)
	release(&h)
}

// A click on a bar leaves the focus where it was: the keys go on doing what they did.
@(test)
a_click_does_not_take_the_focus :: proc(t: ^testing.T) {
	h: Harness
	b := Bar {
		value = 0.5,
	}
	bar_harness(&h, &b)
	defer harness_destroy(&h)
	move_mouse(&h, {150, 58})
	press(&h)
	release(&h)
	before := b.value
	press_key(&h, .Right)
	testing.expect_value(t, b.value, before)
}
