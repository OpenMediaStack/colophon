package main

import "core:fmt"
import "core:strconv"
import "core:strings"

import "../engine"
import lib "../library"
import ui "../ui"

@(private = "file")
INSPECTOR_PADDING :: 16
@(private = "file")
SECTION_GAP :: 16
@(private = "file")
FIELD_LABEL_WIDTH :: 96
@(private)
FIELD_GAP :: 6
// The actions pinned at the bottom: a line, then the buttons with 14 points around.
@(private = "file")
ACTIONS_HEIGHT :: 57
// The comment shows three lines, and the rest scrolls.
@(private = "file")
COMMENT_HEIGHT :: 64
@(private = "file")
NBSP :: " "

// What the inspector keeps between frames: its scroll, which sections show their
// content, and what the selected tracks share, made again when the selection or the
// library changes.
Inspector :: struct {
	scroll:          ui.Scroll,
	comment_scroll:  ui.Scroll,
	tags_open:       bool,
	file_open:       bool,
	tag_format_open: bool,
	frames_open:     bool,
	inspection:      engine.Inspection,
	// What the inspection was made from, once made: the engine's revision and how many
	// commands had run.
	made:            bool,
	revision:        u64,
	commands:        int,
	// The field being typed in, whose next changes go on with the same step of the
	// history, so that Escape takes the whole of the typing back.
	typing:          Maybe(engine.Field),
	// The cover drawn in the well, made again when the selection's cover changes.
	cover:           Maybe(Shown_Cover),
	// The layout of the tags of the single track selected, in developer mode.
	layout:          Maybe(Shown_Layout),
}

// A cover decoded into a texture, by the key of the cover it shows.
Shown_Cover :: struct {
	key:     lib.Cover_Key,
	// nil for a cover that could not be read or decoded, tried once.
	texture: Maybe(ui.Texture_Id),
}

// The side of the cover well, in points.
@(private = "file")
WELL :: 64

// The side of the well's cover in pixels, 1.0.0's: the well at twice the scale.
@(private = "file")
COVER_PIXELS :: 128

// The lines of the header beside the cover well, as 1.0.0's column laid them out: each as
// high as its font's line, with 4 points between them and before the cover button, whose
// row has 4 more above it.
@(private = "file")
Header_Lines :: struct {
	title:  f32,
	album:  f32,
	note:   f32,
	height: f32,
}

@(private = "file")
header_lines :: proc(r: ^ui.Renderer, s: engine.Summary) -> (lines: Header_Lines) {
	lines.title = ui.line_height(r, .Title)
	lines.height = lines.title
	if album_and_artist(s) != "" {
		lines.album = ui.line_height(r, .Body)
		lines.height += 4 + lines.album
	}
	if s.unreadable > 0 {
		lines.note = ui.line_height(r, .Small)
		lines.height += 4 + lines.note
	}
	lines.height += 4 + 4 + 24
	return
}

// The height of the header: the well, or its lines when they are taller.
@(private = "file")
header_height :: proc(r: ^ui.Renderer, s: engine.Summary) -> f32 {
	return max(WELL, header_lines(r, s).height)
}

init_inspector :: proc(i: ^Inspector) {
	i.tags_open = true
	i.file_open = true
	i.tag_format_open = true
	i.frames_open = true
}

// The inspector: the tags of the selected tracks, their file, and the actions on
// them; an unreadable file explained; or an invitation to select tracks.
inspector :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	refresh_inspection(app)
	ui.fill_rect(ctx.renderer, rect, ctx.theme.surface_1)
	id := ui.widget_id("Inspector")
	ui.declare(ctx, {id = id, role = .Group, label = ui.tr("Inspector"), rect = rect})
	ui.push_parent(ctx, id)
	defer ui.pop_parent(ctx)
	switch inspection in app.inspector.inspection {
	case engine.Summary:
		inspect_tracks(ctx, app, rect, inspection)
	case engine.Unreadable_Track:
		drop_cover(ctx, app)
		forget_layout(app)
		inspect_unreadable(ctx, app, rect, inspection)
	case nil:
		drop_cover(ctx, app)
		forget_layout(app)
		nothing_selected(ctx, app, rect)
	}
}

// Makes the inspection again when a command ran or the library or the edits changed,
// since it walks the selection.
@(private = "file")
refresh_inspection :: proc(app: ^App) {
	e := &app.engine
	i := &app.inspector
	if !i.made || i.revision != e.revision || app.commands != i.commands do i.inspection = engine.inspect(e)
	i.made, i.revision, i.commands = true, e.revision, app.commands
}

@(private = "file")
nothing_selected :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	middle := rect.y + rect.h / 2
	centre := rect.x + rect.w / 2
	first := ui.tr("Select tracks to see their tags")
	second := ui.fill(ui.tr("{} selects every track"), shortcut_hint(app, "A"))
	w1 := ui.draw_text(r, first, centre, middle - 12, .Body, th.text_secondary, .Center)
	w2 := ui.draw_text(r, second, centre, middle + 10, .Small, th.text_tertiary, .Center)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Select tracks"),
			role = .Label,
			label = first,
			rect = {centre - w1 / 2, middle - 21, w1, 18},
		},
	)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Select all hint"),
			role = .Label,
			label = second,
			rect = {centre - w2 / 2, middle + 2, w2, 16},
		},
	)
}

