package ui

import "core:math"

// A column of a table: the caller's id for it, and how it is drawn and sized.
Table_Column :: struct {
	id:        int,
	title:     string,
	// The width the user gave it, when the table is sized; else the table shares its width
	// between the columns, each getting min_width and its weight's share of what is left.
	width:     f32,
	min_width: f32,
	weight:    f32,
	// Numbers that line up: JetBrains Mono, aligned right.
	numeric:   bool,
	// The column whose text says which row it is, the title: in the row's colours.
	primary:   bool,
	// Not resized, moved or hidden by the user: the track number.
	fixed:     bool,
}

// What a row is going through.
Row_State :: enum u8 {
	Selected,
	// Its changes wait to be saved: a dot in the status column.
	Modified,
	// Its file could not be read: an alert, and its primary text in the error colour.
	Error,
	// Its tags look wrong beside the rest of its album: a warning sign.
	Warning,
	Playing,
	// Its primary text is a stand-in, the file name for a track without a title.
	Placeholder,
}

Row_States :: bit_set[Row_State]

// Where a table's rows come from: the table asks for the rows it shows, and only those.
Table_Rows :: struct {
	data:   rawptr,
	count:  int,
	// The text of a cell, which must last until the frame ends.
	cell:   proc(data: rawptr, row: int, column: int) -> string,
	states: proc(data: rawptr, row: int) -> Row_States,
}

// What a table keeps between frames, which the screen owns.
Table_State :: struct {
	scroll:      Scroll,
	// The column dragged by its name, and where the pointer is.
	dragging:    Maybe(int),
	drag_x:      f32,
	// The column resized, and its width when the drag started.
	resizing:    Maybe(int),
	resize_from: f32,
	// The focused row the table last scrolled to, so that it scrolls once when it moves.
	revealed:    Maybe(int),
}

// A press on a row, which the app turns into a selection command.
Row_Press :: struct {
	row:       int,
	modifiers: Modifiers,
	clicks:    int,
}

// A column moved by its name before another, or last.
Column_Move :: struct {
	column: int,
	before: Maybe(int),
}

// A column resized to width.
Column_Resize :: struct {
	column: int,
	width:  f32,
}

// A right click on a row, or a Control click on macOS: its menu, at a point.
Row_Menu :: struct {
	row: int,
	at:  [2]f32,
}

// A double click on a cell, to edit it.
Cell_Edit :: struct {
	row, column: int,
}

// The arrow keys on a focused table.
Table_Step :: struct {
	direction: Step_Direction,
	// Shift: the selection grows or shrinks.
	extend:    bool,
}

Step_Direction :: enum u8 {
	Up,
	Down,
}

// What happened to a table this frame. The table decides nothing: the app turns each
// into an engine command.
Table_Result :: struct {
	press:       Maybe(Row_Press),
	release:     bool,
	sort_by:     Maybe(int),
	resized:     Maybe(Column_Resize),
	moved:       Maybe(Column_Move),
	row_menu:    Maybe(Row_Menu),
	// The column chooser: a right click on the header, or the columns button.
	column_menu: Maybe([2]f32),
	edit:        Maybe(Cell_Edit),
	step:        Maybe(Table_Step),
	select_all:  bool,
	// Space on a focused table: play or pause.
	space:       bool,
}

// How a table is sorted, as the engine says.
Table_Sort :: struct {
	column:     int,
	descending: bool,
}

TABLE_HEADER_HEIGHT :: 28
TABLE_ROW_HEIGHT :: 26
TABLE_STATUS_WIDTH :: 24
// Room at the right end of the rows for the vertical scroll bar and the columns button.
TABLE_END_WIDTH :: 32
@(private = "file")
RESIZE_HANDLE :: 6
@(private = "file")
NARROWEST :: 40
@(private = "file")
DRAG_THRESHOLD :: 4
@(private = "file")
WIDEST_FIT :: 600

