package ui

import "core:testing"
import sdl "vendor:sdl3"

// What the test widgets of a frame report.
@(private = "file")
Board :: struct {
	clicked:        map[string]int,
	double_clicked: map[string]int,
	hovered:        map[string]bool,
	// An overlay drawn over the first button, last.
	overlay:        bool,
	// A scrim drawn over everything, last.
	scrim:          bool,
	// Drawn inside a clip that leaves the second button out.
	clipped:        bool,
	// Asks for the focus for this field during the frame.
	focus_request:  string,
	// Releases the focus of this field during the frame, after the request.
	focus_release:  string,
	keys_seen:      [2]bool,
}

@(private = "file")
test_button :: proc(ui: ^Ui, b: ^Board, label: string, rect: Rect) {
	id := widget_id(label)
	result := interact(ui, id, rect)
	declare(ui, {id = id, role = .Button, label = label, rect = rect})
	if .Clicked in result do b.clicked[label] += 1
	if .Double_Clicked in result do b.double_clicked[label] += 1
	b.hovered[label] = .Hovered in result
}

@(private = "file")
board_frame :: proc(ui: ^Ui, data: rawptr) {
	b := (^Board)(data)
	if b.clipped do push_clip(ui.renderer, {0, 0, 100, 100})
	test_button(ui, b, "First", {10, 10, 80, 30})
	test_button(ui, b, "Second", {10, 110, 80, 30})
	if b.clipped do pop_clip(ui.renderer)
	if b.overlay do test_button(ui, b, "Overlay", {0, 0, 100, 50})
	if b.scrim do block_mouse(ui, {0, 0, 1000, 1000})
	if b.focus_request != "" do request_focus(ui, widget_id(b.focus_request))
	if b.focus_release != "" do release_focus(ui, widget_id(b.focus_release))
	b.keys_seen[0] = take_key(ui, .Enter)
	b.keys_seen[1] = take_key(ui, .Enter)
}

@(private = "file")
board_harness :: proc(h: ^Harness, b: ^Board) {
	b.clicked = make(map[string]int, context.temp_allocator)
	b.double_clicked = make(map[string]int, context.temp_allocator)
	b.hovered = make(map[string]bool, context.temp_allocator)
	harness_init(h, board_frame, b)
	run_frame(h)
}

@(private = "file")
destroy_board :: proc(h: ^Harness) {
	harness_destroy(h)
	free_all(context.temp_allocator)
}

@(test)
widget_ids_are_stable_and_never_0 :: proc(t: ^testing.T) {
	testing.expect_value(t, widget_id("Save"), widget_id("Save"))
	testing.expect(t, widget_id("Save") != widget_id("Save", 1))
	testing.expect(t, widget_id("Save") != widget_id("Open"))
	testing.expect(
		t,
		child_id(widget_id("Row", 1), "Title") != child_id(widget_id("Row", 2), "Title"),
	)
	testing.expect(t, widget_id("") != 0)
}

@(test)
a_widget_is_clicked_by_its_label :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	testing.expect(t, click(&h, "Second"))
	testing.expect_value(t, b.clicked["Second"], 1)
	testing.expect_value(t, b.clicked["First"], 0)
	testing.expect(t, !click(&h, "Nothing"))
}

@(test)
hover_takes_a_frame_and_the_widget_drawn_last_wins :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	b.overlay = true
	h.ui.input.mouse = {20, 20}
	run_frame(&h)
	testing.expect(t, !b.hovered["Overlay"], "hover is resolved from the previous frame")
	run_frame(&h)
	testing.expect(t, b.hovered["Overlay"])
	testing.expect(t, !b.hovered["First"])
	press(&h)
	release(&h)
	testing.expect_value(t, b.clicked["Overlay"], 1)
	testing.expect_value(t, b.clicked["First"], 0)
}

@(test)
a_press_dragged_away_clicks_nothing :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	move_mouse(&h, {20, 20})
	press(&h)
	move_mouse(&h, {20, 120})
	testing.expect(t, !b.hovered["Second"], "another widget is active")
	release(&h)
	testing.expect_value(t, b.clicked["First"], 0)
	testing.expect_value(t, b.clicked["Second"], 0)
	run_frame(&h)
	testing.expect(t, b.hovered["Second"])
}

@(test)
a_double_click_is_reported :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	click(&h, "First", clicks = 2)
	testing.expect_value(t, b.clicked["First"], 2)
	testing.expect_value(t, b.double_clicked["First"], 1)
}

