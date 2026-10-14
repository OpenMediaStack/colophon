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
		{
			id = COLUMN_NUMBER,
			title = "#",
			min_width = 36,
			mono = true,
			align = .Right,
			fixed = true,
		},
		{
			id = COLUMN_TITLE,
			title = "Title",
			min_width = 200,
			weight = 1.6,
			width = 240,
			primary = true,
			sort_label = "Sort by Title",
		},
		{id = COLUMN_ARTIST, title = "Artist", min_width = 140, weight = 1.1, width = 160},
		{
			id = COLUMN_TIME,
			title = "Time",
			min_width = 56,
			mono = true,
			align = .Right,
			width = 56,
		},
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
	if row >= 3 && row <= 4 do s += {.Selected}
	if row == 1 do s += {.Modified}
	if row == 2 do s += {.Placeholder}
	if row == 5 do s += {.Error}
	if row == 6 do s += {.Playing}
	if row == 7 do s += {.Warning}
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
		r.release ||= each.release
		if each.step != nil do r.step = each.step
		if each.input != nil do r.input = each.input
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

// The title and the artist edited in place.
@(private = "file")
editable_tracks_harness :: proc(h: ^Harness, t: ^Tracks) {
	tracks_harness(h, t)
	t.columns[COLUMN_TITLE].editable = true
	t.columns[COLUMN_ARTIST].editable = true
	run_frame(h)
}

// The editor of the cell edited in place, while one is open.
@(private = "file")
editor_of :: proc(h: ^Harness) -> (info: Widget_Info, open: bool) {
	for w in h.ui.widgets do if w.role == .Text_Field do return w, true
	return
}

// The middle of a row's cell in a column, by the row's title and the column's name.
@(private = "file")
cell_center :: proc(h: ^Harness, row, column: string) -> [2]f32 {
	r, _ := widget_center(h, row)
	c, _ := widget_center(h, column)
	return {c.x, r.y}
}

@(private = "file")
double_click_at :: proc(h: ^Harness, p: [2]f32) {
	move_mouse(h, p)
	press(h)
	release(h)
	press(h, clicks = 2)
	release(h)
}

@(private = "file")
digits_only :: proc(text: string) -> bool {
	for c in text do if c < '0' || c > '9' do return false
	return true
}

@(test)
a_double_click_edits_a_cell_and_enter_commits_it :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 2", clicks = 2)
	edit, asked := reported(&tr).edit.?
	testing.expect(t, asked && edit == Cell_Edit{1, COLUMN_TITLE})
	editor, open := editor_of(&h)
	testing.expect(t, open && has_focus(&h.ui, editor.id))
	testing.expect_value(t, editor.value, "Track 2")

	// The value is all selected: typing replaces it, and each change is reported.
	type_text(&h, "Neon Overpass")
	input, typed := reported(&tr).input.?
	testing.expect(t, typed && input.field.changed && input.field.text == "Neon Overpass")
	press_key(&h, .Enter)
	input, typed = reported(&tr).input.?
	testing.expect(t, typed && input.field.committed && input.cell == Cell_Edit{1, COLUMN_TITLE})
	run_frame(&h)
	_, open = editor_of(&h)
	testing.expect(t, !open)
	testing.expect(t, has_focus(&h.ui, widget_id("Tracks")))
}

@(test)
only_editable_cells_of_readable_files_are_edited :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	double_click_at(&h, cell_center(&h, "Track 2", "Time"))
	testing.expect_value(t, reported(&tr).edit, nil)
	click(&h, "Track 6", clicks = 2)
	testing.expect_value(t, reported(&tr).edit, nil)
	_, open := editor_of(&h)
	testing.expect(t, !open)
}

@(test)
escape_puts_the_cell_back :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 2", clicks = 2)
	type_text(&h, "Neon Overpass")
	press_key(&h, .Escape)
	input, typed := reported(&tr).input.?
	testing.expect(t, typed && input.field.cancelled && input.field.text == "Track 2")
	run_frame(&h)
	_, open := editor_of(&h)
	testing.expect(t, !open)
	testing.expect(t, has_focus(&h.ui, widget_id("Tracks")))
}

