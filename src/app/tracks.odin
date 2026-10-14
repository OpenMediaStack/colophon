package main

import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "../engine"
import lib "../library"
import ui "../ui"

// The track number's column, which the user neither moves nor hides, apart from the
// columns the engine names by their Table_Column.
@(private = "file")
NUMBER_COLUMN :: -1
// The engine sorts by the number too: its sort columns are the table's, after the number.
#assert(len(engine.Sort_Column) == len(engine.Table_Column) + 1)
#assert(int(engine.Sort_Column.Folder) == int(engine.Table_Column.Folder) + 1)

// The least width of each column, as the mockup, and the weights by which the text
// columns share the room left when the user has not sized them.
@(private = "file", rodata)
NATURAL_WIDTHS := [engine.Table_Column]f32 {
	.Title   = 200,
	.Artist  = 140,
	.Album   = 160,
	.Year    = 56,
	.Genre   = 96,
	.Time    = 56,
	.Bitrate = 72,
	.Tags    = 132,
	.File    = 180,
	.Folder  = 180,
}
@(private = "file", rodata)
WEIGHTS := [engine.Table_Column]f32 {
	.Title   = 1.6,
	.Artist  = 1.1,
	.Album   = 1.2,
	.Year    = 0,
	.Genre   = 0,
	.Time    = 0,
	.Bitrate = 0,
	.Tags    = 0,
	.File    = 1,
	.Folder  = 1,
}

// SDL counts a second click within this many seconds as a double click
// (SDL_HINT_MOUSE_DOUBLE_CLICK_TIME, 500 ms unless set).
@(private = "file")
DOUBLE_CLICK :: 0.5

// What the track table keeps between frames beside the toolkit's state.
Tracks :: struct {
	editing: Maybe(Cell_Editing),
	shrink:  Maybe(Shrink),
	// The track right-clicked, whose menu is open.
	menu:    Maybe(engine.Track_Id),
}

// The cell edited in place: the tracks its editor opened on, which it edits even once
// a scan has moved their rows, and whether its typing made a step of the history to go
// on with, so that Escape takes the whole of it back. The list is made with the
// engine's allocator and freed by end_cell or destroy_tracks.
Cell_Editing :: struct {
	tracks: [dynamic]engine.Track_Id,
	field:  engine.Field,
	typing: bool,
}

// A plain click on a track of a larger selection: the selection shrinks to it once a
// double click can no longer follow, since a double click edits the whole selection.
// The wait starts when the button is released.
Shrink :: struct {
	track: engine.Track_Id,
	at:    Maybe(f64),
}

destroy_tracks :: proc(s: ^Tracks) {
	if editing, is := s.editing.?; is do delete(editing.tracks)
	s^ = {}
}

// The track table: the centre column once something is open. What the user does to it
// becomes engine commands.
track_table :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	e := &app.engine
	columns := table_columns(app)
	rows := ui.Table_Rows{app, len(e.listed), track_cell, track_states}
	sized := e.view.column_widths != nil
	id := ui.widget_id("Tracks")
	result := ui.table(
		ctx,
		id,
		rect,
		columns,
		rows,
		&app.table,
		table_sort(e.sort),
		sized,
		focused_row(e),
		ui.tr("Tracks"),
	)
	take_rows(ctx, app, result)
	if column, sorted := result.sort_by.?; sorted do execute(app, engine.Sort_By{sort_column(column)})
	if resize, resized := result.resized.?; resized {
		execute(app, engine.Resize_Columns{widths_after(app, columns, rect.w, sized, resize)})
	}
	if move, moved := result.moved.?; moved && move.column != NUMBER_COLUMN {
		before: Maybe(engine.Table_Column)
		if b, has := move.before.?; has do before = engine.Table_Column(b)
		execute(app, engine.Move_Column{engine.Table_Column(move.column), before})
	}
	if at, opened := result.column_menu.?; opened do ui.open_menu(ctx, ui.widget_id("Column chooser"), at)
	if step, stepped := result.step.?; stepped {
		s: engine.Step = step.direction == .Up ? .Up : .Down
		if step.extend {
			execute(app, engine.Extend_Selection{s})
		} else {
			execute(app, engine.Move_Selection{s})
		}
	}
	if result.select_all do execute(app, engine.Select_All{})
	if result.space do execute(app, engine.Play_Pause{})
	column_chooser(ctx, app)
	track_menu(ctx, app)
}

