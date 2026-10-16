package main

import "core:fmt"
import "core:math"

import "../engine"
import ui "../ui"

// The albums shown until a click shows them all.
@(private = "file")
FIRST_ALBUMS :: 8
@(private = "file")
SIDEBAR_PADDING :: 10
@(private = "file")
ROW_HEIGHT :: 28
@(private = "file")
ROW_GAP :: 2
@(private = "file")
SWATCH :: 18

// What the sidebar keeps between frames: its scroll, what is unfolded, and the groups
// of the library, made again when the library changes.
Sidebar :: struct {
	scroll:       ui.Scroll,
	every_album:  bool,
	artists_open: bool,
	groups:       engine.Groups,
	// How many tracks could not be read, and how many changed.
	unreadable:   int,
	changed:      int,
	// The engine's revision the groups were made at, once made.
	made:         bool,
	revision:     u64,
}

// A line of the sidebar: a source of the table with its count.
@(private = "file")
Item :: struct {
	source: engine.Source,
	count:  int,
	mono:   bool,
	// The count in the error colour when there are any: files that could not be read.
	alarm:  bool,
	// A colour of its own, for an album, and its cover once drawn small.
	swatch: Maybe(ui.Color),
	cover:  Maybe(ui.Texture_Id),
}

// The sidebar: the library as a whole, its folders, its albums and its artists, each a
// click away from the table.
sidebar :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	s := &app.sidebar
	refresh_groups(app)
	ui.fill_rect(r, rect, th.surface_0)
	id := ui.widget_id("Sidebar")
	ui.declare(ctx, {id = id, role = .Group, label = ui.tr("Sidebar"), rect = rect})
	ui.push_parent(ctx, id)
	defer ui.pop_parent(ctx)

	library := [?]Item {
		{source = engine.All_Tracks{}, count = len(app.engine.library.tracks)},
		{source = engine.Recently_Changed{}, count = s.changed},
		{source = engine.Unreadable{}, count = s.unreadable, alarm = true},
	}
	folders := s.groups.folders[:]
	albums := s.groups.albums[:]
	shown_albums := s.every_album ? albums : albums[:min(len(albums), FIRST_ALBUMS)]
	more_albums := len(albums) - len(shown_albums)
	artists := s.groups.artists[:]

	// The content's height, for the scroll: every section with its title and its rows.
	height: f32 = 2 * SIDEBAR_PADDING + 26 + section_height(len(library))
	if len(folders) > 0 do height += 34 + section_height(len(folders))
	if len(albums) > 0 do height += 34 + section_height(len(shown_albums)) + (more_albums > 0 ? ROW_HEIGHT + ROW_GAP : 0)
	if len(artists) > 0 do height += 34 + (s.artists_open ? section_height(len(artists)) : 0)
	origin := ui.begin_scroll(ctx, id, rect, {rect.w, height}, &s.scroll)
	defer ui.end_scroll(ctx, id, rect, {rect.w, height}, &s.scroll)
	x := origin.x + SIDEBAR_PADDING
	width := rect.w - 2 * SIDEBAR_PADDING
	y := origin.y + SIDEBAR_PADDING

	section_title(
		ctx,
		ui.child_id(id, "library title"),
		ui.tr("Library"),
		{x, y, width, 26},
		.Center,
	)
	y += 26 + ROW_GAP
	for item, i in library do y = row(ctx, app, ui.child_id(id, "library", i), {x, y, width, ROW_HEIGHT}, item)

	if len(folders) > 0 {
		section_title(
			ctx,
			ui.child_id(id, "folders title"),
			ui.tr("Folders"),
			{x, y, width, 34},
			.Bottom,
		)
		y += 34 + ROW_GAP
		for folder, i in folders {
			item := Item {
				source = engine.Folder{folder.path},
				count  = folder.tracks,
				mono   = true,
			}
			y = row(ctx, app, ui.child_id(id, "folder", i), {x, y, width, ROW_HEIGHT}, item)
		}
	}
	if len(albums) > 0 {
		section_title(
			ctx,
			ui.child_id(id, "albums title"),
			ui.tr("Albums"),
			{x, y, width, 34},
			.Bottom,
		)
		y += 34 + ROW_GAP
		for album, i in shown_albums {
			item := Item {
				source = album.key,
				count  = album.tracks,
				swatch = swatch(album.key),
			}
			if track, has := album.cover_track.?; has do item.cover = thumbnail(ctx, app, track)
			y = row(ctx, app, ui.child_id(id, "album", i), {x, y, width, ROW_HEIGHT}, item)
		}
		if more_albums > 0 {
			more := ui.child_id(id, "more albums")
			more_rect := ui.Rect{x, y, width, ROW_HEIGHT}
			label := ui.tr_n("{n} more album", "{n} more albums", more_albums)
			interaction := ui.interact(ctx, more, more_rect)
			if .Hovered in interaction do ctx.cursor = .Pointer
			if .Clicked in interaction do s.every_album = true
			ui.draw_text(r, label, x + 8, y + ROW_HEIGHT / 2, .Small, th.text_tertiary)
			ui.declare(ctx, {id = more, role = .Button, label = label, rect = more_rect})
			y += ROW_HEIGHT + ROW_GAP
		}
	}
	if len(artists) > 0 {
		// A section that folds: its title is a button, with a chevron that points down when it is open and right when it is folded.
		header := ui.child_id(id, "artists")
		header_rect := ui.Rect{x, y, width, 34}
		interaction := ui.interact(ctx, header, header_rect)
		if .Hovered in interaction do ctx.cursor = .Pointer
		if .Clicked in interaction do s.artists_open = !s.artists_open
		chevron := ui.Rect{x + 8, y + 8 + 7, 12, 12}
		ui.draw_icon(r, s.artists_open ? .Chevron_Down : .Chevron_Right, chevron, th.text_tertiary)
		// Inset like the other titles, the chevron's 12 points and 4 more before the text,
		// both on the line 21 points under the header's top, as the design's markup has it.
		// section_title insets its text by 8.
		section_title(ctx, nil, ui.tr("Artists"), {x + 16, y + 8, width - 16, 26}, .Center)
		states: ui.Widget_States = s.artists_open ? {.Expanded} : {}
		ui.declare(
			ctx,
			{
				id = header,
				role = .Button,
				label = ui.tr("Artists"),
				rect = header_rect,
				states = states,
			},
		)
		y += 34 + ROW_GAP
		if s.artists_open {
			for artist, i in artists {
				item := Item {
					source = engine.Artist{artist.name},
					count  = artist.tracks,
				}
				y = row(ctx, app, ui.child_id(id, "artist", i), {x, y, width, ROW_HEIGHT}, item)
			}
		}
	}
}