// A table of rows in columns: virtualised, so that only the rows in view are drawn; a
// header that sorts, resizes and moves the columns, and opens the column chooser; a
// status column; scrolling down and, when the columns are wider than the table,
// sideways, the header following. sized says whether the columns keep the widths the
// user gave them. focused_row is the row the arrow keys move from, which the table keeps
// in view.
table :: proc(
	ui: ^Ui,
	id: Widget_Id,
	rect: Rect,
	columns: []Table_Column,
	rows: Table_Rows,
	state: ^Table_State,
	sort: Maybe(Table_Sort),
	sized: bool,
	focused_row: Maybe(int),
	label := "Tracks",
) -> (
	result: Table_Result,
) {
	r := ui.renderer
	th := ui.theme
	widths := column_widths(columns, rect.w, sized, context.temp_allocator)
	content_width: f32 = TABLE_STATUS_WIDTH + TABLE_END_WIDTH
	for w in widths do content_width += w
	content_width = max(content_width, rect.w)
	header := Rect{rect.x, rect.y, rect.w, TABLE_HEADER_HEIGHT}
	body := Rect {
		rect.x,
		rect.y + TABLE_HEADER_HEIGHT,
		rect.w,
		max(rect.h - TABLE_HEADER_HEIGHT, 0),
	}
	content := [2]f32{content_width, f32(rows.count) * TABLE_ROW_HEIGHT}
	focused := has_focus(ui, id)
	fill_rect(r, rect, th.surface_1)
	declare(
		ui,
		{
			id = id,
			role = .Table,
			label = label,
			rect = rect,
			states = focused ? {.Focused} : {},
			focusable = true,
		},
	)

	if focused do table_keys(ui, &result)
	// The focused row is kept in view once, when it moves.
	if row, has := focused_row.?; has && state.revealed != row {
		scroll_into_view(&state.scroll, f32(row) * TABLE_ROW_HEIGHT, TABLE_ROW_HEIGHT, body.h)
		state.revealed = row
	}

	// A click below the rows still gives the table the focus; the rows, drawn after,
	// take the clicks on them.
	if .Pressed in interact(ui, child_id(id, "body"), body) && !focused do request_focus(ui, id)
	origin := begin_scroll(ui, id, body, content, &state.scroll)
	draw_rows(ui, id, body, origin, columns, widths, rows, focused, &result)
	end_scroll(ui, id, body, content, &state.scroll)
	draw_header(ui, id, header, origin.x, columns, widths, rows, sort, state, &result)
	return
}

// The widths of the columns: those the user gave them when sized, else min_width each
// and the rest of width shared by weight. Allocated with allocator.
column_widths :: proc(
	columns: []Table_Column,
	width: f32,
	sized: bool,
	allocator := context.allocator,
) -> []f32 {
	widths := make([]f32, len(columns), allocator)
	if sized {
		for c, i in columns do widths[i] = c.fixed ? c.min_width : max(c.width, NARROWEST)
		return widths
	}
	least: f32 = TABLE_STATUS_WIDTH + TABLE_END_WIDTH
	weights: f32 = 0
	for c in columns {
		least += c.min_width
		weights += c.weight
	}
	spare := weights > 0 ? max(width - least, 0) / weights : 0
	for c, i in columns do widths[i] = c.min_width + spare * c.weight
	return widths
}

// The arrow keys, Command+A and Space on a focused table.
@(private = "file")
table_keys :: proc(ui: ^Ui, result: ^Table_Result) {
	if take_key(ui, .Up, repeats = true) do result.step = Table_Step{.Up, false}
	if take_key(ui, .Down, repeats = true) do result.step = Table_Step{.Down, false}
	if take_key(ui, .Up, {.Shift}, repeats = true) do result.step = Table_Step{.Up, true}
	if take_key(ui, .Down, {.Shift}, repeats = true) do result.step = Table_Step{.Down, true}
	if take_key(ui, .A, COMMAND) do result.select_all = true
	if take_key(ui, .Space) do result.space = true
	if take_key(ui, .Tab) do move_focus(ui, .Forward)
	if take_key(ui, .Tab, {.Shift}) do move_focus(ui, .Back)
}

