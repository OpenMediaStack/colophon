package ui

import "core:fmt"
import "core:log"
import "core:testing"
import "core:time"

// A table of count tracks, its results, and the state its screen keeps.
@(private = "file")
Tracks :: struct {
	count:   int,
	state:   Table_State,
	sorted:  Maybe(Table_Sort),
	sized:   bool,
	columns: [4]Table_Column,
	focused: Maybe(int),
	last:    Table_Result,
	// What every frame reported, since the harness's helpers run several.
	all:     [dynamic]Table_Result,
	rect:    Rect,
}

@(private = "file")
COLUMN_NUMBER :: 0
@(private = "file")
COLUMN_TITLE :: 1
@(private = "file")
COLUMN_ARTIST :: 2
@(private = "file")
COLUMN_TIME :: 3

@(private = "file")
tracks_of :: proc(t: ^Tracks, count: int) {
	t.count = count
	t.rect = {0, 0, 800, 400}
	t.columns = {
		{id = COLUMN_NUMBER, title = "#", min_width = 36, numeric = true, fixed = true},
		{
			id = COLUMN_TITLE,
			title = "Title",
			min_width = 200,
			weight = 1.6,
			width = 240,
			primary = true,
		},
		{id = COLUMN_ARTIST, title = "Artist", min_width = 140, weight = 1.1, width = 160},
		{id = COLUMN_TIME, title = "Time", min_width = 56, numeric = true, width = 56},
	}
	t.all = make([dynamic]Table_Result, context.temp_allocator)
}

@(private = "file")
cell_of :: proc(data: rawptr, row, column: int) -> string {
	switch column {
	case COLUMN_NUMBER:
		return fmt.tprint(row + 1)
	case COLUMN_TITLE:
		return row == 2 ? "02 Untitled.mp3" : fmt.tprintf("Track %d", row + 1)
	case COLUMN_ARTIST:
		return "Marlowe Kite"
	case COLUMN_TIME:
		return "4:08"
	}
	return ""
}

@(private = "file")
states_of :: proc(data: rawptr, row: int) -> (s: Row_States) {
	t := (^Tracks)(data)
	if row >= 3 && row <= 4 do s += {.Selected}
	if row == 1 do s += {.Modified}
	if row == 2 do s += {.Placeholder}
	if row == 5 do s += {.Error}
	if row == 6 do s += {.Playing}
	if row == 7 do s += {.Warning}
	_ = t
	return
}

@(private = "file")
tracks_frame :: proc(ui: ^Ui, data: rawptr) {
	t := (^Tracks)(data)
	rows := Table_Rows{t, t.count, cell_of, states_of}
	t.last = table(
		ui,
		widget_id("Tracks"),
		t.rect,
		t.columns[:],
		rows,
		&t.state,
		t.sorted,
		t.sized,
		t.focused,
	)
	append(&t.all, t.last)
}

@(private = "file")
tracks_harness :: proc(h: ^Harness, t: ^Tracks, count := 50) {
	tracks_of(t, count)
	harness_init(h, tracks_frame, t)
	run_frame(h)
}

@(private = "file")
destroy_tracks :: proc(h: ^Harness) {
	harness_destroy(h)
	free_all(context.temp_allocator)
}

// What the frames reported, merged: the last of each kind.
@(private = "file")
reported :: proc(t: ^Tracks) -> (r: Table_Result) {
	for each in t.all {
		if each.press != nil do r.press = each.press
		if each.sort_by != nil do r.sort_by = each.sort_by
		if each.resized != nil do r.resized = each.resized
		if each.moved != nil do r.moved = each.moved
		if each.row_menu != nil do r.row_menu = each.row_menu
		if each.column_menu != nil do r.column_menu = each.column_menu
		if each.edit != nil do r.edit = each.edit
		if each.step != nil do r.step = each.step
		r.select_all ||= each.select_all
		r.space ||= each.space
	}
	clear(&t.all)
	return
}

@(test)
the_columns_share_the_width_until_the_user_sizes_them :: proc(t: ^testing.T) {
	tr: Tracks
	tracks_of(&tr, 1)
	shared := column_widths(tr.columns[:], 800, false, context.temp_allocator)
	spare := (800 - (36 + 200 + 140 + 56 + TABLE_STATUS_WIDTH + TABLE_END_WIDTH)) / f32(2.7)
	testing.expect_value(t, shared[1], 200 + spare * 1.6)
	testing.expect_value(t, shared[3], 56)
	sized := column_widths(tr.columns[:], 800, true, context.temp_allocator)
	testing.expect_value(t, sized[1], 240)
	free_all(context.temp_allocator)
}

@(test)
only_the_rows_in_view_are_drawn :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr, 10_000)
	defer destroy_tracks(&h)
	rows := 0
	for w in h.ui.widgets do if w.role == .Row do rows += 1
	testing.expect(t, rows <= int(400 / TABLE_ROW_HEIGHT) + 2, "virtualised")
	// The benchmark of the plan: a frame of a table of 10,000 rows.
	start := time.tick_now()
	FRAMES :: 20
	for _ in 0 ..< FRAMES do run_frame(&h)
	per_frame := time.tick_since(start) / FRAMES
	log.infof("a frame of 10,000 rows: %v", per_frame)
	testing.expect(t, per_frame < 50 * time.Millisecond)
}

