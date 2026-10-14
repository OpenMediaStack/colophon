package main

import "core:strings"

import "../engine"
import lib "../library"
import ui "../ui"

@(private = "file")
PALETTE_WIDTH :: 600
@(private = "file")
PALETTE_TOP :: 74
@(private = "file")
PALETTE_ROW :: 32
// How many commands show at once; the rest scroll.
@(private = "file")
PALETTE_ROWS :: 9

// The command palette: every command by name, narrowed by what is typed, the arrow
// keys moving in the list, Enter running the highlighted command, Escape closing.
Palette :: struct {
	open:     bool,
	// What is typed, kept between frames, allocated with the engine's allocator and
	// freed by open_palette and app_destroy.
	query:    string,
	current:  int,
	scroll:   ui.Scroll,
	// The row the list was last scrolled to show, so that it scrolls when the highlight
	// moves and the wheel is free the rest of the time.
	revealed: int,
}

// A command of the palette, listed while it can run: an engine command, or what the
// app does on its own.
@(private)
Entry :: struct {
	label:    string,
	category: string,
	enabled:  bool,
	command:  engine.Command,
	special:  Special,
}

@(private)
Special :: enum u8 {
	None,
	Open_Folder,
	Open_Files,
	Find,
}

// An entry that holds what is typed, cut around where it first does.
@(private)
Match :: struct {
	entry:      Entry,
	start, end: int,
}

// Opens the palette over the window, with an empty query.
open_palette :: proc(app: ^App) {
	p := &app.palette
	p.open = true
	p.current = 0
	p.revealed = 0
	p.scroll = {}
	delete(p.query, app.engine.allocator)
	p.query = ""
}

// Closes the palette; what was typed goes with it.
@(private = "file")
close_palette :: proc(app: ^App) {
	app.palette.open = false
}