// The rows in view, from the first one the scroll shows.
@(private = "file")
draw_rows :: proc(
	ui: ^Ui,
	id: Widget_Id,
	body: Rect,
	origin: [2]f32,
	columns: []Table_Column,
	widths: []f32,
	rows: Table_Rows,
	focused: bool,
	result: ^Table_Result,
) {
	r := ui.renderer
	th := ui.theme
	first := max(int((body.y - origin.y) / TABLE_ROW_HEIGHT), 0)
	last := min(rows.count, first + int(math.ceil(body.h / TABLE_ROW_HEIGHT)) + 1)
	in_ := &ui.input
	for row in first ..< last {
		y := origin.y + f32(row) * TABLE_ROW_HEIGHT
		rect := Rect {
			origin.x,
			y,
			max(body.w, sum(widths) + TABLE_STATUS_WIDTH + TABLE_END_WIDTH),
			TABLE_ROW_HEIGHT,
		}
		states := rows.states(rows.data, row)
		row_id := child_id(id, "row", row)
		interaction := interact(ui, row_id, rect)
		if .Pressed in interaction {
			result.press = Row_Press{row, in_.modifiers, in_.clicks}
			// The press that starts the drag of a selection does not take the focus away.
			request_focus(ui, id)
		}
		if .Held in interaction && .Left in in_.released do result.release = true
		if .Right_Clicked in interaction do result.row_menu = Row_Menu{row, in_.mouse}
		switch {
		case .Selected in states:
			fill_rect(r, rect, th.accent_selection)
		case .Hovered in interaction:
			fill_rect(r, rect, th.surface_3)
		}
		draw_status(r, th, {rect.x, y, TABLE_STATUS_WIDTH, TABLE_ROW_HEIGHT}, states)
		x := rect.x + TABLE_STATUS_WIDTH
		for column, i in columns {
			cell := Rect{x, y, widths[i], TABLE_ROW_HEIGHT}
			x += widths[i]
			if cell.w <= 0 do continue
			text := rows.cell(rows.data, row, column.id)
			draw_cell(r, th, cell, text, column, states)
			if .Double_Clicked in interaction &&
			   rect_contains(cell, in_.mouse) &&
			   .Error not_in states {
				result.edit = Cell_Edit{row, column.id}
			}
		}
		fill_rect(r, {rect.x, y + TABLE_ROW_HEIGHT - 1, rect.w, 1}, th.border_row)
		if .Selected in states && focused {
			above := row > 0 && .Selected in rows.states(rows.data, row - 1)
			below := row + 1 < rows.count && .Selected in rows.states(rows.data, row + 1)
			draw_selection_outline(r, th, rect, above, below)
		}
		label := len(columns) > 0 ? rows.cell(rows.data, row, primary_column(columns)) : ""
		declare(
			ui,
			{
				id = row_id,
				role = .Row,
				label = label,
				rect = rect,
				states = row_widget_states(states, interaction),
				parent = id,
			},
		)
	}
}

// The status column: why a row stands out, one sign at most.
@(private = "file")
draw_status :: proc(r: ^Renderer, th: Theme, cell: Rect, states: Row_States) {
	switch {
	case .Error in states:
		draw_icon_centered(r, .Circle_Alert, cell, th.error, 14)
	case .Playing in states:
		draw_icon_centered(r, .Volume, cell, th.accent_text, 14)
	case .Modified in states:
		fill_rect(r, centered(cell, 6, 6), th.accent, 3)
	case .Warning in states:
		draw_icon_centered(r, .Triangle_Alert, cell, th.warning, 14)
	}
}

