package ui

import "core:math"

// A column of a table: the caller's id for it, and how it is drawn and sized.
Table_Column :: struct {
	id:         int,
	title:      string,
	// The width the user gave it, when the table is sized; else the table shares its width
	// between the columns, each getting min_width and its weight's share of what is left.
	width:      f32,
	min_width:  f32,
	weight:     f32,
	// In JetBrains Mono, as numbers that line up and the tag versions.
	mono:       bool,
	// Where its text goes: numbers to the right.
	align:      Align,
	// What assistive technologies call its name, which sorts by it: "Sort by Title";
	// its title when empty.
	sort_label: string,
	// The column whose text says which row it is, the title: in the row's colours.
	primary:    bool,
	// Not resized, moved or hidden by the user: the track number.
	fixed:      bool,
	// Its cells are edited in place, but in the rows whose file could not be read.
	editable:   bool,
	// Whether text typed in one of its cells is a value it takes; nil takes any. The
	// editor shows the error ring while it is not, and stays open on Enter and Tab.
	accepts:    proc(text: string) -> bool,
	// Suggested as the user types in one of its cells, the genres: the editor is then a
	// combo box.
	choices:    []string,
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
	// The text of a cell, which must last until the next frame: it is declared as the
	// cell's label.
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
	// The cell edited in place.
	editing:     Maybe(Cell_Edit),
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

// A column resized to width. The first resize of columns the user never sized gives
// one width: the app takes the others from column_widths.
Column_Resize :: struct {
	column: int,
	width:  f32,
}

// A right click on a row, or a Control click on macOS: its menu, at a point.
Row_Menu :: struct {
	row: int,
	at:  [2]f32,
}

// A cell of a row, by the id of its column: the one edited in place.
Cell_Edit :: struct {
	row, column: int,
}

// What was typed in the cell edited in place, which the app takes in as it does a
// field's: each change at once, then the commit, or Escape putting the value back.
Cell_Input :: struct {
	cell:  Cell_Edit,
	field: Text_Field_Result,
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
	// A cell whose editor opened: a double click, Enter or F2 on the focused row, Tab
	// from the cell before.
	edit:        Maybe(Cell_Edit),
	step:        Maybe(Table_Step),
	select_all:  bool,
	// Space on a focused table: play or pause.
	space:       bool,
	// What was typed in the cell edited in place.
	input:       Maybe(Cell_Input),
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
// in view, and which Enter or F2 edits. The editable cells are edited in place.
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
	push_parent(ui, id)
	defer pop_parent(ui)

	if focused do table_keys(ui, &result)
	// Enter or F2 edits the focused row's title, or its first editable cell.
	row, has_row := focused_row.?
	if focused && has_row && row < rows.count && .Error not_in rows.states(rows.data, row) {
		if column, found := first_editable(columns, widths).?; found {
			if take_key(ui, .Enter) || take_key(ui, .F2) {
				start_editing(ui, id, body, columns, widths, state, {row, column}, &result)
			}
		}
	}
	// The focused row is kept in view once, when it moves, above the horizontal scroll
	// bar when there is one; the editing of another row then ends.
	view := body.h - (content.x > body.w ? SCROLL_BAR : 0)
	left_row := false
	if cell, editing := state.editing.?; editing {
		left_row = has_row ? state.revealed != row && cell.row != row : state.revealed != nil
	}
	if !has_row do state.revealed = nil
	if has_row && state.revealed != row {
		scroll_into_view(&state.scroll, f32(row) * TABLE_ROW_HEIGHT, TABLE_ROW_HEIGHT, view)
		state.revealed = row
	}

	// A click below the rows still gives the table the focus; the rows, drawn after,
	// take the clicks on them.
	if .Pressed in interact(ui, child_id(id, "body"), body) && !focused do request_focus(ui, id)
	origin := begin_scroll(ui, id, body, content, &state.scroll)
	// The outline goes while a cell is edited, as the keyboard is the editor's.
	double_clicked := draw_rows(ui, id, body, origin, columns, widths, rows, focused, &result)
	if cell, editing := state.editing.?; editing {
		edit_cell(ui, id, body, origin, columns, widths, rows, state, cell, left_row, &result)
	}
	end_scroll(ui, id, body, content, &state.scroll)
	if cell, opened := double_clicked.?; opened && state.editing == nil {
		start_editing(ui, id, body, columns, widths, state, cell, &result)
	}
	draw_header(ui, id, header, origin.x, columns, widths, rows, sort, state, &result)
	return
}

// Opens the editor of a cell, which takes the focus with all its text selected, and
// scrolls the least that shows it.
@(private = "file")
start_editing :: proc(
	ui: ^Ui,
	id: Widget_Id,
	body: Rect,
	columns: []Table_Column,
	widths: []f32,
	state: ^Table_State,
	cell: Cell_Edit,
	result: ^Table_Result,
) {
	state.editing = cell
	result.edit = cell
	request_focus(ui, editor_id(id, cell), by_key = true)
	if x, w, _, found := column_span(columns, widths, cell.column); found {
		scroll_into_view(&state.scroll, x, w, body.w - TABLE_END_WIDTH, axis = 0)
	}
	scroll_into_view(&state.scroll, f32(cell.row) * TABLE_ROW_HEIGHT, TABLE_ROW_HEIGHT, body.h)
}

// The suggestions under a cell are this wide at least, as 1.0.0's.
@(private = "file")
SUGGESTIONS_WIDTH :: 180

// Each cell's editor has an id of its own, so that the next cell edited starts afresh.
@(private)
editor_id :: proc(id: Widget_Id, cell: Cell_Edit) -> Widget_Id {
	return child_id(child_id(id, "editor", cell.row), "column", cell.column)
}

// The editor over the cell edited in place. Enter ends the editing and Escape gives it
// up, the table taking the keyboard back; Tab goes to the next editable cell of the row
// and Shift+Tab to the one before, the editing ending past the last. A click elsewhere
// ends it, and so does the focus moving to another row, the table then taking the
// keyboard back. Text the column does not take keeps the editor open on Enter and Tab,
// and is given up when the editing ends otherwise.
@(private = "file")
edit_cell :: proc(
	ui: ^Ui,
	id: Widget_Id,
	body: Rect,
	origin: [2]f32,
	columns: []Table_Column,
	widths: []f32,
	rows: Table_Rows,
	state: ^Table_State,
	cell: Cell_Edit,
	left_row: bool,
	result: ^Table_Result,
) {
	editor := editor_id(id, cell)
	was_focused := ui.focus == editor
	x, w, index, found := column_span(columns, widths, cell.column)
	if !found || w <= 0 || cell.row >= rows.count {
		// The cell is gone: what was typed in it is committed, and the table takes the
		// keyboard back.
		state.editing = nil
		if was_focused {
			if ui.edit_owner == editor {
				result.input = Cell_Input{cell, {committed = true, text = edit_text(&ui.edit)}}
			}
			ui.edit_reported = true
			request_focus(ui, id)
		}
		return
	}
	column := columns[index]
	// Over the cell, but for its separator.
	rect := Rect {
		origin.x + x,
		origin.y + f32(cell.row) * TABLE_ROW_HEIGHT + 1,
		w - 1,
		TABLE_ROW_HEIGHT - 2,
	}
	value := rows.cell(rows.data, cell.row, cell.column)
	shown := ui.edit_owner == editor ? edit_text(&ui.edit) : value
	options: Text_Field_Options
	if column.mono do options.flags += {.Numeric}
	if !takes(column, shown) do options.flags += {.Error}
	// Tab belongs to the table while a cell is edited: it goes to the next cell.
	tab := ui.tab
	ui.tab = nil
	field: Text_Field_Result
	if len(column.choices) > 0 {
		field = combo_box(
			ui,
			editor,
			rect,
			value,
			column.title,
			column.choices,
			options,
			list_width = SUGGESTIONS_WIDTH,
		)
	} else {
		field = text_field(ui, editor, rect, value, column.title, options)
	}
	tabbed := ui.tab
	ui.tab = tab
	// The focus moving to another row ends the editing as a click elsewhere does.
	if left_row && was_focused && !field.committed && !field.cancelled {
		field.committed = true
		ui.edit_reported = true
	}
	// A click on the editor's own suggestions is not a click elsewhere.
	clicked := .Left in ui.input.pressed && !mouse_in_popup(ui)
	if field.committed && !takes(column, field.text) {
		field.committed = false
		if was_focused && !clicked && !left_row {
			// Enter or Tab: the editor stays open, showing what is wrong.
			tabbed = nil
			request_focus(ui, editor)
		} else {
			// Given up: back to the value the cell had when its editor took the focus,
			// which the Ui kept when another widget took the focus.
			field.cancelled = true
			field.text = was_focused ? string(ui.edit_start[:]) : string(ui.edit_ended_start[:])
		}
	}
	// The error ring follows the text at once, rather than on the caret's next blink.
	if takes(column, field.text) != takes(column, shown) do wake_at(ui, ui.input.time)
	if field.changed || field.committed || field.cancelled do result.input = Cell_Input{cell, field}
	if direction, has := tabbed.?; has {
		step := direction == .Forward ? 1 : -1
		if next, found_next := editable_after(columns, widths, index, step).?; found_next {
			start_editing(ui, id, body, columns, widths, state, {cell.row, next}, result)
			return
		}
	}
	if tabbed != nil || field.committed || field.cancelled || left_row {
		state.editing = nil
		if was_focused && !clicked do take_focus_back(ui, id)
	}
}

// Gives the table the keyboard back from its editor, unless another widget asked for
// it this frame.
@(private = "file")
take_focus_back :: proc(ui: ^Ui, id: Widget_Id) {
	if next, asked := ui.focus_next.?; asked && next != 0 do return
	request_focus(ui, id)
}

@(private = "file")
takes :: proc(column: Table_Column, text: string) -> bool {
	return column.accepts == nil || column.accepts(text)
}

// Where a column starts, from the left end of the rows, and how wide it is.
@(private = "file")
column_span :: proc(
	columns: []Table_Column,
	widths: []f32,
	column: int,
) -> (
	x, w: f32,
	index: int,
	found: bool,
) {
	x = TABLE_STATUS_WIDTH
	for c, i in columns {
		if c.id == column do return x, widths[i], i, true
		x += widths[i]
	}
	return
}

// The cell Enter edits: the title when it is editable, else the first editable one.
@(private = "file")
first_editable :: proc(columns: []Table_Column, widths: []f32) -> Maybe(int) {
	for c, i in columns do if c.primary && c.editable && widths[i] > 0 do return c.id
	return editable_after(columns, widths, -1, 1)
}

// The first editable column shown after the one at index from, or before it when step
// is -1.
@(private = "file")
editable_after :: proc(columns: []Table_Column, widths: []f32, from, step: int) -> Maybe(int) {
	for i := from + step; i >= 0 && i < len(columns); i += step {
		if columns[i].editable && widths[i] > 0 do return columns[i].id
	}
	return nil
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

// The rows in view, from the first one the scroll shows: each declared with its cells.
// Gives the editable cell double clicked.
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
) -> (
	double_clicked: Maybe(Cell_Edit),
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
		if .Right_Clicked in interaction {
			result.row_menu = Row_Menu{row, in_.mouse}
			request_focus(ui, id)
		}
		switch {
		case .Selected in states:
			fill_rect(r, rect, th.accent_selection)
		case .Hovered in interaction:
			fill_rect(r, rect, th.surface_3)
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
			},
		)
		push_parent(ui, row_id)
		draw_status(ui, row_id, {rect.x, y, TABLE_STATUS_WIDTH, TABLE_ROW_HEIGHT}, states)
		x := rect.x + TABLE_STATUS_WIDTH
		for column, i in columns {
			cell := Rect{x, y, widths[i], TABLE_ROW_HEIGHT}
			x += widths[i]
			if cell.w <= 0 do continue
			text := rows.cell(rows.data, row, column.id)
			draw_cell(r, th, cell, text, column, states)
			// A line at the right edge of each cell, but the number's.
			if !column.fixed do fill_rect(r, {cell.x + cell.w - 1, y, 1, TABLE_ROW_HEIGHT}, th.border_row)
			declare(
				ui,
				{
					id = child_id(row_id, "cell", column.id),
					role = .Cell,
					label = text,
					rect = cell,
				},
			)
			if .Double_Clicked in interaction &&
			   column.editable &&
			   rect_contains(cell, in_.mouse) &&
			   .Error not_in states {
				double_clicked = Cell_Edit{row, column.id}
			}
		}
		pop_parent(ui)
		fill_rect(r, {rect.x, y + TABLE_ROW_HEIGHT - 1, rect.w, 1}, th.border_row)
		if .Selected in states && focused {
			above := row > 0 && .Selected in rows.states(rows.data, row - 1)
			below := row + 1 < rows.count && .Selected in rows.states(rows.data, row + 1)
			draw_selection_outline(r, th, rect, above, below)
		}
	}
	return
}