// What the user did to the rows: a cell edited, a press, the release the shrinking
// click waits for, a right click.
@(private = "file")
take_rows :: proc(ctx: ^ui.Ui, app: ^App, result: ui.Table_Result) {
	e := &app.engine
	s := &app.tracks
	// What was typed in a cell comes first: Tab commits one cell as it opens the next,
	// and a click on another row commits the cell as it selects the row.
	if input, typed := result.input.?; typed do take_cell(app, input.field)
	if press, pressed := result.press.?; pressed && press.row < len(e.listed) {
		// Shift comes first, as in 1.0.0, when both are held.
		track := e.listed[press.row]
		s.shrink = nil
		switch {
		case .Shift in press.modifiers:
			execute(app, engine.Select_Range{track})
		case ui.COMMAND <= press.modifiers:
			execute(app, engine.Toggle_Selected{track})
		case engine.is_selected(&e.selection, track) && len(e.selection.tracks) > 1:
			s.shrink = Shrink {
				track = track,
			}
		case:
			execute(app, engine.Select{track})
		}
	}
	if cell, opened := result.edit.?; opened && cell.row < len(e.listed) do begin_cell(app, cell)
	if result.release {
		if shrink, armed := &s.shrink.?; armed && shrink.at == nil {
			shrink.at = ctx.input.time + DOUBLE_CLICK
		}
	}
	if shrink, armed := s.shrink.?; armed {
		if at, waiting := shrink.at.?; waiting {
			if ctx.input.time >= at {
				execute(app, engine.Select{shrink.track})
				s.shrink = nil
			} else {
				ui.wake_at(ctx, at)
			}
		}
	}
	if menu, opened := result.row_menu.?; opened && menu.row < len(e.listed) {
		// The row joins the selection unless it is in it already, as in 1.0.0.
		s.shrink = nil
		track := e.listed[menu.row]
		if !engine.is_selected(&e.selection, track) do execute(app, engine.Select{track})
		s.menu = track
		ui.open_menu(ctx, ui.widget_id("Track menu"), menu.at)
	}
}

// Captures the tracks a cell's editor opened on: the selected ones, the row's track
// joining the selection first when it was not in it.
@(private = "file")
begin_cell :: proc(app: ^App, cell: ui.Cell_Edit) {
	e := &app.engine
	s := &app.tracks
	s.shrink = nil
	field, editable := column_field(cell.column)
	if !editable do return
	track := e.listed[cell.row]
	if !engine.is_selected(&e.selection, track) do execute(app, engine.Select{track})
	end_cell(app)
	tracks := make([dynamic]engine.Track_Id, 0, len(e.selection.tracks), e.allocator)
	append(&tracks, ..e.selection.tracks[:])
	s.editing = Cell_Editing{tracks, field, false}
}

// Takes in what the cell's editor reported, as the inspector's fields do: each change
// at once on the tracks captured, the typing making one step of the history; Escape
// takes the whole of it back.
@(private = "file")
take_cell :: proc(app: ^App, result: ui.Text_Field_Result) {
	editing, is := &app.tracks.editing.?
	if !is do return
	if result.changed {
		if edit, fits := edit_of(editing.field, result.text); fits {
			execute(
				app,
				engine.Edit_Tracks {
					tracks = editing.tracks[:],
					edit = edit,
					continues = editing.typing,
				},
			)
			editing.typing = true
		}
	}
	if result.cancelled && editing.typing do execute(app, engine.Undo{})
	if result.committed || result.cancelled do end_cell(app)
}

@(private = "file")
end_cell :: proc(app: ^App) {
	if editing, is := app.tracks.editing.?; is do delete(editing.tracks)
	app.tracks.editing = nil
}

// The tag a column's cells edit, for the columns that show one.
@(private = "file")
column_field :: proc(column: int) -> (field: engine.Field, editable: bool) {
	if column == NUMBER_COLUMN do return .Track, true
	#partial switch engine.Table_Column(column) {
	case .Title:
		return .Title, true
	case .Artist:
		return .Artist, true
	case .Album:
		return .Album, true
	case .Year:
		return .Year, true
	case .Genre:
		return .Genre, true
	}
	return
}

// The menu of a right click on a row, over the selected tracks: play the row's track,
// select its album, number the selection, revert it.
@(private = "file")
track_menu :: proc(ctx: ^ui.Ui, app: ^App) {
	e := &app.engine
	id := ui.widget_id("Track menu")
	if !ui.is_menu_open(ctx, id) do return
	items := [?]ui.Menu_Item {
		{label = ui.tr("Play"), disabled = !engine.can_play(e)},
		{label = ui.tr("Select Album"), separator = true},
		{label = ui.tr("Number Tracks")},
		{label = ui.tr("Revert"), separator = true, disabled = !engine.can_revert(e)},
	}
	chosen, picked := ui.menu(ctx, id, items[:], ui.tr("Track menu")).?
	if !picked do return
	switch chosen {
	case 0:
		if track, has := app.tracks.menu.?; has do execute(app, engine.Play{track})
	case 1:
		execute(app, engine.Select_Album{})
	case 2:
		execute(app, engine.Number_Tracks{})
	case 3:
		execute(app, engine.Revert{})
	}
}