@(test)
enter_or_f2_edits_the_focused_row :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 1")
	tr.focused = 0
	reported(&tr)
	for key in ([]Key{.Enter, .F2}) {
		press_key(&h, key)
		edit, asked := reported(&tr).edit.?
		testing.expect(t, asked && edit == Cell_Edit{0, COLUMN_TITLE})
		run_frame(&h)
		editor, open := editor_of(&h)
		testing.expect(t, open && has_focus(&h.ui, editor.id) && editor.value == "Track 1")
		press_key(&h, .Escape)
	}
	// Not the row of a file that could not be read.
	tr.focused = 5
	run_frame(&h)
	press_key(&h, .Enter)
	testing.expect_value(t, reported(&tr).edit, nil)
}

@(test)
tab_goes_across_the_editable_cells :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 1")
	tr.focused = 0
	press_key(&h, .Enter)
	run_frame(&h)
	type_text(&h, "Neon Overpass")
	reported(&tr)
	press_key(&h, .Tab)
	r := reported(&tr)
	input, typed := r.input.?
	testing.expect(t, typed && input.field.committed && input.field.text == "Neon Overpass")
	testing.expect_value(t, r.edit, Cell_Edit{0, COLUMN_ARTIST})
	run_frame(&h)
	editor, open := editor_of(&h)
	testing.expect(t, open && has_focus(&h.ui, editor.id) && editor.value == "Marlowe Kite")

	press_key(&h, .Tab, {.Shift})
	testing.expect_value(t, reported(&tr).edit, Cell_Edit{0, COLUMN_TITLE})
	run_frame(&h)
	press_key(&h, .Tab)
	run_frame(&h)
	reported(&tr)
	// Past the last editable cell, the editing ends.
	press_key(&h, .Tab)
	testing.expect_value(t, reported(&tr).edit, nil)
	run_frame(&h)
	_, open = editor_of(&h)
	testing.expect(t, !open)
	testing.expect(t, has_focus(&h.ui, widget_id("Tracks")))
}

@(test)
text_the_column_does_not_take_keeps_the_editor_open :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	tr.columns[COLUMN_TIME].editable = true
	tr.columns[COLUMN_TIME].accepts = digits_only
	double_click_at(&h, cell_center(&h, "Track 1", "Time"))
	testing.expect_value(t, reported(&tr).edit, Cell_Edit{0, COLUMN_TIME})
	type_text(&h, "20x4")
	press_key(&h, .Enter)
	press_key(&h, .Tab)
	input, _ := reported(&tr).input.?
	testing.expect(t, !input.field.committed)
	editor, open := editor_of(&h)
	testing.expect(t, open && has_focus(&h.ui, editor.id) && editor.value == "20x4")

	// A click elsewhere gives it up.
	click(&h, "Track 4")
	r := reported(&tr)
	input, _ = r.input.?
	testing.expect(t, input.field.cancelled && input.field.text == "4:08")
	press, pressed := r.press.?
	testing.expect(t, pressed && press.row == 3)
	_, open = editor_of(&h)
	testing.expect(t, !open)
}

@(test)
a_click_elsewhere_or_another_focused_row_ends_the_editing :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	editable_tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 2", clicks = 2)
	type_text(&h, "Neon Overpass")
	click(&h, "Track 4")
	input, typed := reported(&tr).input.?
	testing.expect(t, typed && input.field.committed && input.field.text == "Neon Overpass")
	_, open := editor_of(&h)
	testing.expect(t, !open)

	tr.focused = 3
	run_frame(&h)
	press_key(&h, .Enter)
	run_frame(&h)
	type_text(&h, "Cassette Bloom")
	tr.focused = 4
	run_frame(&h)
	input, typed = reported(&tr).input.?
	testing.expect(t, typed && input.field.committed && input.cell == Cell_Edit{3, COLUMN_TITLE})
	run_frame(&h)
	_, open = editor_of(&h)
	testing.expect(t, !open)
	testing.expect(t, has_focus(&h.ui, widget_id("Tracks")))
}

@(test)
a_press_and_its_release_are_reported_and_a_right_click_takes_the_focus :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	click(&h, "Track 2")
	testing.expect(t, reported(&tr).release)
	request_focus(&h.ui, 0)
	run_frame(&h)
	click(&h, "Track 4", .Right)
	testing.expect(t, has_focus(&h.ui, widget_id("Tracks")))
	// Tab moves on from the table.
	press_key(&h, .Tab)
	testing.expect(t, !has_focus(&h.ui, widget_id("Tracks")))
}