// The status column: why a row stands out, one sign at most, declared as an image.
@(private = "file")
draw_status :: proc(ui: ^Ui, row_id: Widget_Id, cell: Rect, states: Row_States) {
	r := ui.renderer
	th := ui.theme
	label: string
	switch {
	case .Error in states:
		draw_icon_centered(r, .Circle_Alert, cell, th.error, 14)
		label = "Unreadable"
	case .Playing in states:
		draw_icon_centered(r, .Volume, cell, th.accent_text, 14)
		label = "Playing"
	case .Modified in states:
		fill_rect(r, centered(cell, 6, 6), th.accent, 3)
		label = "Unsaved changes"
	case .Warning in states:
		draw_icon_centered(r, .Triangle_Alert, cell, th.warning, 14)
		label = "Unlike the rest of its album"
	}
	if label != "" do declare(ui, {id = child_id(row_id, "status"), role = .Image, label = label, rect = cell})
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
	style := column.mono ? Text_Style.Numeric : Text_Style.Body
	push_clip(r, cell)
	defer pop_clip(r)
	inner := rect_inset(cell, 8, 0)
	draw_text_fit(r, text, inner.x, cell.y + cell.h / 2, inner.w, style, color, column.align)
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
// anywhere opens the column chooser, as does the button at its right end. A press
// gives the table the focus.
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
		if .Pressed in interaction do request_focus(ui, id)
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
						drop_before(columns, widths, starts, in_.mouse.x),
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
		draw_column_name(r, rect_inset(cell, 8, 0), column, sorted, descending, color)
		declare(
			ui,
			{
				id = cell_id,
				role = .Button,
				label = column.sort_label != "" ? column.sort_label : column.title,
				rect = name,
				states = sorted ? {.Selected} : {},
			},
		)
		if column.fixed do continue
		// The separator at the column's right edge, which a drag resizes.
		fill_rect(r, {cell.x + cell.w - 1, cell.y, 1, cell.h}, th.border_subtle)
		handle := Rect{cell.x + cell.w - RESIZE_HANDLE, cell.y, RESIZE_HANDLE, cell.h}
		resize := interact(ui, handle_id, handle)
		if .Hovered in resize || .Held in resize do ui.cursor = .Resize_Horizontal
		if .Pressed in resize {
			state.resizing = column.id
			state.resize_from = widths[i]
			request_focus(ui, id)
		}
		if .Double_Clicked in resize do result.resized = Column_Resize{column.id, fit_width(r, rows, column)}
		if .Held in resize && state.resizing == column.id {
			// The drag's distance first: the width stays exact while the pointer has not
			// moved, and a press alone resizes nothing.
			width := max(state.resize_from + (in_.mouse.x - ui.press_mouse.x), NARROWEST)
			if width != widths[i] do result.resized = Column_Resize{column.id, width}
		}
		if .Held not_in resize && state.resizing == column.id do state.resizing = nil
	}
	starts[len(columns)] = x
	// Where a dragged column would go: a line before the column it would precede.
	if state.dragging != nil {
		ui.cursor = .Grabbing
		line_x := x
		if before, has := drop_before(columns, widths, starts, state.drag_x).?; has {
			for c, i in columns do if c.id == before do line_x = starts[i]
		}
		fill_rect(r, {line_x - 1, header.y, 2, header.h}, th.accent)
	}
	// A drag or a resize whose column went away ends with the button.
	if .Left not_in in_.down {
		state.dragging = nil
		state.resizing = nil
	}
	// The columns button, at the right end, over the names scrolled under it.
	end := Rect{header.x + header.w - TABLE_END_WIDTH, header.y, TABLE_END_WIDTH, header.h - 1}
	fill_rect(r, end, th.surface_2)
	button_rect := Rect{end.x + 4, header.y + 2, 24, 24}
	if toolbar_button(ui, child_id(id, "columns"), button_rect, .Columns, "Choose columns") {
		result.column_menu = [2]f32{button_rect.x, button_rect.y + button_rect.h}
	}
	if .Right in in_.pressed && mouse_over(ui, header) do result.column_menu = in_.mouse
}