// The selected tracks whose tags could be read: the cover and the heading, the tags,
// the file, and the actions.
@(private = "file")
inspect_tracks :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect, s: engine.Summary) {
	r := ctx.renderer
	th := ctx.theme
	e := &app.engine
	i := &app.inspector
	id := ui.widget_id("Inspector")
	body := ui.Rect{rect.x, rect.y, rect.w, rect.h - ACTIONS_HEIGHT}
	width := rect.w - 2 * INSPECTOR_PADDING

	// The content's height, for the scroll.
	height: f32 = 2 * INSPECTOR_PADDING + header_height(r, s) + SECTION_GAP + 16
	// The warnings under the Tags header, wrapped to the panel's width.
	notes := make([dynamic]string, context.temp_allocator)
	if lost := lost_names(s.id3v1_losses); lost != "" {
		append(&notes, ui.fill(ui.tr("ID3v1 will keep only part of: {}"), lost))
	}
	for warning in selection_warnings(app) do append(&notes, warning_text(warning, s.count))
	if i.tags_open {
		height += 8 + 8 * (ui.BUTTON_HEIGHT + FIELD_GAP) + COMMENT_HEIGHT
		for text in notes do height += warning_height(r, text, width)
	}
	height += SECTION_GAP + 16
	if i.file_open do height += 8 + f32(s.modified != {} ? 4 : 3) * 20
	conversion: []string
	if e.view.developer_mode {
		conversion = conversion_lines(r, s, width)
		height += SECTION_GAP + 16
		if i.tag_format_open {
			height +=
				8 +
				2 * (ui.BUTTON_HEIGHT + FIELD_GAP) +
				f32(len(conversion)) * ui.line_height(r, .Small)
			height += 8 + write_details(ctx, app, 0, 0, width, true)
		}
	}
	layout := shown_layout(app, s)
	if layout != nil {
		height += SECTION_GAP + 16
		if i.frames_open do height += 8 + frames_section(ctx, layout, 0, 0, width, true)
	}
	origin := ui.begin_scroll(ctx, id, body, {body.w, height}, &i.scroll)
	x := origin.x + INSPECTOR_PADDING
	y := origin.y + INSPECTOR_PADDING

	cover_well(ctx, app, s, {x, y, WELL, WELL})
	heading :=
		s.count == 1 ? s.heading.? or_else "" : ui.tr_n("{n} track selected", "{n} tracks selected", s.count)
	text_x := x + WELL + 12
	lines := header_lines(r, s)
	header := max(WELL, lines.height)
	ty := y + (header - lines.height) / 2
	ui.draw_text_fit(r, heading, text_x, ty + lines.title / 2, width - 76, .Title, th.text_primary)
	hw := min(ui.text_width(r, heading, .Title), width - 76)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Heading"),
			role = .Label,
			label = heading,
			rect = {text_x, ty, hw, lines.title},
		},
	)
	ty += lines.title + 4
	if line := album_and_artist(s); line != "" {
		ui.draw_text_fit(
			r,
			line,
			text_x,
			ty + lines.album / 2,
			width - 76,
			.Body,
			th.text_secondary,
		)
		lw := min(ui.text_width(r, line, .Body), width - 76)
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Album line"),
				role = .Label,
				label = line,
				rect = {text_x, ty, lw, lines.album},
			},
		)
		ty += lines.album + 4
	}
	if s.unreadable > 0 {
		note := ui.tr_n("{n} file could not be read", "{n} files could not be read", s.unreadable)
		ui.draw_text_fit(r, note, text_x, ty + lines.note / 2, width - 76, .Small, th.error)
		nw := min(ui.text_width(r, note, .Small), width - 76)
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Unreadable note"),
				role = .Label,
				label = note,
				rect = {text_x, ty, nw, lines.note},
			},
		)
		ty += lines.note + 4
	}
	replace_label := ui.tr("Replace cover…")
	replace_options := ui.Button_Options {
		kind = .Secondary,
	}
	replace_rect := ui.Rect{text_x, ty + 4, ui.button_width(r, replace_label, replace_options), 24}
	if ui.button(ctx, ui.widget_id("Replace cover"), replace_rect, replace_label, replace_options) do pick_image(app)
	y += header + SECTION_GAP

	if section_header(ctx, 0, ui.tr("Tags"), {x, y, width, 16}, &i.tags_open) {
		y += 16 + 8
		for text, index in notes do y += warning_row(ctx, text, x, y, width, index)
		y = tag_fields(ctx, app, s, x, y, width)
	} else {
		y += 16
	}
	y += SECTION_GAP
	if section_header(ctx, 1, ui.tr("File"), {x, y, width, 16}, &i.file_open) {
		y += 16 + 8
		file_row(ctx, ui.tr("Audio"), audio_text(s), x, y, width, false, 0)
		y += 20
		size := size_text(s.size)
		if s.count > 1 do size = ui.fill(ui.tr("{} total"), size)
		file_row(ctx, ui.tr("Size"), size, x, y, width, true, 1)
		y += 20
		file_row(ctx, ui.tr("Tags"), formats_text(s.formats), x, y, width, false, 2)
		y += 20
		if s.modified != {} {
			file_row(ctx, ui.tr("Saved as"), formats_text(s.saved_as), x, y, width, false, 3)
			y += 20
		}
	} else {
		y += 16
	}
	if e.view.developer_mode {
		y += SECTION_GAP
		if section_header(ctx, 2, ui.tr("Tag format"), {x, y, width, 16}, &i.tag_format_open) {
			y += 16 + 8
			y = tag_format(ctx, app, s, conversion, x, y, width)
		} else {
			y += 16
		}
	}
	if layout != nil {
		y += SECTION_GAP
		if section_header(ctx, 3, ui.tr("Frames"), {x, y, width, 16}, &i.frames_open) {
			y += 16 + 8
			frames_section(ctx, layout, x, y, width)
		}
	}
	ui.end_scroll(ctx, id, body, {body.w, height}, &i.scroll)

	// Pinned at the bottom, so that the actions never leave the screen.
	actions := ui.Rect{rect.x, rect.y + rect.h - ACTIONS_HEIGHT, rect.w, ACTIONS_HEIGHT}
	ui.fill_rect(r, {actions.x, actions.y, actions.w, 1}, th.border_subtle)
	saving := engine.saving(e) != nil
	pending := len(e.edits.pending)
	by := actions.y + 1 + 14
	save_label := saving ? ui.tr("Saving…") : ui.tr_n("Save {n} file", "Save {n} files", pending)
	save_options := ui.Button_Options {
		kind     = .Primary,
		disabled = !engine.can_save(e),
	}
	save_width := ui.button_width(r, save_label, save_options)
	save_rect := ui.Rect {
		actions.x + actions.w - INSPECTOR_PADDING - save_width,
		by,
		save_width,
		ui.BUTTON_HEIGHT,
	}
	if ui.button(ctx, ui.widget_id("Save files"), save_rect, save_label, save_options) do request_save(app)
	revert_label := ui.tr("Revert")
	revert_options := ui.Button_Options {
		kind     = .Secondary,
		disabled = !engine.can_revert(e) || saving,
	}
	revert_width := ui.button_width(r, revert_label, revert_options)
	revert_rect := ui.Rect{save_rect.x - 8 - revert_width, by, revert_width, ui.BUTTON_HEIGHT}
	if ui.button(ctx, ui.widget_id("Revert"), revert_rect, revert_label, revert_options) do execute(app, engine.Revert{})
}

