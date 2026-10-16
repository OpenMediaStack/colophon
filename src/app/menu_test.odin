package main

import "core:testing"

import "../engine"
import ui "../ui"

// A screen on a platform, with a folder open over one fixture, for the menus.
@(private = "file")
screen_on :: proc(
	t: ^testing.T,
	s: ^Screen,
	platform: ui.Platform,
	open := true,
) -> (
	folder: string,
) {
	screen_init(s, {1440, 900})
	s.app.platform = platform
	ui.run_frame(&s.h)
	if open {
		folder = folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
		open_folder_of(t, s, folder)
		wait_until_shown(t, s, "1 track")
	}
	return
}

@(private = "file")
menu_titles :: proc(s: ^Screen) -> (titles: [dynamic]string) {
	titles = make([dynamic]string, context.temp_allocator)
	for m in app_menus(&s.h.ui, &s.app) do append(&titles, m.title)
	return
}

@(private = "file")
line_of :: proc(s: ^Screen, menu, label: string) -> (line: Menu_Line, found: bool) {
	for m in app_menus(&s.h.ui, &s.app) {
		if m.title != menu do continue
		for l in m.lines do if l.entry.label == label do return l, true
	}
	return
}

@(test)
the_menus_follow_the_platform :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := [?]struct {
		platform:  ui.Platform,
		titles:    []string,
		settings:  string,
		in_menu:   string,
		shortcut:  string,
		open_with: string,
	} {
		{
			.Mac,
			{"Colophon", "File", "Edit", "Controls", "View"},
			"Settings…",
			"Colophon",
			"⌘,",
			"⌘O",
		},
		{
			.Windows,
			{"File", "Edit", "Controls", "View", "Help"},
			"Options…",
			"File",
			"Ctrl+,",
			"Ctrl+O",
		},
		{
			.Linux,
			{"File", "Edit", "Controls", "View", "Help"},
			"Preferences…",
			"Edit",
			"Ctrl+,",
			"Ctrl+O",
		},
	}
	for c in cases {
		s: Screen
		folder := screen_on(t, &s, c.platform, false)
		defer screen_destroy(&s)
		_ = folder
		titles := menu_titles(&s)
		testing.expect_value(t, len(titles), len(c.titles))
		for title, i in c.titles do if i < len(titles) do testing.expect_value(t, titles[i], title)
		settings, found := line_of(&s, c.in_menu, c.settings)
		testing.expectf(t, found, "%v has no %s in %s", c.platform, c.settings, c.in_menu)
		testing.expect_value(t, settings.shortcut, c.shortcut)
		open, has_open := line_of(&s, "File", "Open Folder…")
		testing.expect(t, has_open)
		testing.expect_value(t, open.shortcut, c.open_with)
	}
}

@(test)
the_menus_say_what_can_run_now :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	defer free_all(context.temp_allocator)
	save, _ := line_of(&s, "File", "Save")
	testing.expect(t, !save.entry.enabled)
	undo, _ := line_of(&s, "Edit", "Undo")
	testing.expect(t, !undo.entry.enabled)
	album, _ := line_of(&s, "Edit", "Select Album")
	testing.expect(t, !album.entry.enabled)
	hide, found := line_of(&s, "View", "Hide Sidebar")
	testing.expect(t, found && hide.entry.enabled)
	// An edit makes them run.
	execute(&s.app, engine.Select{s.app.engine.listed[0]})
	execute(&s.app, engine.Apply_Edit{{.Title, "Neon"}})
	ui.run_frame(&s.h)
	save, _ = line_of(&s, "File", "Save")
	testing.expect(t, save.entry.enabled)
	undo, _ = line_of(&s, "Edit", "Undo")
	testing.expect(t, undo.entry.enabled)
	album, _ = line_of(&s, "Edit", "Select Album")
	testing.expect(t, album.entry.enabled)
	// The panels' item says what it does.
	execute(&s.app, engine.Toggle_Sidebar{})
	ui.run_frame(&s.h)
	_, shows_show := line_of(&s, "View", "Show Sidebar")
	testing.expect(t, shows_show)
	// While a dialog is up, they wait.
	open_settings(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	save, _ = line_of(&s, "File", "Save")
	testing.expect(t, !save.entry.enabled)
	folder_line, _ := line_of(&s, "File", "Open Folder…")
	testing.expect(t, !folder_line.entry.enabled)
}

