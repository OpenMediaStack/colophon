package main

import "core:fmt"
import "core:testing"

import ui "../ui"

// What a fresh window shows: the first launch screen, without the sidebar and the
// inspector until something is open.
@(private = "file")
REGIONS :: [?]string{"Filter", "Open your music folder", "No folder open"}

// A screen with an empty folder open, so that the panels have a reason to show.
@(private = "file")
screen_with_a_folder :: proc(t: ^testing.T, s: ^Screen, size: [2]f32) -> (folder: string) {
	screen_init(s, size)
	folder = folder_with_fixtures(t, {})
	open_folder_of(t, s, folder)
	return
}

@(test)
a_large_window_shows_every_region :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	for region in REGIONS do testing.expectf(t, shows(&s, region), "%s is missing", region)
}

@(test)
the_panels_wait_for_something_open :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	testing.expect(t, !shows(&s, "Sidebar"))
	testing.expect(t, !shows(&s, "Inspector"))
	folder := folder_with_fixtures(t, {})
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	testing.expect(t, shows(&s, "Sidebar"))
	testing.expect(t, shows(&s, "Inspector"))
	testing.expect(t, !shows(&s, "Open your music folder"))
}

@(test)
the_sidebar_gives_way_in_a_small_window :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_folder(t, &s, {960, 600})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, !shows(&s, "Sidebar"))
	testing.expect(t, shows(&s, "Inspector"))
}

@(test)
the_sidebar_comes_back_when_the_window_grows :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_folder(t, &s, {960, 600})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, !shows(&s, "Sidebar"))
	resize(&s, {1440, 900})
	testing.expect(t, shows(&s, "Sidebar"))
}

@(test)
hiding_the_inspector_makes_room_for_the_sidebar :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_folder(t, &s, {960, 600})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Toggle inspector")
	testing.expect(t, shows(&s, "Sidebar"))
	testing.expect(t, !shows(&s, "Inspector"))
}

// With the inspector shown, the sidebar needs 220 and the centre 560: 1100 keeps it,
// a point less drops it.
@(test)
the_sidebar_gives_way_just_below_the_centre_width_it_needs :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_folder(t, &s, {1100, 600})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, layout_of(&s.app, {0, 0, 1100, 600}).sidebar_shown)
	testing.expect(t, !layout_of(&s.app, {0, 0, 1099, 600}).sidebar_shown)
	testing.expect_value(t, layout_of(&s.app, {0, 0, 1100, 600}).centre.w, 558)
}

@(test)
hidden_panels_are_not_shown :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_folder(t, &s, {1440, 900})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.click(&s.h, "Toggle sidebar")
	ui.click(&s.h, "Toggle inspector")
	testing.expect(t, !shows(&s, "Sidebar"))
	testing.expect(t, !shows(&s, "Inspector"))
	// The centre column takes the whole width.
	l := layout_of(&s.app, s.h.ui.viewport)
	testing.expect_value(t, l.centre.w, 1440)
}

// The regions' names in French, from 1.0.0's catalogue: checked on the catalogue
// itself, since the one in use is shared by every test.
@(test)
the_regions_are_named_in_french_when_selected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(
		t,
		ui.catalog_tr(&c, "Open your music folder"),
		"Ouvrez votre dossier de musique",
	)
	testing.expect_value(t, ui.catalog_tr(&c, "No folder open"), "Aucun dossier ouvert")
	testing.expect_value(
		t,
		ui.catalog_tr(&c, "Filter by title, artist, album"),
		"Filtrer par titre, artiste, album",
	)
}

@(test)
the_layout_matches_its_references :: proc(t: ^testing.T) {
	sizes := [?][2]f32{{1440, 900}, {1280, 720}, {960, 600}}
	for size in sizes {
		for kind in ui.Theme_Kind {
			s: Screen
			screen_init(&s, size, kind)
			defer screen_destroy(&s)
			name := fmt.tprintf(
				"layout-%s-%dx%d.png",
				kind == .Dark ? "dark" : "light",
				int(size.x),
				int(size.y),
			)
			expect_screen(t, &s, name)
		}
	}
}