@(test)
a_press_on_a_row_reports_it_with_its_modifiers :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	testing.expect(t, click(&h, "Track 2"))
	press, pressed := reported(&tr).press.?
	testing.expect(t, pressed && press.row == 1)
	testing.expect(t, has_focus(&h.ui, widget_id("Tracks")))
	h.ui.input.modifiers = COMMAND
	click(&h, "Track 4")
	press, pressed = reported(&tr).press.?
	testing.expect(t, pressed && press.row == 3 && press.modifiers == COMMAND)
	h.ui.input.modifiers = {}
	click(&h, "Track 4", .Right)
	menu, opened := reported(&tr).row_menu.?
	testing.expect(t, opened && menu.row == 3)
}

@(test)
a_double_click_on_a_cell_asks_to_edit_it :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 2", clicks = 2)
	edit, asked := reported(&tr).edit.?
	testing.expect(t, asked && edit.row == 1 && edit.column == COLUMN_TITLE)
	click(&h, "Track 6", clicks = 2)
	testing.expect_value(t, reported(&tr).edit, nil)
}

@(test)
the_header_sorts_resizes_and_moves_the_columns :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Artist")
	testing.expect_value(t, reported(&tr).sort_by, COLUMN_ARTIST)

	// The right edge of Title.
	title, _ := find_widget(&h.ui, "Title")
	move_mouse(&h, {title.rect.x + title.rect.w + 3, 14})
	press(&h)
	move_mouse(&h, {title.rect.x + title.rect.w + 53, 14})
	release(&h)
	resize, resized := reported(&tr).resized.?
	testing.expect(t, resized && resize.column == COLUMN_TITLE)
	testing.expect(t, abs(resize.width - (title.rect.w + 6 + 50)) <= 1)

	// Artist dragged by its name before Title.
	artist, _ := find_widget(&h.ui, "Artist")
	move_mouse(&h, rect_center(artist.rect))
	press(&h)
	move_mouse(&h, {title.rect.x + 10, 14})
	release(&h)
	move, moved := reported(&tr).moved.?
	testing.expect(t, moved && move.column == COLUMN_ARTIST && move.before == COLUMN_TITLE)
	testing.expect_value(t, reported(&tr).sort_by, nil)
}

@(test)
the_column_chooser_opens_from_the_header :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Time", .Right)
	testing.expect(t, reported(&tr).column_menu != nil)
	click(&h, "Choose columns")
	testing.expect(t, reported(&tr).column_menu != nil)
}

@(test)
keys_on_a_focused_table_step_select_all_and_play :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 1")
	reported(&tr)
	press_key(&h, .Down, {.Shift})
	step, stepped := reported(&tr).step.?
	testing.expect(t, stepped && step == Table_Step{.Down, true})
	press_key(&h, .A, COMMAND)
	testing.expect(t, reported(&tr).select_all)
	press_key(&h, .Space)
	testing.expect(t, reported(&tr).space)
}

@(test)
the_focused_row_is_kept_in_view :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr, 1000)
	defer destroy_tracks(&h)
	tr.focused = 500
	run_frame(&h)
	run_frame(&h)
	_, shown := find_widget(&h.ui, "Track 501")
	testing.expect(t, shown)
}

@(test)
sized_columns_wider_than_the_table_scroll_sideways_with_their_header :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	tr.sized = true
	tr.columns[1].width = 900
	run_frame(&h)
	move_mouse(&h, {300, 200})
	h.ui.input.wheel = {120, 0}
	run_frame(&h)
	run_frame(&h)
	testing.expect_value(t, tr.state.scroll.offset.x, 120)
	artist, _ := find_widget(&h.ui, "Artist")
	testing.expect_value(t, artist.rect.x, TABLE_STATUS_WIDTH + 36 + 900 - 120)
}

// Rows in every state, the selection outlined, a sorted column, in both themes.
@(test)
the_table_matches_its_reference :: proc(t: ^testing.T) {
	size := [2]f32{1000, 260}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	for kind, i in Theme_Kind {
		area := Rect{f32(i) * size.x / 2, 0, size.x / 2, size.y}
		ui: Ui
		ui_init(&ui, cap.renderer, theme(kind))
		tr: Tracks
		tracks_of(&tr, 9)
		tr.rect = area
		id := widget_id("Tracks")
		ui.focus = id
		ui.hot = child_id(id, "row", 0)
		ui.input.mouse = {area.x + 100, TABLE_HEADER_HEIGHT + 10}
		rows := Table_Rows{&tr, tr.count, cell_of, states_of}
		table(
			&ui,
			id,
			area,
			tr.columns[:],
			rows,
			&tr.state,
			Table_Sort{COLUMN_TITLE, false},
			false,
			nil,
		)
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "table.png")
	free_all(context.temp_allocator)
}