@(test)
the_menu_bar_is_drawn_where_the_system_has_none :: proc(t: ^testing.T) {
	for platform in ([?]ui.Platform{.Linux, .Windows}) {
		s: Screen
		folder := screen_on(t, &s, platform, false)
		defer screen_destroy(&s)
		_ = folder
		testing.expect(t, shows(&s, "Menu bar"))
		for title in ([]string{"File", "Edit", "Controls", "View", "Help"}) do testing.expect(t, shows(&s, title))
		l := layout_of(&s.app, {0, 0, 1440, 900})
		testing.expect_value(t, l.menu_bar.h, f32(MENU_BAR_HEIGHT))
		testing.expect_value(t, l.toolbar.y, f32(MENU_BAR_HEIGHT))
	}
	mac: Screen
	screen_on(t, &mac, .Mac, false)
	defer screen_destroy(&mac)
	testing.expect(t, !shows(&mac, "Menu bar"))
	testing.expect_value(t, layout_of(&mac.app, {0, 0, 1440, 900}).toolbar.y, f32(0))
}

@(test)
a_title_opens_its_menu_and_an_item_runs :: proc(t: ^testing.T) {
	s: Screen
	screen_on(t, &s, .Linux, false)
	defer screen_destroy(&s)
	music := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(music)
	append(&s.answers.folders, music)
	testing.expect(t, !shows(&s, "Open Files…"))
	testing.expect(t, ui.click(&s.h, "File"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Open Files…"))
	testing.expect(t, ui.click(&s.h, "Open Folder…"))
	ui.run_frame(&s.h)
	wait_until_shown(t, &s, "1 track")
	// The menu closed once an item was chosen.
	testing.expect(t, !shows(&s, "Open Files…"))
}

@(test)
the_mouse_going_to_another_title_opens_it_and_escape_closes :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Windows)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "File"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Open Files…"))
	edit, found := ui.find_widget(&s.h.ui, "Edit")
	if !testing.expect(t, found) do return
	ui.move_mouse(&s.h, ui.rect_center(edit.rect))
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Select Album"))
	testing.expect(t, !shows(&s, "Open Files…"))
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Select Album"))
}

@(test)
help_opens_about_and_the_view_menu_opens_the_palette :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Help"))
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "About Colophon"))
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.about.open)
	s.app.about.open = false
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "View"))
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Command Palette…"))
	ui.run_frame(&s.h)
	testing.expect(t, s.app.palette.open)
}

@(test)
the_menu_items_toggle_the_panels :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, s.app.engine.view.sidebar_visible)
	testing.expect(t, ui.click(&s.h, "View"))
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Hide Sidebar"))
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.engine.view.sidebar_visible)
}

@(test)
the_menus_speak_french :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(t, ui.catalog_tr(&c, "Menu bar"), "Barre de menus")
	testing.expect_value(t, ui.catalog_tr(&c, "File"), "Fichier")
	testing.expect_value(t, ui.catalog_tr(&c, "Edit"), "Édition")
	testing.expect_value(t, ui.catalog_tr(&c, "View"), "Présentation")
	testing.expect_value(t, ui.catalog_tr(&c, "Help"), "Aide")
}

// The window with the Edit menu open on Linux, in both themes.
@(test)
the_menu_bar_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		screen_init(&s, {1280, 720}, kind)
		defer screen_destroy(&s)
		s.app.platform = .Linux
		ui.run_frame(&s.h)
		testing.expect(t, ui.click(&s.h, "Edit"))
		ui.run_frame(&s.h)
		ui.move_mouse(&s.h, {0, 300})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "menu-bar-dark.png" : "menu-bar-light.png")
	}
}

// A dialog that opens while a menu is open takes the keys: the menu is closed, rather than
// left holding them.
@(test)
a_dialog_opening_under_a_menu_closes_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	execute(&s.app, engine.Select{s.app.engine.listed[0]})
	execute(&s.app, engine.Apply_Edit{{.Title, "Neon"}})
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "File"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Open Files…"))
	// What the window's close button does, with a change unsaved.
	testing.expect(t, !request_close(&s.app))
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Open Files…"))
	testing.expect_value(t, s.app.departure, Departure.Asking)
	// Escape reaches the dialog, which cancels the close.
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect_value(t, s.app.departure, nil)
}