// The columns the table shows, in the user's order: the number, then those not hidden,
// at the widths the user gave them when sized. Temporary.
@(private = "file")
table_columns :: proc(app: ^App) -> []ui.Table_Column {
	view := app.engine.view
	widths, sized := view.column_widths.?
	columns := make(
		[dynamic]ui.Table_Column,
		0,
		len(engine.Table_Column) + 1,
		context.temp_allocator,
	)
	append(
		&columns,
		ui.Table_Column {
			id = NUMBER_COLUMN,
			title = "#",
			min_width = 36,
			mono = true,
			align = .Right,
			fixed = true,
			sort_label = ui.fill(ui.tr("Sort by {}"), "#"),
			editable = true,
			accepts = accepts_of(.Track),
		},
	)
	for column in view.column_order {
		if hideable, is := engine.hideable_column(column); is && hideable not_in view.columns do continue
		name := column_name(column)
		numeric := column == .Year || column == .Time || column == .Bitrate
		field, editable := column_field(int(column))
		append(
			&columns,
			ui.Table_Column {
				id = int(column),
				title = name,
				min_width = NATURAL_WIDTHS[column],
				weight = WEIGHTS[column],
				width = sized ? f32(widths[column]) : 0,
				mono = numeric || column == .Tags,
				align = numeric ? .Right : .Left,
				primary = column == .Title,
				sort_label = ui.fill(ui.tr("Sort by {}"), name),
				editable = editable,
				accepts = editable ? accepts_of(field) : nil,
				choices = column == .Genre ? genres(app) : nil,
			},
		)
	}
	return columns[:]
}

// What the user calls a column.
@(private = "file")
column_name :: proc(column: engine.Table_Column) -> string {
	switch column {
	case .Title:
		return ui.tr("Title")
	case .Artist:
		return ui.tr("Artist")
	case .Album:
		return ui.tr("Album")
	case .Year:
		return ui.tr("Year")
	case .Genre:
		return ui.tr("Genre")
	case .Time:
		return ui.tr("Time")
	case .Bitrate:
		return ui.tr("Bitrate")
	case .Tags:
		return ui.tr("Tags")
	case .File:
		return ui.tr("File")
	case .Folder:
		return ui.tr("Folder")
	}
	return ""
}

// The text of a cell: the tags as they will be saved, the audio as it was read, and
// the file's name and folder. Allocated with the temporary allocator.
@(private)
track_cell :: proc(data: rawptr, row, column: int) -> string {
	app := (^App)(data)
	e := &app.engine
	if row < 0 || row >= len(e.listed) do return ""
	id := e.listed[row]
	track := &e.library.tracks[id]
	tags, readable := engine.shown_tags(e, id)
	if column == NUMBER_COLUMN {
		if !readable do return ""
		if number, has := tags.track.?; has do return fmt.tprintf("%02d", number)
		return ""
	}
	switch engine.Table_Column(column) {
	case .Title:
		// A file without a title goes by its name.
		if readable {
			if title, has := tags.title.?; has do return title
		}
		return filepath.stem(track.path)
	case .File:
		return filepath.base(track.path)
	case .Folder:
		return display_folder(filepath.dir(track.path), app.home)
	case .Artist, .Album, .Genre, .Year, .Time, .Bitrate, .Tags:
		if !readable do return ""
		return tag_cell(tags, &track.metadata, engine.Table_Column(column))
	}
	return ""
}

// The text of a cell of a readable track, from its tags and its audio. Allocated with
// the temporary allocator.
@(private = "file")
tag_cell :: proc(tags: ^lib.Tags, metadata: ^lib.Metadata, column: engine.Table_Column) -> string {
	#partial switch column {
	case .Artist:
		return tags.artist.? or_else ""
	case .Album:
		return tags.album.? or_else ""
	case .Genre:
		return tags.genre.? or_else ""
	case .Year:
		if year, has := tags.year.?; has do return fmt.tprint(year)
	case .Time:
		return duration_text(metadata.audio.duration)
	case .Bitrate:
		audio := metadata.audio
		if audio.bitrate_mode == .Variable do return fmt.tprintf("VBR %d", audio.bitrate_kbps)
		return fmt.tprint(audio.bitrate_kbps)
	case .Tags:
		return lib.tag_formats_string(metadata.formats, context.temp_allocator)
	}
	return ""
}

