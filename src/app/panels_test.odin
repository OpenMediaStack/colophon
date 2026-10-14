package main

import "core:testing"

import ui "../ui"

// A screen at 1440 by 900 with an empty folder open: the panels show.
@(private = "file")
open_screen :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 900})
	folder = folder_with_fixtures(t, {})
	open_folder_of(t, s, folder)
	return
}

@(test)
the_toolbar_button_hides_and_shows_the_sidebar :: proc(t: ^testing.T) {
	s: Screen
	folder := open_screen(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	toggle, _ := ui.find_widget(&s.h.ui, "Toggle sidebar")
	testing.expect(t, .Checkable in toggle.states && .Checked in toggle.states)
	ui.click(&s.h, "Toggle sidebar")
	testing.expect(t, !shows(&s, "Sidebar"))
	// The button's own state follows in the next frame: it was drawn before the click.
	ui.run_frame(&s.h)
	toggle, _ = ui.find_widget(&s.h.ui, "Toggle sidebar")
	testing.expect(t, .Checked not_in toggle.states)
	ui.click(&s.h, "Toggle sidebar")
	testing.expect(t, shows(&s, "Sidebar"))
}

@(test)
the_toolbar_button_hides_the_inspector :: proc(t: ^testing.T) {
	s: Screen
	folder := open_screen(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Toggle inspector")
	testing.expect(t, !shows(&s, "Inspector"))
	testing.expect(t, shows(&s, "Sidebar"))
}

@(test)
the_inspector_shortcut_toggles_the_inspector :: proc(t: ^testing.T) {
	s: Screen
	folder := open_screen(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .I, ui.COMMAND + {.Alt})
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Inspector"))
	ui.press_key(&s.h, .I, ui.COMMAND + {.Alt})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Inspector"))
}

@(test)
the_sidebar_shortcut_toggles_the_sidebar :: proc(t: ^testing.T) {
	s: Screen
	folder := open_screen(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .S, ui.COMMAND + {.Alt})
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Sidebar"))
}

@(test)
the_panel_toggles_wait_for_something_open :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	toggle, _ := ui.find_widget(&s.h.ui, "Toggle sidebar")
	testing.expect(t, .Disabled in toggle.states && .Checked not_in toggle.states)
	ui.press_key(&s.h, .S, ui.COMMAND + {.Alt})
	testing.expect(t, s.app.engine.view.sidebar_visible)
}