@(private = "file")
draw_cell :: proc(
	r: ^Renderer,
	th: Theme,
	cell: Rect,
	text: string,
	column: Table_Column,
	states: Row_States,
) {
	color := th.text_secondary
	switch {
	case column.fixed:
		color = th.text_tertiary
	case column.primary && .Error in states:
		color = th.error
	case column.primary && .Playing in states:
		color = th.accent_text
	case column.primary && .Placeholder in states:
		color = th.text_tertiary
	case column.primary:
		color = th.text_primary
	}
	style := column.numeric ? Text_Style.Numeric : Text_Style.Body
	push_clip(r, cell)
	defer pop_clip(r)
	inner := rect_inset(cell, 8, 0)
	draw_text_fit(
		r,
		text,
		inner.x,
		cell.y + cell.h / 2,
		inner.w,
		style,
		color,
		column.numeric ? .Right : .Left,
	)
}

// The outline of a run of selected rows while the table has the focus: its sides, and
// its top and bottom where the run starts and ends.
@(private = "file")
draw_selection_outline :: proc(r: ^Renderer, th: Theme, rect: Rect, above, below: bool) {
	fill_rect(r, {rect.x, rect.y, 1, rect.h}, th.focus_ring)
	fill_rect(r, {rect.x + rect.w - 1, rect.y, 1, rect.h}, th.focus_ring)
	if !above do fill_rect(r, {rect.x, rect.y, rect.w, 1}, th.focus_ring)
	if !below do fill_rect(r, {rect.x, rect.y + rect.h - 1, rect.w, 1}, th.focus_ring)
}

// The header: a click on a column's name sorts by it, a drag of it moves the column, a
// drag of its right edge resizes it and a double click there fits it, a right click
// opens the column chooser, as does the button at its right end.
@(private = "file")
draw_header :: proc(
	ui: ^Ui,
	id: Widget_Id,
	header: Rect,
	origin_x: f32,
	columns: []Table_Column,
	widths: []f32,
	rows: Table_Rows,
	sort: Maybe(Table_Sort),
	state: ^Table_State,
	result: ^Table_Result,
) {
	r := ui.renderer
	th := ui.theme
	in_ := &ui.input
	fill_rect(r, header, th.surface_2)
	fill_rect(r, {header.x, header.y + header.h - 1, header.w, 1}, th.border_subtle)
	push_clip(r, header)
	defer pop_clip(r)
	x := origin_x + TABLE_STATUS_WIDTH
	starts := make([]f32, len(columns) + 1, context.temp_allocator)
	for column, i in columns {
		cell := Rect{x, header.y, widths[i], header.h}
		starts[i] = x
		x += widths[i]
		if cell.w <= 0 do continue
		cell_id := child_id(id, "column", column.id)
		handle_id := child_id(id, "resize", column.id)
		name := Rect{cell.x, cell.y, cell.w - (column.fixed ? 0 : RESIZE_HANDLE), cell.h}
		interaction := interact(ui, cell_id, name)
		if .Right_Clicked in interaction do result.column_menu = in_.mouse
		if !column.fixed {
			if .Held in interaction &&
			   state.dragging == nil &&
			   abs(in_.mouse.x - ui.press_mouse.x) > DRAG_THRESHOLD {
				state.dragging = column.id
			}
			if dragged, is := state.dragging.?; is && dragged == column.id {
				state.drag_x = in_.mouse.x
				if .Held not_in interaction || .Left in in_.released {
					result.moved = Column_Move {
						column.id,
						drop_before(columns, widths, starts, x, in_.mouse.x, origin_x),
					}
					state.dragging = nil
				}
			}
		}
		if .Clicked in interaction && state.dragging == nil && result.moved == nil do result.sort_by = column.id
		sorted, descending := false, false
		if s, has := sort.?; has && s.column == column.id do sorted, descending = true, s.descending
		if state.dragging == column.id do fill_rect(r, cell, th.surface_3)
		color := sorted ? th.text_primary : th.text_secondary
		inner := rect_inset(cell, 8, 0)
		marker: f32 = sorted ? 14 : 0
		align: Align = column.numeric ? .Right : .Left
		text_x := inner.x
		if column.numeric do text_x = inner.x + marker
		draw_text_fit(
			r,
			column.title,
			text_x,
			cell.y + cell.h / 2,
			inner.w - marker,
			.Small_Strong,
			color,
			align,
		)
		if sorted {
			title_width := min(text_width(r, column.title, .Small_Strong), inner.w - marker)
			icon_x :=
				column.numeric ? inner.x + inner.w - title_width - 14 : inner.x + title_width + 4
			draw_icon(
				r,
				descending ? .Chevron_Down : .Chevron_Up,
				{icon_x, cell.y + cell.h / 2 - 5, 10, 10},
				color,
			)
		}
		label := column.title
		declare(
			ui,
			{
				id = cell_id,
				role = .Button,
				label = label,
				rect = name,
				states = sorted ? {.Selected} : {},
			},
		)
		if column.fixed do continue
		// The separator at the column's right edge, which a drag resizes.
		fill_rect(r, {cell.x + cell.w - 1, cell.y + 6, 1, cell.h - 12}, th.border_subtle)
		handle := Rect{cell.x + cell.w - RESIZE_HANDLE, cell.y, RESIZE_HANDLE, cell.h}
		resize := interact(ui, handle_id, handle)
		if .Hovered in resize || .Held in resize do ui.cursor = .Resize_Horizontal
		if .Pressed in resize {
			state.resizing = column.id
			state.resize_from = widths[i]
		}
		if .Double_Clicked in resize do result.resized = Column_Resize{column.id, fit_width(r, rows, column)}
		if .Held in resize && state.resizing == column.id {
			width := max(state.resize_from + in_.mouse.x - ui.press_mouse.x, NARROWEST)
			if width != widths[i] do result.resized = Column_Resize{column.id, width}
		}
		if .Held not_in resize && state.resizing == column.id do state.resizing = nil
	}
	starts[len(columns)] = x
	// Where a dragged column would go: a line before the column it would precede.
	if dragged, is := state.dragging.?; is {
		ui.cursor = .Grabbing
		before := drop_before(columns, widths, starts, x, state.drag_x, origin_x)
		line_x := x
		if b, has := before.?; has {
			for c, i in columns do if c.id == b do line_x = starts[i]
		}
		fill_rect(r, {line_x - 1, header.y, 2, header.h}, th.focus_ring)
		_ = dragged
	}
	// The columns button, at the right end.
	button_rect := Rect{header.x + header.w - TABLE_END_WIDTH + 4, header.y + 2, 24, 24}
	if toolbar_button(ui, child_id(id, "columns"), button_rect, .Columns, "Choose columns") {
		result.column_menu = [2]f32{button_rect.x, button_rect.y + button_rect.h}
	}
}