// A line of a warning, and the room under its last line.
// The well: the cover the selected tracks share, its centre square, or the sign that
// they have none or several. A right click opens its menu. The cover is read, decoded
// and shrunk when the selection's cover changes, on the UI thread: see the plan's
// decision on covers.
@(private = "file")
cover_well :: proc(ctx: ^ui.Ui, app: ^App, s: engine.Summary, well: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	i := &app.inspector
	refresh_cover(ctx, app, s)
	id := ui.widget_id("Cover")
	interaction := ui.interact(ctx, id, well)
	if .Right_Clicked in interaction do ui.open_menu(ctx, ui.widget_id("Cover menu"), ctx.input.mouse)
	ui.fill_rect(r, well, th.surface_2, 6)
	label := ui.tr("No cover")
	drawn := false
	if shown, has := i.cover.?; has {
		if texture, made := shown.texture.?; made {
			ui.draw_image(r, texture, well, 6)
			drawn = true
		}
	}
	switch v in s.cover {
	case lib.Cover_Key:
		// Shared: the well is the cover's, empty while it cannot be drawn, as 1.0.0.
		label = ui.tr("Cover")
	case engine.Mixed:
		label = ui.tr("Several covers")
	case nil:
	}
	if _, shared := s.cover.(lib.Cover_Key); !shared && !drawn do ui.draw_icon_centered(r, .Music, well, th.text_tertiary, 24)
	ui.stroke_rect(r, well, .Cover in s.modified ? th.modified_border : th.border_subtle, 6)
	ui.declare(ctx, {id = id, role = .Image, label = label, rect = well})
	cover_menu(ctx, app, s)
}

// Makes the well's texture again when the cover the selection shares changed: from
// the bytes held for a cover waiting to be saved, else read from the first selected
// track's file, shrunk to the well's pixels. A cover that cannot be read or decoded
// is tried once.
@(private = "file")
refresh_cover :: proc(ctx: ^ui.Ui, app: ^App, s: engine.Summary) {
	i := &app.inspector
	key, shared := s.cover.(lib.Cover_Key)
	track, has_track := s.cover_track.?
	if !shared || !has_track {
		drop_cover(ctx, app)
		return
	}
	if shown, has := i.cover.?; has && shown.key == key do return
	drop_cover(ctx, app)
	i.cover = Shown_Cover{key, nil}
	e := &app.engine
	tags, readable := engine.shown_tags(e, track)
	if !readable do return
	bytes: []u8
	switch cover in tags.cover {
	case lib.Cover:
		bytes = cover.data
	case lib.Own_Cover:
		read, found := lib.read_cover(e.library.tracks[track].path, context.temp_allocator)
		if !found do return
		bytes = read.data
	case nil:
		return
	}
	rgba, w, h, decoded := ui.decode_image(bytes, context.temp_allocator)
	if !decoded do return
	small, shrunk := ui.shrink_image(rgba, w, h, COVER_PIXELS, context.temp_allocator)
	if !shrunk do return
	texture, made := ui.create_image(ctx, small, COVER_PIXELS, COVER_PIXELS)
	if !made do return
	i.cover = Shown_Cover{key, texture}
}

@(private = "file")
drop_cover :: proc(ctx: ^ui.Ui, app: ^App) {
	if shown, has := app.inspector.cover.?; has {
		if texture, made := shown.texture.?; made do ui.destroy_image(ctx, texture)
	}
	app.inspector.cover = nil
}

// The well's menu: replace the cover, write it to a file, or remove it.
@(private = "file")
cover_menu :: proc(ctx: ^ui.Ui, app: ^App, s: engine.Summary) {
	id := ui.widget_id("Cover menu")
	if !ui.is_menu_open(ctx, id) do return
	_, shared := s.cover.(lib.Cover_Key)
	items := [?]ui.Menu_Item {
		{label = ui.tr("Replace Cover…")},
		{label = ui.tr("Extract Cover…"), disabled = !shared},
		{label = ui.tr("Remove Cover"), disabled = s.cover == nil},
	}
	chosen, picked := ui.menu(ctx, id, items[:], ui.tr("Cover menu")).?
	if !picked do return
	switch chosen {
	case 0:
		pick_image(app)
	case 1:
		extract_cover(app)
	case 2:
		execute(app, engine.Apply_Edit{{.Cover, nil}})
	}
}