@(test)
f10_opens_the_first_menu_and_the_arrows_go_from_one_to_the_next :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .F10)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Open Files…"))
	ui.press_key(&s.h, .Right)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Select Album"))
	testing.expect(t, !shows(&s, "Open Files…"))
	ui.press_key(&s.h, .Left)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Open Files…"))
	// From the first, Left goes round to the last.
	ui.press_key(&s.h, .Left)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "About Colophon"))
	testing.expect(t, !shows(&s, "Open Files…"))
}

// A title and its popup are two widgets, with ids of their own.
@(test)
a_title_and_its_menu_have_their_own_ids :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "File"))
	ui.run_frame(&s.h)
	seen := make(map[ui.Widget_Id]string, context.temp_allocator)
	for w in s.h.ui.widgets {
		if previous, twice := seen[w.id]; twice {
			testing.expectf(t, false, "%q and %q share an id", previous, w.label)
		}
		seen[w.id] = w.label
	}
}

@(test)
nothing_but_the_always_possible_waits_without_a_folder :: proc(t: ^testing.T) {
	s: Screen
	screen_on(t, &s, .Linux, false)
	defer screen_destroy(&s)
	defer free_all(context.temp_allocator)
	for entry in ([]struct {
			menu, label: string,
			enabled:     bool,
		}{{"File", "Open Folder…", true}, {"File", "Save", false}, {"Edit", "Find", false}, {"Edit", "Undo", false}, {"Controls", "Play", false}, {"Controls", "Next Track", false}, {"View", "Command Palette…", true}, {"View", "Hide Sidebar", false}, {"Help", "About Colophon", true}}) {
		line, found := line_of(&s, entry.menu, entry.label)
		testing.expectf(t, found, "%s has no %s", entry.menu, entry.label)
		testing.expectf(
			t,
			line.entry.enabled == entry.enabled,
			"%s: %v",
			entry.label,
			line.entry.enabled,
		)
	}
}

@(test)
the_bar_fits_the_smallest_windows :: proc(t: ^testing.T) {
	for platform in ([?]ui.Platform{.Linux, .Windows}) {
		s: Screen
		screen_init(&s, {960, 600})
		defer screen_destroy(&s)
		s.app.platform = platform
		ui.run_frame(&s.h)
		bar, found := ui.find_widget(&s.h.ui, "Menu bar")
		testing.expect(t, found)
		last, has_last := ui.find_widget(&s.h.ui, "Help")
		testing.expect(t, has_last)
		testing.expect(t, last.rect.x + last.rect.w <= bar.rect.x + bar.rect.w)
		toolbar, _ := ui.find_widget(&s.h.ui, "Toolbar")
		testing.expect_value(t, toolbar.rect.y, f32(MENU_BAR_HEIGHT))
	}
}

// What the system's menu bar chooses arrives as a number, and runs in the next frame.
@(test)
a_choice_of_the_system_menu_runs_its_command :: proc(t: ^testing.T) {
	s: Screen
	screen_on(t, &s, .Linux, false)
	defer screen_destroy(&s)
	music := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(music)
	append(&s.answers.folders, music)
	// File, then its first line: Open Folder….
	s.app.menu_choice = 0 * MENU_CODE + 0
	ui.run_frame(&s.h)
	wait_until_shown(t, &s, "1 track")
	testing.expect_value(t, s.app.menu_choice, nil)
}

@(test)
a_choice_that_cannot_run_or_is_gone_does_nothing :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_on(t, &s, .Linux)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	// Save, with nothing to save, and numbers past the menus and the lines.
	for code in ([?]int{0 * MENU_CODE + 2, 9 * MENU_CODE, 0 * MENU_CODE + 99, -1}) {
		s.app.menu_choice = code
		ui.run_frame(&s.h)
		testing.expect_value(t, s.app.menu_choice, nil)
	}
	testing.expect_value(t, len(s.app.engine.edits.pending), 0)
	testing.expect(t, !s.app.settings_open)
	// The Edit menu's Preferences… on Linux runs: Edit is the second, its last line.
	menus := app_menus(&s.h.ui, &s.app)
	last := len(menus[1].lines) - 1
	s.app.menu_choice = 1 * MENU_CODE + last
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.settings_open)
}
