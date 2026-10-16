package main

import "core:slice"

import "../engine"
import ui "../ui"

// The height of the menu bar drawn inside the window, its line under it included, and the
// mockup's room around its titles: the bar's side, the title's side, the gap between.
MENU_BAR_HEIGHT :: 28
@(private = "file")
BAR_SIDE :: 6
@(private = "file")
TITLE_SIDE :: 8
@(private = "file")
TITLE_GAP :: 2

// A line of a menu: a command, with the shortcut that does the same.
@(private)
Menu_Line :: struct {
	entry:     Entry,
	shortcut:  string,
	// A line before it, between groups.
	separator: bool,
}

// A menu of the menu bar: File, Edit, and so on.
@(private)
Menu :: struct {
	title: string,
	lines: []Menu_Line,
}

// The menus of the menu bar, as 1.0.0's: what each does and whether it can now, a
// dialog being up making them wait. Settings are in the File menu on macOS and Windows,
// and in the Edit menu on Linux, which calls them Preferences; macOS has About in the
// application menu. The strings are allocated with the temporary allocator.
@(private)
app_menus :: proc(ctx: ^ui.Ui, app: ^App) -> []Menu {
	e := &app.engine
	open := folder_open(app)
	waiting := ui.modal_shown(ctx)
	selected := len(e.selection.tracks) > 0
	linux, mac := app.platform == .Linux, app.platform == .Mac
	menus := make([dynamic]Menu, context.temp_allocator)
	lines := make([dynamic]Menu_Line, context.temp_allocator)
	line :: proc(
		lines: ^[dynamic]Menu_Line,
		label: string,
		enabled: bool,
		command: engine.Command,
		special := Special.None,
		shortcut := "",
		separator := false,
	) {
		append(lines, Menu_Line{Entry{label, "", enabled, command, special}, shortcut, separator})
	}
	finish :: proc(menus: ^[dynamic]Menu, lines: ^[dynamic]Menu_Line, title: string) {
		append(menus, Menu{title, slice.clone(lines[:], context.temp_allocator)})
		clear(lines)
	}

	// macOS keeps About and Settings in the application menu, as the brief says.
	if mac {
		line(&lines, ui.tr("About Colophon"), !waiting, nil, .About)
		line(
			&lines,
			settings_label(app),
			!waiting,
			nil,
			.Settings,
			shortcut_hint(app, ","),
			separator = true,
		)
		finish(&menus, &lines, "Colophon")
	}
	line(&lines, ui.tr("Open Folder…"), !waiting, nil, .Open_Folder, shortcut_hint(app, "O"))
	line(
		&lines,
		ui.tr("Open Files…"),
		!waiting,
		nil,
		.Open_Files,
		shortcut_hint(app, "O", shift = true),
	)
	saving := engine.saving(e) != nil
	line(
		&lines,
		ui.tr("Save"),
		len(e.edits.pending) > 0 && !saving && !waiting,
		nil,
		.Save,
		shortcut_hint(app, "S"),
		separator = true,
	)
	if !linux && !mac {
		line(
			&lines,
			settings_label(app),
			!waiting,
			nil,
			.Settings,
			shortcut_hint(app, ","),
			separator = true,
		)
	}
	finish(&menus, &lines, ui.tr("File"))

	line(
		&lines,
		ui.tr("Undo"),
		engine.can_undo(e) && !waiting,
		engine.Undo{},
		shortcut = shortcut_hint(app, "Z"),
	)
	line(
		&lines,
		ui.tr("Redo"),
		engine.can_redo(e) && !waiting,
		engine.Redo{},
		shortcut = shortcut_hint(app, "Z", shift = true),
	)
	line(
		&lines,
		ui.tr("Find"),
		open && !waiting,
		nil,
		.Find,
		shortcut_hint(app, "F"),
		separator = true,
	)
	line(
		&lines,
		ui.tr("Select Album"),
		selected && !waiting,
		engine.Select_Album{},
		separator = true,
	)
	line(&lines, ui.tr("Number Tracks"), selected && !waiting, engine.Number_Tracks{})
	if linux {
		line(
			&lines,
			settings_label(app),
			!waiting,
			nil,
			.Settings,
			shortcut_hint(app, ","),
			separator = true,
		)
	}
	finish(&menus, &lines, ui.tr("Edit"))

	playing := engine.playing(e.playback)
	line(
		&lines,
		playing ? ui.tr("Pause") : ui.tr("Play", "Player"),
		engine.can_play(e) && open && !waiting,
		engine.Play_Pause{},
	)
	line(&lines, ui.tr("Next Track"), e.playback.track != nil && !waiting, engine.Play_Next{})
	line(
		&lines,
		ui.tr("Previous Track"),
		e.playback.track != nil && !waiting,
		engine.Play_Previous{},
	)
	finish(&menus, &lines, ui.tr("Controls"))

	line(&lines, ui.tr("Command Palette…"), !waiting, nil, .Palette, shortcut_hint(app, "K"))
	sidebar := e.view.sidebar_visible
	line(
		&lines,
		sidebar ? ui.tr("Hide Sidebar") : ui.tr("Show Sidebar"),
		open,
		engine.Toggle_Sidebar{},
		shortcut = shortcut_hint(app, "S", alt = true),
		separator = true,
	)
	inspector := e.view.inspector_visible
	line(
		&lines,
		inspector ? ui.tr("Hide Inspector") : ui.tr("Show Inspector"),
		open,
		engine.Toggle_Inspector{},
		shortcut = shortcut_hint(app, "I", alt = true),
	)
	finish(&menus, &lines, ui.tr("View"))

	if !mac {
		line(&lines, ui.tr("About Colophon"), !waiting, nil, .About)
		finish(&menus, &lines, ui.tr("Help"))
	}
	return menus[:]
}

