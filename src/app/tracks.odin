package main

import "core:fmt"
import "core:math"
import "core:os"
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

// The least width of each column, as the mockup, and the weights by which the text
// columns share the room left when the user has not sized them.
@(private = "file")
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
@(private = "file")
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
	if press, pressed := result.press.?; pressed && press.row < len(e.listed) {
		track := e.listed[press.row]
		switch {
		case ui.COMMAND <= press.modifiers:
			execute(app, engine.Toggle_Selected{track})
		case .Shift in press.modifiers:
			execute(app, engine.Select_Range{track})
		case:
			execute(app, engine.Select{track})
		}
	}
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
		},
	)
	for column in view.column_order {
		if hideable, is := engine.hideable_column(column); is && hideable not_in view.columns do continue
		name := column_name(column)
		numeric := column == .Year || column == .Time || column == .Bitrate
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
// the file's name and folder. Temporary.
@(private = "file")
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
		return display_folder(filepath.dir(track.path))
	case .Artist, .Album, .Genre, .Year, .Time, .Bitrate, .Tags:
		if !readable do return ""
		return tag_cell(tags, track.metadata, engine.Table_Column(column))
	}
	return ""
}

// The text of a cell of a readable track, from its tags and its audio. Temporary.
@(private = "file")
tag_cell :: proc(tags: ^lib.Tags, metadata: lib.Metadata, column: engine.Table_Column) -> string {
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

// What a row is going through. The warnings come with slice 35.
@(private = "file")
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
// shared or sized, and the hidden ones their least width, as 1.0.0 did.
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
// Temporary.
@(private = "file")
duration_text :: proc(duration: time.Duration) -> string {
	seconds := int(duration / time.Second)
	hours, minutes := seconds / 3600, seconds / 60 % 60
	seconds %= 60
	if hours > 0 do return fmt.tprintf("%d:%02d:%02d", hours, minutes, seconds)
	return fmt.tprintf("%d:%02d", minutes, seconds)
}

// A folder as the user knows it: inside their home, from "~". Temporary.
@(private = "file")
display_folder :: proc(folder: string) -> string {
	home := os.get_env("HOME", context.temp_allocator)
	if len(home) == 0 || !strings.has_prefix(folder, home) do return folder
	rest := folder[len(home):]
	if len(rest) == 0 do return "~"
	if rest[0] != '/' && rest[0] != '\\' do return folder
	return strings.concatenate({"~", rest}, context.temp_allocator)
}