// The palette over the window, while open.
palette :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	p := &app.palette
	if !p.open do return
	r := ctx.renderer
	th := ctx.theme
	// Not the toolbar button's id, which is named the same.
	id := ui.widget_id("Palette")
	ui.begin_modal(ctx, id, window)
	defer ui.end_modal(ctx)
	entries := palette_entries(app)
	found := matches(entries, p.query)
	p.current = clamp(p.current, 0, max(len(found) - 1, 0))
	shown := min(len(found), PALETTE_ROWS)
	width := min(PALETTE_WIDTH, window.w - 32)
	height: f32 = 44 + 1 + 6 + 26 + f32(shown) * PALETTE_ROW + 6 + 1 + 30
	box := ui.Rect{window.x + (window.w - width) / 2, window.y + PALETTE_TOP, width, height}
	// A click beside the box closes the palette; one inside it, between the rows, stays
	// there: the box claims the hover after the scrim, and the widgets drawn after it
	// take their own clicks.
	if .Clicked in ui.interact(ctx, ui.child_id(id, "scrim"), window) do close_palette(app)
	ui.interact(ctx, ui.child_id(id, "box"), box)
	ui.draw_shadow(r, box, 8, 16, 48, th.shadow_dialog)
	ui.fill_rect(r, box, th.surface_2, 8)
	ui.stroke_rect(r, box, th.border_strong, 8)
	ui.declare(ctx, {id = id, role = .Group, label = ui.tr("Command palette"), rect = box})
	ui.push_parent(ctx, id)
	defer ui.pop_parent(ctx)

	// The field, with the search sign before it and the key that closes after. It keeps
	// the focus whatever is clicked, and the keys that move and run are taken before it,
	// since a field moves its caret with the arrows and commits on Enter.
	field_id := ui.child_id(id, "query")
	if !ui.has_focus(ctx, field_id) do ui.request_focus(ctx, field_id)
	enter := ui.take_key(ctx, .Enter)
	down := ui.take_key(ctx, .Down, repeats = true)
	up := ui.take_key(ctx, .Up, repeats = true)
	ui.draw_icon(r, .Search, {box.x + 14, box.y + 14, 16, 16}, th.text_tertiary)
	esc := "esc"
	esc_width := ui.text_width(r, esc, .Small) + 12
	esc_box := ui.Rect{box.x + box.w - 14 - esc_width, box.y + 13, esc_width, 18}
	ui.stroke_rect(r, esc_box, th.border_strong, 3)
	ui.draw_text(r, esc, esc_box.x + 6, esc_box.y + 9, .Small, th.text_secondary)
	field_rect := ui.Rect{box.x + 40, box.y + 8, esc_box.x - 10 - (box.x + 40), 28}
	result := ui.text_field(
		ctx,
		field_id,
		field_rect,
		p.query,
		ui.tr("Command"),
		{placeholder = ui.tr("Type a command")},
	)
	if result.changed {
		delete(p.query, app.engine.allocator)
		p.query = strings.clone(result.text, app.engine.allocator)
		p.current = 0
		p.revealed = 0
		p.scroll = {}
		found = matches(entries, p.query)
		shown = min(len(found), PALETTE_ROWS)
		// The box's height follows the new list: a frame at once, not at the caret's blink.
		ui.wake_at(ctx, ctx.input.time)
	}
	if down do p.current = min(p.current + 1, max(len(found) - 1, 0))
	if up do p.current = max(p.current - 1, 0)
	if enter && p.current < len(found) {
		run_entry(ctx, app, found[p.current].entry)
		close_palette(app)
	}
	if result.cancelled || ui.take_key(ctx, .Escape) do close_palette(app)
	ui.fill_rect(r, {box.x, box.y + 44, box.w, 1}, th.border_subtle)

	// The commands found, or that none holds what is typed.
	y := box.y + 45 + 6
	if len(found) > 0 {
		ui.draw_text(r, ui.tr("Commands"), box.x + 14, y + 13, .Label, th.text_tertiary)
	} else {
		none := ui.fill(ui.tr("No command holds “{}”"), p.query)
		ui.draw_text(r, none, box.x + 14, y + 13, .Body, th.text_tertiary)
		ui.declare(
			ctx,
			{
				id = ui.child_id(id, "none"),
				role = .Label,
				label = none,
				rect = {box.x + 14, y, box.w - 28, 26},
			},
		)
	}
	y += 26
	list := ui.Rect{box.x + 6, y, box.w - 12, f32(shown) * PALETTE_ROW}
	content := [2]f32{list.w, f32(len(found)) * PALETTE_ROW}
	if p.revealed != p.current {
		ui.scroll_into_view(&p.scroll, f32(p.current) * PALETTE_ROW, PALETTE_ROW, list.h)
		p.revealed = p.current
	}
	origin := ui.begin_scroll(ctx, ui.child_id(id, "list"), list, content, &p.scroll)
	for m, i in found {
		row := ui.Rect{origin.x, origin.y + f32(i) * PALETTE_ROW, list.w, PALETTE_ROW}
		row_id := ui.child_id(id, "command", i)
		interaction := ui.interact(ctx, row_id, row)
		if .Hovered in interaction do ctx.cursor = .Pointer
		switch {
		case i == p.current:
			ui.fill_rect(r, row, th.accent_selection, 4)
		case .Hovered in interaction:
			ui.fill_rect(r, row, th.surface_3, 4)
		}
		middle := row.y + row.h / 2
		x := row.x + 10
		label := m.entry.label
		x += ui.draw_text(r, label[:m.start], x, middle, .Body, th.text_primary)
		x += ui.draw_text(r, label[m.start:m.end], x, middle, .Body, th.accent_text)
		ui.draw_text(r, label[m.end:], x, middle, .Body, th.text_primary)
		ui.draw_text(
			r,
			m.entry.category,
			row.x + row.w - 10,
			middle,
			.Small,
			th.text_tertiary,
			.Right,
		)
		states: ui.Widget_States = i == p.current ? {.Selected} : {}
		ui.declare(ctx, {id = row_id, role = .Row, label = label, rect = row, states = states})
		if .Clicked in interaction {
			run_entry(ctx, app, m.entry)
			close_palette(app)
		}
	}
	ui.end_scroll(ctx, ui.child_id(id, "list"), list, content, &p.scroll)
	// The keys it answers to, under a line.
	footer := list.y + list.h + 6
	ui.fill_rect(r, {box.x, footer, box.w, 1}, th.border_subtle)
	x := box.x + 14
	for hint in ([]string{ui.tr("↑↓ to move"), ui.tr("↵ to run"), ui.tr("esc to close")}) {
		x += ui.draw_text(r, hint, x, footer + 1 + 15, .Small, th.text_tertiary) + 16
	}
}