@(private = "file")
WARNING_GAP :: 6

// What a warning says of the selected tracks, as 1.0.0 worded it.
@(private = "file")
warning_text :: proc(warning: engine.Warning, count: int) -> string {
	switch warning {
	case .Missing_Number:
		if count == 1 do return ui.tr("This track has no number, unlike the rest of its album.")
		return ui.tr("Some of these tracks have no number, unlike the rest of their albums.")
	case .Odd_Album_Artist:
		if count == 1 do return ui.tr("Its album artist differs from the rest of its album.")
		return ui.tr(
			"Some of these tracks have an album artist that differs from the rest of their albums.",
		)
	}
	return ""
}

// A warning under the Tags header, wrapped to the width: what saving would lose, a
// track unlike the rest of its album. Gives its height.
@(private = "file")
warning_row :: proc(ctx: ^ui.Ui, text: string, x, y, width: f32, index: int) -> (height: f32) {
	r := ctx.renderer
	th := ctx.theme
	lines := ui.wrap_text(r, text, .Small, width - 20, context.temp_allocator)
	height = f32(max(len(lines), 1)) * ui.line_height(r, .Small) + WARNING_GAP
	ui.draw_icon(r, .Triangle_Alert, {x, y + 1, 14, 14}, th.warning)
	for line, i in lines {
		ui.draw_text(
			r,
			line,
			x + 20,
			y + f32(i) * ui.line_height(r, .Small) + ui.line_height(r, .Small) / 2,
			.Small,
			th.warning,
		)
	}
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Inspector warning", index),
			role = .Label,
			label = text,
			rect = {x, y, width, height},
		},
	)
	return
}

// The height a warning takes, wrapped to the width: what warning_row gives, for the
// scroll's content before the rows are drawn.
@(private = "file")
warning_height :: proc(r: ^ui.Renderer, text: string, width: f32) -> f32 {
	lines := ui.wrap_text(r, text, .Small, width - 20, context.temp_allocator)
	return f32(max(len(lines), 1)) * ui.line_height(r, .Small) + WARNING_GAP
}

// The fields an ID3v1 tag would keep only part of, named in 1.0.0's order and joined
// with commas; empty when none. Allocated with the temporary allocator.
@(private = "file")
lost_names :: proc(losses: lib.Id3v1_Losses) -> string {
	order := [?]lib.Id3v1_Loss{.Title, .Artist, .Album, .Year, .Comment, .Track, .Genre}
	names := make([dynamic]string, context.temp_allocator)
	for loss in order do if loss in losses do append(&names, loss_name(loss))
	return strings.join(names[:], ", ", context.temp_allocator)
}

@(private = "file")
loss_name :: proc(loss: lib.Id3v1_Loss) -> string {
	switch loss {
	case .Title:
		return ui.tr("Title")
	case .Artist:
		return ui.tr("Artist")
	case .Album:
		return ui.tr("Album")
	case .Year:
		return ui.tr("Year")
	case .Comment:
		return ui.tr("Comment")
	case .Track:
		return ui.tr("Track")
	case .Genre:
		return ui.tr("Genre")
	}
	return ""
}

// A section's title, the index-th of the panel, which hides the section or shows it
// again. True while shown.
@(private = "file")
section_header :: proc(
	ctx: ^ui.Ui,
	index: int,
	title: string,
	rect: ui.Rect,
	open: ^bool,
) -> bool {
	r := ctx.renderer
	th := ctx.theme
	id := ui.widget_id("Section header", index)
	interaction := ui.interact(ctx, id, rect)
	if .Hovered in interaction do ctx.cursor = .Pointer
	if .Clicked in interaction do open^ = !open^
	color := .Hovered in interaction ? th.text_secondary : th.text_tertiary
	ui.draw_icon(r, open^ ? .Chevron_Down : .Chevron_Right, {rect.x, rect.y + 2, 12, 12}, color)
	ui.draw_text(r, title, rect.x + 16, rect.y + rect.h / 2, .Label, color)
	states: ui.Widget_States = open^ ? {.Expanded} : {}
	ui.declare(ctx, {id = id, role = .Button, label = title, rect = rect, states = states})
	return open^
}

// What a field reported this frame, taken in once every row is drawn.
@(private = "file")
Taken :: struct {
	field:  engine.Field,
	result: ui.Text_Field_Result,
}