// A column's name in the header, and the order's chevron right after it when the table
// is sorted by it, both packed to the side the column's text goes to.
@(private = "file")
draw_column_name :: proc(
	r: ^Renderer,
	inner: Rect,
	column: Table_Column,
	sorted, descending: bool,
	color: Color,
) {
	MARKER :: 10
	GAP :: 4
	middle := inner.y + inner.h / 2
	if !sorted {
		draw_text_fit(
			r,
			column.title,
			inner.x,
			middle,
			inner.w,
			.Small_Strong,
			color,
			column.align,
		)
		return
	}
	title_width := min(text_width(r, column.title, .Small_Strong), inner.w - MARKER - GAP)
	text_x := column.align == .Right ? inner.x + inner.w - MARKER - GAP - title_width : inner.x
	draw_text_fit(r, column.title, text_x, middle, title_width, .Small_Strong, color)
	icon := descending ? Icon.Chevron_Down : Icon.Chevron_Up
	draw_icon(r, icon, {text_x + title_width + GAP, middle - MARKER / 2, MARKER, MARKER}, color)
}

// The column a column dragged to pointer would go before: the first whose middle lies
// past it, among those that can move; nil to go last.
@(private = "file")
drop_before :: proc(columns: []Table_Column, widths, starts: []f32, pointer: f32) -> Maybe(int) {
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
	style := column.mono ? Text_Style.Numeric : Text_Style.Body
	widest := text_width(r, column.title, .Small_Strong)
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