// The window's title: the source the table lists, once something is open.
window_title :: proc(app: ^App) -> string {
	if !folder_open(app) do return "Colophon"
	return fmt.tprintf("Colophon · %s", source_name(app, app.engine.source))
}

// What a source is called, in the sidebar and in the window's title: a folder from the
// home folder, as the table shows it. Allocated with the temporary allocator.
@(private = "file")
source_name :: proc(app: ^App, source: engine.Source) -> string {
	switch s in source {
	case engine.All_Tracks:
		return ui.tr("All tracks")
	case engine.Recently_Changed:
		return ui.tr("Recently changed")
	case engine.Unreadable:
		return ui.tr("Unreadable files")
	case engine.Folder:
		return display_folder(s.path, app.home)
	case engine.Album_Key:
		return s.title
	case engine.Artist:
		return s.name
	}
	return ""
}

// Frees what the sidebar keeps.
destroy_sidebar :: proc(s: ^Sidebar) {
	engine.destroy_groups(&s.groups)
}

// Makes the groups and the counts again when the library changed: a scan, an edit, a
// save.
@(private = "file")
refresh_groups :: proc(app: ^App) {
	e := &app.engine
	s := &app.sidebar
	if s.made && s.revision == e.revision do return
	s.made, s.revision = true, e.revision
	engine.destroy_groups(&s.groups)
	s.groups = engine.groups(e, e.allocator)
	s.unreadable, s.changed = 0, 0
	for track, i in e.library.tracks {
		if track.error != .None do s.unreadable += 1
		if engine.is_changed(e, engine.Track_Id(i)) do s.changed += 1
	}
}