// Runs an entry: its engine command, or what the app does on its own.
@(private = "file")
run_entry :: proc(ctx: ^ui.Ui, app: ^App, entry: Entry) {
	switch entry.special {
	case .None:
		execute(app, entry.command)
	case .Open_Folder:
		open_folder(app)
	case .Open_Files:
		open_files(app)
	case .Find:
		ui.focus_field(ctx, ui.widget_id("Filter"))
	}
}

// Every command, by name, with whether it can run now, in the palette's order. The
// strings are allocated with the temporary allocator: valid for the frame. Settings,
// About and the removals of a tag, which ask first, come with their slices.
@(private = "file")
palette_entries :: proc(app: ^App) -> []Entry {
	e := &app.engine
	entries := make([dynamic]Entry, context.temp_allocator)
	open := folder_open(app)
	selected := len(e.selection.tracks) > 0
	file, edit, controls, tags, view, settings :=
		ui.tr("File"),
		ui.tr("Edit"),
		ui.tr("Controls"),
		ui.tr("Tags"),
		ui.tr("View"),
		ui.tr("Settings")
	add :: proc(
		entries: ^[dynamic]Entry,
		label, category: string,
		enabled: bool,
		command: engine.Command,
		special := Special.None,
	) {
		append(entries, Entry{label, category, enabled, command, special})
	}
	add(&entries, ui.tr("Open Folder…"), file, true, nil, .Open_Folder)
	add(&entries, ui.tr("Open Files…"), file, true, nil, .Open_Files)
	add(
		&entries,
		ui.tr("Save"),
		file,
		len(e.edits.pending) > 0 && engine.saving(e) == nil,
		engine.Save{},
	)
	add(&entries, ui.tr("Undo"), edit, engine.can_undo(e), engine.Undo{})
	add(&entries, ui.tr("Redo"), edit, engine.can_redo(e), engine.Redo{})
	add(&entries, ui.tr("Find"), edit, open, nil, .Find)
	add(&entries, ui.tr("Select All"), edit, open, engine.Select_All{})
	add(&entries, ui.tr("Select Album"), edit, selected, engine.Select_Album{})
	add(&entries, ui.tr("Number Tracks"), edit, selected, engine.Number_Tracks{})
	add(&entries, ui.tr("Revert"), edit, engine.can_revert(e), engine.Revert{})
	playing := engine.playing(e.playback)
	add(
		&entries,
		playing ? ui.tr("Pause") : ui.tr("Play", "Player"),
		controls,
		engine.can_play(e) && open,
		engine.Play_Pause{},
	)
	add(&entries, ui.tr("Next Track"), controls, e.playback.track != nil, engine.Play_Next{})
	add(
		&entries,
		ui.tr("Previous Track"),
		controls,
		e.playback.track != nil,
		engine.Play_Previous{},
	)
	developer := e.view.developer_mode && selected
	add(
		&entries,
		ui.tr("Write ID3v2.4 to the selected files"),
		tags,
		developer,
		engine.Choose_Version{engine.Id3v2_Choice{lib.Id3v2_Version.V2_4}},
	)
	add(
		&entries,
		ui.tr("Write ID3v2.3 to the selected files"),
		tags,
		developer,
		engine.Choose_Version{engine.Id3v2_Choice{lib.Id3v2_Version.V2_3}},
	)
	add(
		&entries,
		ui.tr("Write ID3v2.2 to the selected files"),
		tags,
		developer,
		engine.Choose_Version{engine.Id3v2_Choice{lib.Id3v2_Version.V2_2}},
	)
	add(
		&entries,
		ui.tr("Write ID3v1.1 to the selected files"),
		tags,
		developer,
		engine.Choose_Version{engine.Id3v1_Choice{lib.Id3v1_Version.V1_1}},
	)
	add(
		&entries,
		ui.tr("Write ID3v1.0 to the selected files"),
		tags,
		developer,
		engine.Choose_Version{engine.Id3v1_Choice{lib.Id3v1_Version.V1_0}},
	)
	add(
		&entries,
		e.view.sidebar_visible ? ui.tr("Hide Sidebar") : ui.tr("Show Sidebar"),
		view,
		open,
		engine.Toggle_Sidebar{},
	)
	add(
		&entries,
		e.view.inspector_visible ? ui.tr("Hide Inspector") : ui.tr("Show Inspector"),
		view,
		open,
		engine.Toggle_Inspector{},
	)
	for column in engine.Column {
		name := column_name(engine.table_column(column))
		shown := column in e.view.columns
		label: string
		switch {
		case column == .Tags && shown:
			label = ui.fill(ui.tr("Hide the {} column (ID3 versions)"), name)
		case column == .Tags:
			label = ui.fill(ui.tr("Show the {} column (ID3 versions)"), name)
		case shown:
			label = ui.fill(ui.tr("Hide the {} column"), name)
		case:
			label = ui.fill(ui.tr("Show the {} column"), name)
		}
		add(&entries, label, view, true, engine.Toggle_Column{column})
	}
	add(&entries, ui.tr("Reset to default columns"), view, true, engine.Reset_Columns{})
	policy := e.edits.policy
	add(
		&entries,
		ui.tr("Write ID3v2.4 by default"),
		settings,
		policy.id3v2 != .V2_4,
		engine.Set_Write_Policy{{.V2_4, policy.id3v1}},
	)
	add(
		&entries,
		ui.tr("Write ID3v2.3 by default"),
		settings,
		policy.id3v2 != .V2_3,
		engine.Set_Write_Policy{{.V2_3, policy.id3v1}},
	)
	add(
		&entries,
		ui.tr("ID3v1 policy: keep where it exists"),
		settings,
		policy.id3v1 != .Keep,
		engine.Set_Write_Policy{{policy.id3v2, .Keep}},
	)
	add(
		&entries,
		ui.tr("ID3v1 policy: always write"),
		settings,
		policy.id3v1 != .Always,
		engine.Set_Write_Policy{{policy.id3v2, .Always}},
	)
	add(
		&entries,
		ui.tr("ID3v1 policy: never write"),
		settings,
		policy.id3v1 != .Never,
		engine.Set_Write_Policy{{policy.id3v2, .Never}},
	)
	add(
		&entries,
		e.view.developer_mode ? ui.tr("Turn developer mode off") : ui.tr("Turn developer mode on"),
		settings,
		true,
		engine.Toggle_Developer_Mode{},
	)
	return entries[:]
}

