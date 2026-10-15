package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "../engine"
import ui "../ui"

// The smallest window the brief allows, and the one 1.0.0 was checked at beside it.
@(private = "file")
SMALL_SIZES := [2][2]f32{{1280, 720}, {960, 600}}

// A screen over ten tracks of one album, all selected, at size.
@(private = "file")
screen_at :: proc(t: ^testing.T, s: ^Screen, size: [2]f32) -> (folder: string) {
	screen_init(s, size)
	copies: [10][2]string
	for &c, i in copies do c = {"v23_v1_long_title.mp3", fmt.tprintf("A track with a name of some length %02d.mp3", i)}
	folder = folder_with_fixtures(t, copies[:])
	// The folder shows as the home, "~": the same on every platform.
	delete(s.app.home)
	s.app.home = strings.clone(folder)
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "10 tracks")
	execute(&s.app, engine.Select_All{})
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	return
}

// Whether the widget with the id lies inside the window.
@(private = "file")
inside_window :: proc(s: ^Screen, id: ui.Widget_Id) -> (inside, found: bool) {
	window := s.h.ui.viewport
	for w in s.h.ui.widgets do if w.id == id {
		r := w.rect
		return r.x >= 0 && r.y >= 0 && r.x + r.w <= window.w && r.y + r.h <= window.h, true
	}
	return false, false
}

@(test)
every_overlay_fits_the_smallest_windows :: proc(t: ^testing.T) {
	for size in SMALL_SIZES {
		s: Screen
		folder := screen_at(t, &s, size)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		context_name := fmt.tprintf("%vx%v", size.x, size.y)

		open_palette(&s.app)
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		fits, found := inside_window(&s, ui.widget_id("Palette"))
		testing.expectf(t, found && fits, "the palette at %s", context_name)
		s.app.palette.open = false
		ui.run_frame(&s.h)

		open_settings(&s.app)
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		fits, found = inside_window(&s, ui.widget_id("Settings"))
		testing.expectf(t, found && fits, "the settings at %s", context_name)
		s.app.settings_open = false
		ui.run_frame(&s.h)

		request_version(&s.app, engine.Id3v1_Choice{nil})
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		fits, found = inside_window(&s, ui.widget_id("Tag removal"))
		testing.expectf(t, found && fits, "the removal at %s", context_name)
		forget_removal(&s.app)
		ui.run_frame(&s.h)

		show_about(&s.app)
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		fits, found = inside_window(&s, ui.widget_id("About"))
		testing.expectf(t, found && fits, "about at %s", context_name)
		s.app.about.licenses = true
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		fits, found = inside_window(&s, ui.widget_id("About"))
		testing.expectf(t, found && fits, "the licenses at %s", context_name)
		s.app.about.open = false
		ui.run_frame(&s.h)

	}
}

// The main screen with its inspector in developer mode, and two overlays, at each of
// the small sizes.
@(test)
the_small_windows_match_their_references :: proc(t: ^testing.T) {
	for size in SMALL_SIZES {
		s: Screen
		folder := screen_at(t, &s, size)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		name := fmt.tprintf("%vx%v", int(size.x), int(size.y))
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, fmt.tprintf("small-%s.png", name))
		open_settings(&s.app)
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		expect_screen(t, &s, fmt.tprintf("small-settings-%s.png", name))
		s.app.settings_open = false
		open_palette(&s.app)
		ui.type_text(&s.h, "id3")
		ui.run_frame(&s.h)
		expect_screen(t, &s, fmt.tprintf("small-palette-%s.png", name))
	}
}