// What a row is going through.
@(private)
track_states :: proc(data: rawptr, row: int) -> (states: ui.Row_States) {
	app := (^App)(data)
	e := &app.engine
	if row < 0 || row >= len(e.listed) do return
	id := e.listed[row]
	track := &e.library.tracks[id]
	if engine.is_selected(&e.selection, id) do states += {.Selected}
	if id in e.edits.pending do states += {.Modified}
	if track.error != .None do states += {.Error}
	if playing, has := e.playback.track.?; has && playing == id do states += {.Playing}
	if id in warnings(app) do states += {.Warning}
	if tags, readable := engine.shown_tags(e, id); readable && tags.title == nil do states += {.Placeholder}
	return
}

// The row the arrow keys move from, in the table's order.
@(private = "file")
focused_row :: proc(e: ^engine.Engine) -> Maybe(int) {
	focus, has := e.selection.focus.?
	if !has do return nil
	for id, i in e.listed do if id == focus do return i
	return nil
}

@(private = "file")
table_sort :: proc(sort: Maybe(engine.Sort)) -> Maybe(ui.Table_Sort) {
	s, has := sort.?
	if !has do return nil
	column := s.column == .Number ? NUMBER_COLUMN : int(s.column) - 1
	return ui.Table_Sort{column, s.descending}
}

@(private = "file")
sort_column :: proc(column: int) -> engine.Sort_Column {
	if column == NUMBER_COLUMN do return .Number
	return engine.Sort_Column(column + 1)
}

// Every column's width after one was resized: the others keep the width they have,
// shared or sized, and a hidden one the width it had, or its least width when it never
// had one. 1.0.0 gave a hidden column its least width back on every resize.
@(private = "file")
widths_after :: proc(
	app: ^App,
	columns: []ui.Table_Column,
	width: f32,
	sized: bool,
	resize: ui.Column_Resize,
) -> (
	widths: engine.Column_Widths,
) {
	for column in engine.Table_Column do widths[column] = int(NATURAL_WIDTHS[column])
	if existing, has := app.engine.view.column_widths.?; has do widths = existing
	current := ui.column_widths(columns, width, sized, context.temp_allocator)
	for c, i in columns {
		if c.id != NUMBER_COLUMN do widths[engine.Table_Column(c.id)] = int(math.round(current[i]))
	}
	widths[engine.Table_Column(resize.column)] = int(math.round(resize.width))
	return
}

// The column chooser: every column with a tick for those shown, the title that always
// shows apart, and the way back to the mockup's columns.
@(private = "file")
column_chooser :: proc(ctx: ^ui.Ui, app: ^App) {
	e := &app.engine
	id := ui.widget_id("Column chooser")
	if !ui.is_menu_open(ctx, id) do return
	items := make([dynamic]ui.Menu_Item, 0, len(engine.Table_Column) + 1, context.temp_allocator)
	for column in engine.Table_Column {
		hideable, is := engine.hideable_column(column)
		shown := !is || hideable in e.view.columns
		append(&items, ui.Menu_Item{label = column_name(column), checked = shown, disabled = !is})
	}
	append(&items, ui.Menu_Item{label = ui.tr("Reset to default columns"), separator = true})
	chosen, picked := ui.menu(ctx, id, items[:], ui.tr("Columns")).?
	if !picked do return
	if chosen == len(engine.Table_Column) {
		execute(app, engine.Reset_Columns{})
	} else if hideable, is := engine.hideable_column(engine.Table_Column(chosen)); is {
		execute(app, engine.Toggle_Column{hideable})
	}
}

// A duration as players show it: minutes and seconds, with hours from an hour on.
// Allocated with the temporary allocator.
@(private)
duration_text :: proc(duration: time.Duration) -> string {
	seconds := int(duration / time.Second)
	hours, minutes := seconds / 3600, seconds / 60 % 60
	seconds %= 60
	if hours > 0 do return fmt.tprintf("%d:%02d:%02d", hours, minutes, seconds)
	return fmt.tprintf("%d:%02d", minutes, seconds)
}

// A folder as the user knows it: inside their home, from "~". Allocated with the
// temporary allocator.
@(private)
display_folder :: proc(folder, home: string) -> string {
	if len(home) == 0 || !strings.has_prefix(folder, home) do return folder
	rest := folder[len(home):]
	if len(rest) == 0 do return "~"
	if rest[0] != filepath.SEPARATOR do return folder
	return strings.concatenate({"~", rest}, context.temp_allocator)
}