// The fields of the tags, label and value, in the order of the mockup. Gives the y
// after them. The commands run once every row is drawn: the summary's strings last
// until the next command, and the rows read them.
@(private = "file")
tag_fields :: proc(ctx: ^ui.Ui, app: ^App, s: engine.Summary, x, y, width: f32) -> f32 {
	y := y
	field_x := x + FIELD_LABEL_WIDTH + 8
	field_w := width - FIELD_LABEL_WIDTH - 8
	taken := make([dynamic]Taken, context.temp_allocator)
	defer for t in taken do take_field(app, t.field, t.result)
	text_row :: proc(
		ctx: ^ui.Ui,
		taken: ^[dynamic]Taken,
		s: engine.Summary,
		field: engine.Field,
		name: string,
		shared: engine.Shared(string),
		x, y, field_x, field_w: f32,
	) {
		field_label(ctx, name, {x, y, FIELD_LABEL_WIDTH, ui.BUTTON_HEIGHT}, field in s.modified)
		value, options := field_options(shared, field in s.modified)
		result := ui.text_field(
			ctx,
			ui.widget_id(name),
			{field_x, y, field_w, ui.BUTTON_HEIGHT},
			value,
			name,
			options,
		)
		append(taken, Taken{field, result})
	}
	text_row(ctx, &taken, s, .Title, ui.tr("Title"), s.title, x, y, field_x, field_w)
	y += ui.BUTTON_HEIGHT + FIELD_GAP
	text_row(ctx, &taken, s, .Artist, ui.tr("Artist"), s.artist, x, y, field_x, field_w)
	y += ui.BUTTON_HEIGHT + FIELD_GAP
	text_row(
		ctx,
		&taken,
		s,
		.Album_Artist,
		ui.tr("Album artist"),
		s.album_artist,
		x,
		y,
		field_x,
		field_w,
	)
	y += ui.BUTTON_HEIGHT + FIELD_GAP
	text_row(ctx, &taken, s, .Album, ui.tr("Album"), s.album, x, y, field_x, field_w)
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	year_name := ui.tr("Year")
	field_label(ctx, year_name, {x, y, FIELD_LABEL_WIDTH, ui.BUTTON_HEIGHT}, .Year in s.modified)
	year_value, year_options := number_options(s.year, .Year in s.modified, .Year)
	year := ui.text_field(
		ctx,
		ui.widget_id(year_name),
		{field_x, y, field_w, ui.BUTTON_HEIGHT},
		year_value,
		year_name,
		year_options,
	)
	append(&taken, Taken{.Year, year})
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	number_row :: proc(
		ctx: ^ui.Ui,
		taken: ^[dynamic]Taken,
		s: engine.Summary,
		name: string,
		fields: [2]engine.Field,
		labels: [2]string,
		shared: [2]engine.Shared(int),
		x, y, field_x: f32,
	) {
		modified := fields[0] in s.modified || fields[1] in s.modified
		field_label(ctx, name, {x, y, FIELD_LABEL_WIDTH, ui.BUTTON_HEIGHT}, modified)
		values: [2]string
		options: [2]ui.Text_Field_Options
		values[0], options[0] = number_options(shared[0], fields[0] in s.modified, fields[0])
		values[1], options[1] = number_options(shared[1], fields[1] in s.modified, fields[1])
		// The pair says the tracks differ in fewer letters than a field would.
		if .Multiple_Values in options[0].flags do options[0].placeholder = ui.tr("Multiple")
		if .Multiple_Values in options[1].flags do options[1].placeholder = "…"
		number, total := ui.number_pair(
			ctx,
			ui.widget_id(name),
			{field_x, y},
			values[0],
			values[1],
			labels,
			ui.tr("of"),
			options,
		)
		append(taken, Taken{fields[0], number})
		append(taken, Taken{fields[1], total})
	}
	number_row(
		ctx,
		&taken,
		s,
		ui.tr("Track"),
		{.Track, .Track_Total},
		{ui.tr("Track"), ui.tr("Track total")},
		{s.track, s.track_total},
		x,
		y,
		field_x,
	)
	y += ui.BUTTON_HEIGHT + FIELD_GAP
	number_row(
		ctx,
		&taken,
		s,
		ui.tr("Disc"),
		{.Disc, .Disc_Total},
		{ui.tr("Disc"), ui.tr("Disc total")},
		{s.disc, s.disc_total},
		x,
		y,
		field_x,
	)
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	genre_name := ui.tr("Genre")
	field_label(ctx, genre_name, {x, y, FIELD_LABEL_WIDTH, ui.BUTTON_HEIGHT}, .Genre in s.modified)
	genre_value, genre_options := field_options(s.genre, .Genre in s.modified)
	genre := ui.combo_box(
		ctx,
		ui.widget_id(genre_name),
		{field_x, y, field_w, ui.BUTTON_HEIGHT},
		genre_value,
		genre_name,
		genres(app),
		genre_options,
	)
	append(&taken, Taken{.Genre, genre})
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	comment_name := ui.tr("Comment")
	field_label(
		ctx,
		comment_name,
		{x, y, FIELD_LABEL_WIDTH, ui.BUTTON_HEIGHT},
		.Comment in s.modified,
	)
	comment_value, comment_options := field_options(s.comment, .Comment in s.modified)
	comment := ui.text_area(
		ctx,
		ui.widget_id(comment_name),
		{field_x, y, field_w, COMMENT_HEIGHT},
		comment_value,
		comment_name,
		&app.inspector.comment_scroll,
		comment_options,
	)
	append(&taken, Taken{.Comment, comment})
	return y + COMMENT_HEIGHT
}

// A field's label: a dot takes the place of the padding while the field waits to be
// saved.
@(private)
field_label :: proc(ctx: ^ui.Ui, text: string, rect: ui.Rect, modified: bool) {
	r := ctx.renderer
	th := ctx.theme
	middle := rect.y + rect.h / 2
	x := rect.x + 12
	if modified do ui.fill_rect(r, {rect.x, middle - 3, 6, 6}, th.accent, 3)
	ui.draw_text_fit(
		r,
		text,
		x,
		middle,
		rect.w - 12,
		.Body,
		modified ? th.text_primary : th.text_secondary,
	)
}

// A row of the File section: a name and a value that is not edited.
@(private = "file")
file_row :: proc(ctx: ^ui.Ui, name, value: string, x, y, width: f32, mono: bool, index: int) {
	r := ctx.renderer
	th := ctx.theme
	middle := y + 10
	ui.draw_text(r, name, x + 12, middle, .Small, th.text_secondary)
	style: ui.Text_Style = mono ? .Numeric : .Small
	vx := x + FIELD_LABEL_WIDTH + 8
	ui.draw_text_fit(r, value, vx, middle, width - FIELD_LABEL_WIDTH - 8, style, th.text_primary)
	vw := min(ui.text_width(r, value, style), width - FIELD_LABEL_WIDTH - 8)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("File value", index),
			role = .Label,
			label = value,
			rect = {vx, y, vw, 20},
		},
	)
}