// The column a column dragged to pointer would go before: the first whose middle lies
// past it, among those that can move; nil to go last.
@(private = "file")
drop_before :: proc(
	columns: []Table_Column,
	widths, starts: []f32,
	end, pointer, origin_x: f32,
) -> Maybe(int) {
	for c, i in columns {
		if c.fixed || widths[i] <= 0 do continue
		if starts[i] + widths[i] / 2 > pointer do return c.id
	}
	return nil
}

// The width that shows a column's name and its longest value whole, with both paddings
// and the separator, up to WIDEST_FIT: a double click on the column's edge.
@(private = "file")
fit_width :: proc(r: ^Renderer, rows: Table_Rows, column: Table_Column) -> f32 {
	style := column.numeric ? Text_Style.Numeric : Text_Style.Body
	widest := text_width(r, column.title, .Small_Strong) + 14
	for row in 0 ..< rows.count {
		widest = max(widest, text_width(r, rows.cell(rows.data, row, column.id), style))
		if widest >= WIDEST_FIT do break
	}
	return clamp(widest + 17, NARROWEST, WIDEST_FIT)
}

@(private = "file")
primary_column :: proc(columns: []Table_Column) -> int {
	for c in columns do if c.primary do return c.id
	return columns[0].id
}

@(private = "file")
row_widget_states :: proc(states: Row_States, interaction: Interaction) -> (w: Widget_States) {
	if .Selected in states do w += {.Selected}
	if .Hovered in interaction do w += {.Hovered}
	return
}

@(private = "file")
sum :: proc(values: []f32) -> (total: f32) {
	for v in values do total += v
	return
}