// The menu bar drawn inside the window, on the platforms whose own is not used: the
// titles of the menus, each opening its menu under it, and the mouse going from one
// title to the next while a menu is open opening that one. Escape closes it.
menu_bar :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	ui.fill_rect(r, rect, th.menu_bar)
	ui.fill_rect(r, {rect.x, rect.y + rect.h - 1, rect.w, 1}, th.border_subtle)
	id := ui.widget_id("Menu bar")
	ui.declare(ctx, {id = id, role = .Group, label = ui.tr("Menu bar"), rect = rect})
	ui.push_parent(ctx, id)
	defer ui.pop_parent(ctx)
	menus := app_menus(ctx, app)
	title_rects := make([]ui.Rect, len(menus), context.temp_allocator)
	x := rect.x + BAR_SIDE
	for menu, i in menus {
		width := ui.text_width(r, menu.title, .Body) + 2 * TITLE_SIDE
		title_rects[i] = {x, rect.y + 2, width, rect.h - 5}
		x += width + TITLE_GAP
	}
	// Whether one of the bar's menus is open, not a context menu of the window.
	bar_open := false
	for _, i in menus do bar_open ||= ui.is_menu_open(ctx, ui.child_id(id, "menu", i))
	// F10 opens the first menu, as it does on Windows and in GTK.
	if !bar_open && ui.take_key(ctx, .F10) && len(menus) > 0 {
		ui.open_menu(ctx, ui.child_id(id, "menu", 0), {title_rects[0].x, rect.y + rect.h})
	}
	for menu, i in menus {
		menu_id := ui.child_id(id, "menu", i)
		title_id := ui.child_id(id, "title", i)
		open := ui.is_menu_open(ctx, menu_id)
		// The popup takes the mouse while a menu is open: where it is decides the switch.
		over := ui.rect_contains(title_rects[i], ctx.input.mouse)
		interaction := ui.interact(ctx, title_id, title_rects[i])
		if (.Clicked in interaction) || (over && bar_open && !open) {
			ui.open_menu(ctx, menu_id, {title_rects[i].x, rect.y + rect.h})
			open = true
		}
		if open || .Hovered in interaction do ui.fill_rect(r, title_rects[i], th.surface_3, 4)
		ui.draw_text(
			r,
			menu.title,
			title_rects[i].x + TITLE_SIDE,
			rect.y + (rect.h - 1) / 2,
			.Body,
			th.text_primary,
		)
		states: ui.Widget_States = open ? {.Expanded} : {}
		ui.declare(
			ctx,
			{
				id = title_id,
				role = .Button,
				label = menu.title,
				rect = title_rects[i],
				states = states,
			},
		)
	}
	for menu, i in menus {
		menu_id := ui.child_id(id, "menu", i)
		if !ui.is_menu_open(ctx, menu_id) do continue
		items := make([]ui.Menu_Item, len(menu.lines), context.temp_allocator)
		for line, j in menu.lines {
			items[j] = {
				label     = line.entry.label,
				shortcut  = line.shortcut,
				disabled  = !line.entry.enabled,
				separator = line.separator,
			}
		}
		if chosen, picked := ui.menu(ctx, menu_id, items, menu.title).?; picked {
			run_entry(ctx, app, menu.lines[chosen].entry)
		}
		// Left and Right go to the menu beside, as in every menu bar.
		if step := ui.menu_step(ctx); step != 0 {
			next := (i + step + len(menus)) % len(menus)
			ui.open_menu(
				ctx,
				ui.child_id(id, "menu", next),
				{title_rects[next].x, rect.y + rect.h},
			)
		}
		break
	}
}

// Whether the window draws its own menu bar: on every platform whose menu bar is not the
// system's. macOS has a global one, which a later slice fills.
menu_bar_drawn :: proc(app: ^App) -> bool {
	return app.platform != .Mac
}

// A menu choice made outside the frames, in the system's menu bar, as the number of the
// menu times MENU_CODE plus the number of the line. Runs the command of the line, if it
// is still there and can run: the choice and the frame that runs it are not the same
// moment. Call it in a frame.
take_menu_choice :: proc(ctx: ^ui.Ui, app: ^App) {
	code, chosen := app.menu_choice.?
	if !chosen do return
	app.menu_choice = nil
	menus := app_menus(ctx, app)
	menu, line := code / MENU_CODE, code % MENU_CODE
	if code < 0 || menu >= len(menus) || line >= len(menus[menu].lines) do return
	entry := menus[menu].lines[line].entry
	if entry.enabled do run_entry(ctx, app, entry)
	// The command ran in this frame, which shows it at once.
	app.commands += 1
}

// What a menu choice's number is made of: menu * MENU_CODE + line.
MENU_CODE :: 100