@(test)
a_scrim_takes_the_mouse :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	b.scrim = true
	click(&h, "First")
	testing.expect_value(t, b.clicked["First"], 0)
}

@(test)
the_mouse_outside_the_clip_hovers_nothing :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	b.clipped = true
	click(&h, "Second")
	testing.expect_value(t, b.clicked["Second"], 0)
	click(&h, "First")
	testing.expect_value(t, b.clicked["First"], 1)
}

@(test)
the_focus_moves_between_frames :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	b.focus_request = "Field"
	ui_begin_frame(&h.ui, 1)
	board_frame(&h.ui, &b)
	testing.expect(t, !has_focus(&h.ui, widget_id("Field")), "not before the frame ends")
	ui_end_frame(&h.ui)
	testing.expect(t, has_focus(&h.ui, widget_id("Field")))
}

@(test)
losing_the_focus_never_cancels_another_request :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	b.focus_request = "One"
	run_frame(&h)
	b.focus_request = "Two"
	b.focus_release = "One"
	run_frame(&h)
	testing.expect(t, has_focus(&h.ui, widget_id("Two")))
	b.focus_request = ""
	b.focus_release = "Two"
	run_frame(&h)
	testing.expect_value(t, h.ui.focus, 0)
}

@(test)
a_key_taken_is_seen_once :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	press_key(&h, .Enter)
	testing.expect_value(t, b.keys_seen, [2]bool{true, false})
	press_key(&h, .Enter, COMMAND)
	testing.expect_value(t, b.keys_seen, [2]bool{false, false})
}

@(test)
sdl_events_become_input :: proc(t: ^testing.T) {
	input: Input
	defer {
		delete(input.keys)
		delete(input.text.buf)
	}
	event: sdl.Event
	event.type = .MOUSE_BUTTON_DOWN
	event.button = {
		type   = .MOUSE_BUTTON_DOWN,
		button = sdl.BUTTON_LEFT,
		down   = true,
		clicks = 2,
		x      = 12,
		y      = 34,
	}
	testing.expect_value(t, input_from_sdl(&input, &event), Event_Use.Taken)
	testing.expect_value(t, input.mouse, [2]f32{12, 34})
	testing.expect(t, .Left in input.pressed && .Left in input.down)
	testing.expect_value(t, input.clicks, 2)

	event = {}
	event.key = {
		type = .KEY_DOWN,
		key  = sdl.K_S,
		mod  = {.LGUI, .LSHIFT},
		down = true,
	}
	testing.expect_value(t, input_from_sdl(&input, &event), Event_Use.Taken)
	testing.expect_value(t, input.keys[0], Key_Press{.S, {.Super, .Shift}, false, 0})

	event = {}
	event.text = {
		type = .TEXT_INPUT,
		text = "é",
	}
	testing.expect_value(t, input_from_sdl(&input, &event), Event_Use.Taken)
	testing.expect_value(t, string(input.text.buf[:]), "é")

	event = {}
	event.wheel = {
		type      = .MOUSE_WHEEL,
		y         = 1,
		direction = .FLIPPED,
	}
	testing.expect_value(t, input_from_sdl(&input, &event), Event_Use.Taken)
	testing.expect_value(t, input.wheel, [2]f32{0, -WHEEL_POINTS})
}

@(test)
a_rectangle_is_centered_on_whole_points :: proc(t: ^testing.T) {
	testing.expect_value(t, rect_center({10, 20, 100, 50}), [2]f32{60, 45})
	testing.expect_value(t, centered({0, 0, 101, 51}, 16, 16), Rect{42, 17, 16, 16})
}

@(private = "file")
motion :: proc(x, y: f32) -> (e: sdl.Event) {
	e.motion = {
		type = .MOUSE_MOTION,
		x    = x,
		y    = y,
	}
	return
}

@(private = "file")
button_event :: proc(down: bool, x, y: f32) -> (e: sdl.Event) {
	e.button = {
		type   = down ? .MOUSE_BUTTON_DOWN : .MOUSE_BUTTON_UP,
		button = sdl.BUTTON_LEFT,
		down   = down,
		clicks = 1,
		x      = x,
		y      = y,
	}
	return
}

@(test)
a_press_after_a_move_waits_for_the_next_frame :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	// The mouse comes over Second and presses in one burst of events, as a fast
	// move-and-click does: the loop feeds what waits to the next frame.
	events := [?]sdl.Event {
		motion(20, 120),
		button_event(true, 20, 120),
		button_event(false, 20, 120),
	}
	pending := events[:]
	for len(pending) > 0 {
		for len(pending) > 0 {
			use := input_from_sdl(&h.ui.input, &pending[0])
			if use == .Wait do break
			pending = pending[1:]
		}
		run_frame(&h)
	}
	run_frame(&h)
	testing.expect_value(t, b.clicked["Second"], 1)
}