@(test)
rows_cells_and_signs_are_declared_inside_the_table :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	table := widget_id("Tracks")
	row, _ := find_widget(&h.ui, "Track 2")
	testing.expect_value(t, row.parent, table)
	unsaved, _ := find_widget(&h.ui, "Unsaved changes")
	testing.expect(t, unsaved.role == .Image && unsaved.parent == row.id)
	unreadable, found := find_widget(&h.ui, "Unreadable")
	testing.expect(t, found && unreadable.parent == child_id(table, "row", 5))
	cell, _ := find_widget(&h.ui, "Marlowe Kite")
	testing.expect(t, cell.role == .Cell && cell.parent == child_id(table, "row", 0))
	sort, _ := find_widget(&h.ui, "Sort by Title")
	testing.expect_value(t, sort.parent, table)
	chooser, _ := find_widget(&h.ui, "Choose columns")
	testing.expect_value(t, chooser.parent, table)
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
	title, _ := find_widget(&h.ui, "Sort by Title")
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
a_column_fits_its_content_moves_last_and_keeps_some_width :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	artist, _ := find_widget(&h.ui, "Artist")
	edge := [2]f32{artist.rect.x + artist.rect.w + 3, 14}
	move_mouse(&h, edge)
	press(&h)
	release(&h)
	// A press alone resizes nothing.
	testing.expect_value(t, reported(&tr).resized, nil)
	press(&h, clicks = 2)
	release(&h)
	fit, fitted := reported(&tr).resized.?
	widest := text_width(h.ui.renderer, "Marlowe Kite", .Body)
	testing.expect(t, fitted && fit.column == COLUMN_ARTIST && fit.width == widest + 17)

	// Never narrower than 40 points.
	move_mouse(&h, edge)
	press(&h)
	move_mouse(&h, {edge.x - 500, 14})
	release(&h)
	narrow, _ := reported(&tr).resized.?
	testing.expect_value(t, narrow.width, 40)

	// Dropped past the last column: last.
	title, _ := find_widget(&h.ui, "Sort by Title")
	move_mouse(&h, rect_center(title.rect))
	press(&h)
	move_mouse(&h, {790, 14})
	release(&h)
	move, moved := reported(&tr).moved.?
	testing.expect(t, moved && move.column == COLUMN_TITLE && move.before == nil)
}

@(test)
a_right_click_anywhere_on_the_header_opens_the_chooser :: proc(t: ^testing.T) {
	h: Harness
	tr: Tracks
	tracks_harness(&h, &tr)
	defer destroy_tracks(&h)
	// The status corner, which no column covers.
	move_mouse(&h, {10, 14})
	press(&h, .Right)
	release(&h, .Right)
	testing.expect(t, reported(&tr).column_menu != nil)
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
	// Back to a row the focus left: it scrolls there again.
	tr.focused = 0
	run_frame(&h)
	tr.state.scroll.offset.y = 10_000
	tr.focused = nil
	run_frame(&h)
	tr.focused = 0
	run_frame(&h)
	run_frame(&h)
	_, shown = find_widget(&h.ui, "Track 1")
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

// A cell edited in place, its text selected, in both themes.
@(test)
the_cell_editor_matches_its_reference :: proc(t: ^testing.T) {
	size := [2]f32{1000, 140}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	for kind, i in Theme_Kind {
		area := Rect{f32(i) * size.x / 2, 0, size.x / 2, size.y}
		ui: Ui
		ui_init(&ui, cap.renderer, theme(kind))
		tr: Tracks
		tracks_of(&tr, 4)
		tr.rect = area
		tr.columns[COLUMN_ARTIST].editable = true
		tr.state.editing = Cell_Edit{1, COLUMN_ARTIST}
		id := widget_id("Tracks")
		ui.focus = editor_id(id, tr.state.editing.?)
		ui.focus_by_key = true
		rows := Table_Rows{&tr, tr.count, cell_of, states_of}
		table(&ui, id, area, tr.columns[:], rows, &tr.state, nil, false, 1)
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "table-editing.png")
	free_all(context.temp_allocator)
}