// The entries that can run and whose name holds query, ignoring case, cut around
// where it first does: names with a word that starts with it come first, then the
// others, then the entries whose category holds it, each group in the palette's
// order, as 1.0.0 ranked them. Allocated with the temporary allocator.
@(private)
matches :: proc(entries: []Entry, query: string) -> []Match {
	wanted := strings.trim_space(query)
	found := make([dynamic]Match, context.temp_allocator)
	for rank in 0 ..< 3 {
		for entry in entries {
			if !entry.enabled do continue
			start, end, in_label := find_ignoring_case(entry.label, wanted)
			switch rank {
			case 0:
				if !in_label || !(start == 0 || entry.label[start - 1] == ' ' || entry.label[start - 1] == '(') do continue
			case 1:
				if !in_label || start == 0 || entry.label[start - 1] == ' ' || entry.label[start - 1] == '(' do continue
			case 2:
				if in_label do continue
				if _, _, in_category := find_ignoring_case(entry.category, wanted); !in_category do continue
				start, end = 0, 0
			}
			append(&found, Match{entry, start, end})
		}
	}
	return found[:]
}

// Where query first appears in text, ignoring case, in bytes of text. An empty query
// appears at the start.
@(private)
find_ignoring_case :: proc(text, query: string) -> (start, end: int, found: bool) {
	if len(query) == 0 do return 0, 0, true
	lowered := strings.to_lower(text, context.temp_allocator)
	wanted := strings.to_lower(query, context.temp_allocator)
	at := strings.index(lowered, wanted)
	if at < 0 || len(lowered) != len(text) do return
	return at, at + len(wanted), true
}