// What a text field shows of a shared value: the value, or the placeholder that says
// the tracks differ.
@(private = "file")
field_options :: proc(
	shared: engine.Shared(string),
	modified: bool,
) -> (
	value: string,
	options: ui.Text_Field_Options,
) {
	switch v in shared {
	case string:
		value = v
	case engine.Mixed:
		options.flags += {.Multiple_Values}
		options.placeholder = ui.tr("Multiple values")
	case nil:
	}
	if modified do options.flags += {.Modified}
	return
}

// The same for a number: its digits. Allocated with the temporary allocator.
@(private = "file")
number_options :: proc(
	shared: engine.Shared(int),
	modified: bool,
	field: engine.Field,
) -> (
	value: string,
	options: ui.Text_Field_Options,
) {
	switch v in shared {
	case int:
		value = fmt.tprint(v)
	case engine.Mixed:
		options.flags += {.Multiple_Values}
		options.placeholder = ui.tr("Multiple values")
	case nil:
	}
	if modified do options.flags += {.Modified}
	options.flags += {.Numeric}
	options.accepts = accepts_of(field)
	return
}

// Takes in what a field reported: each change at once, so that saving never misses
// what was just typed, the typing of one field making one step of the history; Escape
// takes the whole of it back.
@(private = "file")
take_field :: proc(app: ^App, field: engine.Field, result: ui.Text_Field_Result) {
	i := &app.inspector
	if result.changed {
		edit, fits := edit_of(field, result.text)
		if fits {
			if i.typing == field {
				execute(app, engine.Continue_Edit{edit})
			} else {
				execute(app, engine.Apply_Edit{edit})
				i.typing = field
			}
		}
	}
	if result.committed do i.typing = nil
	if result.cancelled {
		if i.typing == field do execute(app, engine.Undo{})
		i.typing = nil
	}
}

// The edit a field's text makes: text for the text fields, a number for the number
// fields, empty text emptying either. fits is false when the text is not a value the
// field takes, such as letters in a year.
@(private)
edit_of :: proc(field: engine.Field, text: string) -> (edit: engine.Edit, fits: bool) {
	edit.field = field
	#partial switch field {
	case .Year, .Track, .Track_Total, .Disc, .Disc_Total:
		if len(text) == 0 do return edit, true
		// Digits only: parse_int would take a sign and underscores.
		for c in text do if c < '0' || c > '9' do return edit, false
		number, ok := strconv.parse_int(text, 10)
		if !ok || number < 1 do return edit, false
		if field == .Year && number > 9999 do return edit, false
		edit.value = number
		return edit, true
	}
	edit.value = text
	return edit, true
}

// Whether a text is a value a field takes, for the number fields, which refuse some:
// the fields and the cells show what is wrong rather than taking it in.
@(private)
accepts_of :: proc(field: engine.Field) -> proc(text: string) -> bool {
	#partial switch field {
	case .Year:
		return proc(text: string) -> bool {
				_, fits := edit_of(.Year, text)
				return fits
			}
	case .Track, .Track_Total, .Disc, .Disc_Total:
		return proc(text: string) -> bool {
				_, fits := edit_of(.Track, text)
				return fits
			}
	}
	return nil
}

// The album and the artist the selected tracks share, with a dot between them when
// both are there. Allocated with the temporary allocator.
@(private)
album_and_artist :: proc(s: engine.Summary) -> string {
	album, has_album := s.album.(string)
	artist, has_artist := s.artist.(string)
	switch {
	case has_album && has_artist:
		return fmt.tprintf("%s · %s", album, artist)
	case has_album:
		return album
	case has_artist:
		return artist
	}
	return ""
}

// The audio line: the format, the bitrate with its mode, the sample rate, or that the
// tracks differ. Allocated with the temporary allocator.
@(private)
audio_text :: proc(s: engine.Summary) -> string {
	audio, same := s.audio.(engine.Audio_Line)
	if !same do return ui.tr("Multiple values")
	mode := ""
	switch audio.mode {
	case .Constant:
		mode = NBSP + "CBR"
	case .Variable:
		mode = NBSP + "VBR"
	}
	// Tenths of kilohertz, rounded: 44100 Hz reads 44.1 kHz, 22050 Hz 22.1 kHz.
	tenths := (audio.sample_rate + 50) / 100
	rate: string
	if tenths % 10 == 0 {
		rate = ui.fill(ui.tr("{}\u00A0kHz"), fmt.tprint(tenths / 10))
	} else {
		rate = ui.fill(ui.tr("{}.{}\u00A0kHz"), fmt.tprint(tenths / 10), fmt.tprint(tenths % 10))
	}
	bitrate := ui.fill(ui.tr("{}\u00A0kbps"), fmt.tprint(audio.bitrate_kbps))
	return fmt.tprintf("MP3 · %s%s · %s", bitrate, mode, rate)
}

// A size as people read it: bytes, then whole kilobytes, then megabytes and gigabytes
// to a tenth. Allocated with the temporary allocator.
@(private)
size_text :: proc(bytes: i64) -> string {
	switch {
	case bytes < 1_000:
		return ui.tr_n("{n}\u00A0byte", "{n}\u00A0bytes", int(bytes))
	case bytes < 1_000_000:
		return ui.fill(ui.tr("{}\u00A0KB"), fmt.tprint((bytes + 500) / 1_000))
	case bytes < 1_000_000_000:
		tenths := (bytes + 50_000) / 100_000
		return ui.fill(ui.tr("{}.{}\u00A0MB"), fmt.tprint(tenths / 10), fmt.tprint(tenths % 10))
	}
	tenths := (bytes + 50_000_000) / 100_000_000
	return ui.fill(ui.tr("{}.{}\u00A0GB"), fmt.tprint(tenths / 10), fmt.tprint(tenths % 10))
}