// A line of the sidebar: a click lists its source in the table.
@(private = "file")
row :: proc(ctx: ^ui.Ui, app: ^App, id: ui.Widget_Id, rect: ui.Rect, item: Item) -> (next_y: f32) {
	r := ctx.renderer
	th := ctx.theme
	label := source_name(app, item.source)
	selected := app.engine.source == item.source
	interaction := ui.interact(ctx, id, rect)
	if .Hovered in interaction do ctx.cursor = .Pointer
	if .Clicked in interaction do execute(app, engine.Show_Source{item.source})
	switch {
	case selected:
		ui.fill_rect(r, rect, th.surface_3, 4)
	case .Hovered in interaction:
		ui.fill_rect(r, rect, th.surface_2, 4)
	}
	middle := rect.y + rect.h / 2
	x := rect.x + 8
	if colour, has := item.swatch.?; has {
		square := ui.Rect{x, middle - SWATCH / 2, SWATCH, SWATCH}
		if texture, drawn := item.cover.?; drawn {
			ui.draw_image(r, texture, square, 3)
		} else {
			// As 1.0.0's: the swatch to a darker one, corner to corner.
			ui.fill_gradient(r, square, colour, darker(colour, 0.4), 3)
		}
		x += SWATCH + 8
	}
	count := fmt.tprint(item.count)
	count_width := ui.text_width(r, count, .Small)
	count_color := item.alarm && item.count > 0 ? th.error : th.text_tertiary
	ui.draw_text(r, count, rect.x + rect.w - 8, middle, .Small, count_color, .Right)
	style: ui.Text_Style = item.mono ? .Numeric : .Body
	color := selected ? th.text_primary : th.text_secondary
	ui.draw_text_fit(r, label, x, middle, rect.x + rect.w - 8 - count_width - 8 - x, style, color)
	states: ui.Widget_States = selected ? {.Selected} : {}
	ui.declare(
		ctx,
		{id = id, role = .Row, label = label, value = count, rect = rect, states = states},
	)
	return rect.y + rect.h + ROW_GAP
}

@(private = "file")
Title_Align :: enum u8 {
	Center,
	Bottom,
}

// A section's title, in capitals, declared as a label unless the caller declares the
// widget it belongs to.
@(private = "file")
section_title :: proc(
	ctx: ^ui.Ui,
	id: Maybe(ui.Widget_Id),
	title: string,
	rect: ui.Rect,
	align: Title_Align,
) {
	y := align == .Center ? rect.y + rect.h / 2 : rect.y + rect.h - 8
	width := ui.draw_text(ctx.renderer, title, rect.x + 8, y, .Label, ctx.theme.text_tertiary)
	if id, declared := id.?; declared {
		ui.declare(
			ctx,
			{id = id, role = .Label, label = title, rect = {rect.x + 8, y - 8, width, 16}},
		)
	}
}

@(private = "file")
section_height :: proc(rows: int) -> f32 {
	return f32(rows) * (ROW_HEIGHT + ROW_GAP)
}

// A colour of an album's own, from its name, shown until its cover is drawn small, or
// when it has none: a hue the same on every launch, in the mockup's saturation and
// value.
@(private = "file")
swatch :: proc(key: engine.Album_Key) -> ui.Color {
	h := u64(0xcbf29ce484222325)
	for b in transmute([]u8)key.title do h = (h ~ u64(b)) * 0x100000001b3
	if artist, has := key.artist.?; has {
		for b in transmute([]u8)artist do h = (h ~ u64(b)) * 0x100000001b3
	}
	return hsv(f32(h % 360), 0.55, 0.85)
}

// A colour from its hue in degrees, saturation and value from 0 to 1.
@(private = "file")
hsv :: proc(hue, saturation, value: f32) -> ui.Color {
	c := value * saturation
	x := c * (1 - abs(math.mod(hue / 60, 2) - 1))
	m := value - c
	rgb: [3]f32
	switch {
	case hue < 60:
		rgb = {c, x, 0}
	case hue < 120:
		rgb = {x, c, 0}
	case hue < 180:
		rgb = {0, c, x}
	case hue < 240:
		rgb = {0, x, c}
	case hue < 300:
		rgb = {x, 0, c}
	case:
		rgb = {c, 0, x}
	}
	return {rgb.r + m, rgb.g + m, rgb.b + m, 1}
}

// The colour with its brightness lowered by factor, as Slint's `darker`: the value of
// the colour divided by 1 + factor, which scaling the three channels does.
@(private = "file")
darker :: proc(colour: ui.Color, factor: f32) -> ui.Color {
	return {colour.r / (1 + factor), colour.g / (1 + factor), colour.b / (1 + factor), colour.a}
}