@(test)
mouse_positions_become_points :: proc(t: ^testing.T) {
	input: Input
	defer {
		delete(input.keys)
		delete(input.text.buf)
	}
	e := motion(150, 300)
	input_from_sdl(&input, &e, 1 / 1.5)
	testing.expect_value(t, input.mouse, [2]f32{100, 200})
}

@(test)
a_click_lost_with_the_window_s_focus_clicks_nothing :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	move_mouse(&h, {20, 20})
	press(&h)
	lost: sdl.Event
	lost.type = .WINDOW_FOCUS_LOST
	testing.expect_value(t, input_from_sdl(&h.ui.input, &lost), Event_Use.Other)
	run_frame(&h)
	testing.expect_value(t, h.ui.active, 0)
	testing.expect_value(t, b.clicked["First"], 0)
	left: sdl.Event
	left.type = .WINDOW_MOUSE_LEAVE
	input_from_sdl(&h.ui.input, &left)
	run_frame(&h)
	run_frame(&h)
	testing.expect(t, !b.hovered["First"])
}

@(test)
a_release_and_a_press_in_one_frame_keep_the_second_click :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	move_mouse(&h, {20, 20})
	press(&h)
	h.ui.input.released += {.Left}
	h.ui.input.pressed += {.Left}
	h.ui.input.clicks = 2
	run_frame(&h)
	release(&h)
	testing.expect_value(t, b.clicked["First"], 2)
}

@(test)
a_double_click_needs_both_presses_on_the_widget :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	click(&h, "First")
	click(&h, "Second", clicks = 2)
	testing.expect_value(t, b.double_clicked["Second"], 1)
	move_mouse(&h, {20, 20})
	press(&h, .Left, 2)
	release(&h)
	testing.expect_value(t, b.double_clicked["First"], 0)
}

@(test)
the_focus_goes_with_its_widget :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	request_focus(&h.ui, widget_id("First"))
	ui_end_frame(&h.ui)
	run_frame(&h)
	testing.expect(t, has_focus(&h.ui, widget_id("First")))
	request_focus(&h.ui, widget_id("Gone"))
	ui_end_frame(&h.ui)
	run_frame(&h)
	testing.expect_value(t, h.ui.focus, 0)
}

@(test)
a_widget_on_a_higher_layer_keeps_the_mouse :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, proc(ui: ^Ui, data: rawptr) {
			hovered := (^[2]bool)(data)
			previous := set_layer(ui.renderer, .Overlay)
			hovered[0] = .Hovered in interact(ui, widget_id("Over"), {0, 0, 100, 100})
			set_layer(ui.renderer, previous)
			hovered[1] = .Hovered in interact(ui, widget_id("Under"), {0, 0, 100, 100})
		}, nil)
	defer harness_destroy(&h)
	hovered: [2]bool
	h.data = &hovered
	move_mouse(&h, {50, 50})
	testing.expect_value(t, hovered, [2]bool{true, false})
}

@(test)
a_held_key_repeats_only_where_asked :: proc(t: ^testing.T) {
	h: Harness
	b: Board
	board_harness(&h, &b)
	defer destroy_board(&h)
	append(&h.ui.input.keys, Key_Press{.Enter, {}, true, 0})
	ui_begin_frame(&h.ui, 1)
	testing.expect(t, !take_key(&h.ui, .Enter))
	testing.expect(t, take_key(&h.ui, .Enter, repeats = true))
	ui_end_frame(&h.ui)
}

@(test)
a_widget_gets_the_actions_of_its_role_and_its_group :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, proc(ui: ^Ui, data: rawptr) {
			push_parent(ui, widget_id("Dialog"))
			declare(ui, {id = widget_id("Save"), role = .Button, label = "Save"})
			pop_parent(ui)
			declare(ui, {id = widget_id("Title"), role = .Text_Field, label = "Title"})
		}, nil)
	defer harness_destroy(&h)
	run_frame(&h)
	save, _ := find_widget(&h.ui, "Save")
	testing.expect_value(t, save.actions, Actions{.Press, .Focus})
	testing.expect_value(t, save.parent, widget_id("Dialog"))
	title, _ := find_widget(&h.ui, "Title")
	testing.expect_value(t, title.parent, 0)
	testing.expect(t, .Set_Value in title.actions)
}