// The Tag format section of developer mode: the versions saving writes the selected
// tracks in, ID3v2 and ID3v1, each with None, and what saving converts.
@(private = "file")
tag_format :: proc(
	ctx: ^ui.Ui,
	app: ^App,
	s: engine.Summary,
	conversion: []string,
	x, top, width: f32,
) -> (
	bottom: f32,
) {
	th := ctx.theme
	y := top
	field_x := x + FIELD_LABEL_WIDTH + 8
	field_w := width - FIELD_LABEL_WIDTH - 8
	versions, shared := s.versions.(lib.Tag_Versions)
	v2, v1: Maybe(int)
	if shared {
		v2 = versions.id3v2 == nil ? 0 : int(versions.id3v2.?) + 1
		v1 = versions.id3v1 == nil ? 0 : int(versions.id3v1.?) + 1
	}
	v2_segments := id3v2_segments()
	if chosen, picked := version_row(
		   ctx,
		   ui.tr("Write ID3v2"),
		   {x, y},
		   field_x,
		   field_w,
		   v2_segments[:],
		   v2,
	   ).?; picked {
		request_version(
			app,
			engine.Id3v2_Choice{chosen == 0 ? nil : lib.Id3v2_Version(chosen - 1)},
		)
	}
	y += ui.BUTTON_HEIGHT + FIELD_GAP
	v1_segments := id3v1_segments()
	if chosen, picked := version_row(
		   ctx,
		   ui.tr("Write ID3v1"),
		   {x, y},
		   field_x,
		   field_w,
		   v1_segments[:],
		   v1,
	   ).?; picked {
		request_version(
			app,
			engine.Id3v1_Choice{chosen == 0 ? nil : lib.Id3v1_Version(chosen - 1)},
		)
	}
	y += ui.BUTTON_HEIGHT + FIELD_GAP
	if len(conversion) > 0 {
		for line, i in conversion {
			ui.draw_text(
				ctx.renderer,
				line,
				field_x,
				y +
				f32(i) * ui.line_height(ctx.renderer, .Small) +
				ui.line_height(ctx.renderer, .Small) / 2,
				.Small,
				th.text_tertiary,
			)
		}
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Conversion"),
				role = .Label,
				label = conversion_text(s),
				rect = {
					field_x,
					y,
					field_w,
					f32(len(conversion)) * ui.line_height(ctx.renderer, .Small),
				},
			},
		)
	}
	y += f32(len(conversion)) * ui.line_height(ctx.renderer, .Small) + 8
	return y + write_details(ctx, app, x, y, width)
}

// None, then each version, named by its tag's way of writing it: 2.4, 1.1.
@(private = "file")
id3v2_segments :: proc() -> [1 + len(lib.Id3v2_Version)]ui.Segment {
	segments: [1 + len(lib.Id3v2_Version)]ui.Segment
	segments[0] = {
		label = ui.tr("None"),
	}
	for version, i in lib.Id3v2_Version do segments[i + 1] = {
		label   = version_name(version),
		numeric = true,
	}
	return segments
}

@(private = "file")
id3v1_segments :: proc() -> [1 + len(lib.Id3v1_Version)]ui.Segment {
	segments: [1 + len(lib.Id3v1_Version)]ui.Segment
	segments[0] = {
		label = ui.tr("None"),
	}
	for version, i in lib.Id3v1_Version do segments[i + 1] = {
		label   = version_name(version),
		numeric = true,
	}
	return segments
}

@(private = "file")
version_name :: proc(version: $V) -> string {
	when V == lib.Id3v2_Version {
		switch version {
		case .V2_2:
			return "2.2"
		case .V2_3:
			return "2.3"
		case .V2_4:
			return "2.4"
		}
	} else {
		switch version {
		case .V1_0:
			return "1.0"
		case .V1_1:
			return "1.1"
		}
	}
	return ""
}

// A label and the segments that choose a version, gives the one chosen.
@(private = "file")
version_row :: proc(
	ctx: ^ui.Ui,
	name: string,
	at: [2]f32,
	field_x, field_w: f32,
	segments: []ui.Segment,
	selected: Maybe(int),
) -> Maybe(int) {
	field_label(ctx, name, {at.x, at.y, FIELD_LABEL_WIDTH, ui.BUTTON_HEIGHT}, false)
	return ui.segmented(
		ctx,
		ui.widget_id(name),
		{field_x, at.y, field_w, ui.BUTTON_HEIGHT},
		name,
		segments,
		selected,
	)
}

// The lines the conversion text takes, wrapped to the section's field.
@(private = "file")
conversion_lines :: proc(r: ^ui.Renderer, s: engine.Summary, width: f32) -> []string {
	text := conversion_text(s)
	if text == "" do return nil
	return ui.wrap_text(r, text, .Small, width - FIELD_LABEL_WIDTH - 8, context.temp_allocator)
}

// What saving does to the tags of the files it converts, as 1.0.0 said it. Allocated
// with the temporary allocator.
@(private)
conversion_text :: proc(s: engine.Summary) -> string {
	if s.converted == 0 do return ""
	_, saved_mixed := s.saved_as.(engine.Mixed)
	saved, has_saved := s.saved_as.(lib.Tag_Formats)
	if saved_mixed {
		return ui.tr_n("Saving converts {n} file.", "Saving converts {n} files.", s.converted)
	}
	saved_text := has_saved ? lib.tag_formats_string(saved, context.temp_allocator) : ""
	if saved_text == "" {
		return ui.tr_n(
			"Saving removes the tags of {n} file.",
			"Saving removes the tags of {n} files.",
			s.converted,
		)
	}
	before, same := s.formats.(lib.Tag_Formats)
	before_text := same ? lib.tag_formats_string(before, context.temp_allocator) : ""
	if !same || before_text == "" {
		return ui.fill(
			ui.tr_n(
				"Saving converts {n} file to {}.",
				"Saving converts {n} files to {}.",
				s.converted,
			),
			saved_text,
		)
	}
	return ui.fill(
		ui.tr_n(
			"Saving converts {n} file from {} to {}.",
			"Saving converts {n} files from {} to {}.",
			s.converted,
		),
		before_text,
		saved_text,
	)
}

// The tag formats the tracks share, or that they differ, or that they have none.
@(private = "file")
formats_text :: proc(shared: engine.Shared(lib.Tag_Formats)) -> string {
	switch v in shared {
	case lib.Tag_Formats:
		text := lib.tag_formats_string(v, context.temp_allocator)
		return len(text) > 0 ? text : ui.tr("None")
	case engine.Mixed:
		return ui.tr("Multiple values")
	case nil:
	}
	return ui.tr("None")
}

// One selected track whose tags could not be read: what went wrong, and what to do.
@(private = "file")
inspect_unreadable :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect, u: engine.Unreadable_Track) {
	r := ctx.renderer
	th := ctx.theme
	track := &app.engine.library.tracks[u.track]
	x := rect.x + INSPECTOR_PADDING
	y := rect.y + INSPECTOR_PADDING
	width := rect.w - 2 * INSPECTOR_PADDING
	ui.draw_icon(r, .Circle_Alert, {x, y + 2, 16, 16}, th.error)
	title := ui.tr("Could not read this file")
	tw := ui.draw_text(r, title, x + 24, y + 10, .Title, th.text_primary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Unreadable title"),
			role = .Label,
			label = title,
			rect = {x + 24, y, tw, 20},
		},
	)
	y += 20 + 6
	path := display_folder(track.path, app.home)
	for line in ui.wrap_text(r, path, .Numeric, width, context.temp_allocator) {
		ui.draw_text(r, line, x, y + 8, .Numeric, th.text_secondary)
		y += 16
	}
	y += SECTION_GAP

	ui.draw_text(r, ui.tr("Problem"), x, y + 8, .Label, th.text_tertiary)
	y += 16 + 6
	problem: string
	switch u.error {
	case .Cannot_Open:
		problem = ui.tr(
			"Colophon could not open this file. It may have been moved or deleted, or Colophon may not be allowed to read it.",
		)
	case .Damaged, .None:
		problem = ui.tr(
			"This file is damaged, or it is not an MP3: Colophon could not make sense of it.",
		)
	}
	lines := ui.wrap_text(r, problem, .Body, width, context.temp_allocator)
	for line in lines {
		ui.draw_text(r, line, x, y + 9, .Body, th.text_primary)
		y += 18
	}
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Problem"),
			role = .Label,
			label = problem,
			rect = {x, y - f32(len(lines)) * 18, width, f32(len(lines)) * 18},
		},
	)
	y += SECTION_GAP

	ui.draw_text(r, ui.tr("Details"), x, y + 8, .Label, th.text_tertiary)
	y += 16 + 6
	size := size_text(track.size)
	ui.draw_text(r, ui.tr("File size"), x, y + 10, .Small, th.text_secondary)
	sw := ui.draw_text(r, size, x + FIELD_LABEL_WIDTH + 8, y + 10, .Numeric, th.text_primary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("File size"),
			role = .Label,
			label = size,
			rect = {x + FIELD_LABEL_WIDTH + 8, y, sw, 20},
		},
	)
	y += 20 + SECTION_GAP

	reveal_label: string
	switch app.platform {
	case .Mac:
		reveal_label = ui.tr("Show in Finder")
	case .Windows:
		reveal_label = ui.tr("Show in Explorer")
	case .Linux:
		reveal_label = ui.tr("Show in Folder")
	}
	options := ui.Button_Options {
		kind = .Secondary,
	}
	rw := ui.button_width(r, reveal_label, options)
	if ui.button(ctx, ui.widget_id("Reveal"), {x, y, rw, ui.BUTTON_HEIGHT}, reveal_label, options) do reveal_file(app, track.path)
	copy_label := ui.tr("Copy details")
	cw := ui.button_width(r, copy_label, options)
	if ui.button(
		ctx,
		ui.widget_id("Copy details"),
		{x + rw + 8, y, cw, ui.BUTTON_HEIGHT},
		copy_label,
		options,
	) {
		copy_details(ctx, track, u.error)
	}
}

// Puts what is known of an unreadable file on the clipboard, for a bug report.
@(private = "file")
copy_details :: proc(ctx: ^ui.Ui, track: ^lib.Track, error: lib.Read_Error) {
	if ctx.clipboard.set == nil do return
	details := fmt.tprintf(
		"File: %s\nSize: %d bytes\nError: %s\nColophon %s",
		track.path,
		track.size,
		error_sentence(error),
		VERSION,
	)
	ctx.clipboard.set(ctx.clipboard.data, details)
}

// What went wrong, for a bug report: in English, as the report travels.
@(private = "file")
error_sentence :: proc(error: lib.Read_Error) -> string {
	switch error {
	case .None:
		return "None"
	case .Cannot_Open:
		return "The file could not be opened"
	case .Damaged:
		return "The file holds no MPEG audio Colophon can read, or an ID3v2 header it can use"
	}
	return ""
}
