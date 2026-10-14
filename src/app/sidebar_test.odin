package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "../engine"
import ui "../ui"

// Whether the sidebar shows a line labelled label: the table may show the same words
// in a cell.
@(private = "file")
sidebar_shows :: proc(s: ^Screen, label: string) -> bool {
	for w in s.h.ui.widgets do if w.label == label && w.parent == ui.widget_id("Sidebar") do return true
	return false
}

// The main screen over a library of three tracks, two of Small Hours by Marlowe Kite
// and one by 坂本龍一, and a file whose tags cannot be read.
@(private = "file")
screen_with_a_library :: proc(t: ^testing.T, s: ^Screen) -> (folder: string) {
	screen_init(s, {1440, 900})
	folder = folder_with_fixtures(
		t,
		{
			{"v23_full.mp3", "1.mp3"},
			{"v23_full.mp3", "2.mp3"},
			{"v23_unicode.mp3", "3.mp3"},
			{"tiny_tag.mp3", "4.mp3"},
		},
	)
	// The folder shows from the home folder, as "~": a home named the same on every run.
	delete(s.app.home)
	s.app.home = strings.clone(folder)
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "4 tracks")
	return
}

@(test)
the_sidebar_lists_the_library_its_folder_and_albums :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_library(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	for label in ([]string{"All tracks", "Recently changed", "Unreadable files", "~", "Small Hours", "Ελληνικά"}) {
		testing.expectf(t, sidebar_shows(&s, label), "%s is missing", label)
	}
	testing.expect(t, sidebar_shows(&s, "Folders"))
	// Each line carries its count.
	all, _ := ui.find_widget(&s.h.ui, "All tracks")
	testing.expect_value(t, all.value, "4")
	unreadable, _ := ui.find_widget(&s.h.ui, "Unreadable files")
	testing.expect_value(t, unreadable.value, "1")
	// The artists are folded until asked for.
	testing.expect(t, !sidebar_shows(&s, "坂本龍一"))
}

@(test)
an_album_lists_its_tracks_alone_and_titles_the_window :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_library(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect_value(t, window_title(&s.app), "Colophon · All tracks")
	testing.expect(t, ui.click(&s.h, "Small Hours"))
	testing.expect_value(t, len(s.app.engine.listed), 2)
	testing.expect_value(t, window_title(&s.app), "Colophon · Small Hours")
	// The row was drawn before the click: its state follows in the next frame.
	ui.run_frame(&s.h)
	album, _ := ui.find_widget(&s.h.ui, "Small Hours")
	testing.expect(t, .Selected in album.states)
	testing.expect(t, ui.click(&s.h, "All tracks"))
	testing.expect_value(t, len(s.app.engine.listed), 4)
	testing.expect_value(t, window_title(&s.app), "Colophon · All tracks")
	testing.expect(t, ui.click(&s.h, "~"))
	testing.expect_value(t, len(s.app.engine.listed), 4)
	testing.expect_value(t, window_title(&s.app), "Colophon · ~")
}

@(test)
the_unreadable_files_are_one_click_away :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_library(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Unreadable files"))
	testing.expect_value(t, len(s.app.engine.listed), 1)
}

@(test)
the_artists_show_once_unfolded :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_a_library(t, &s)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Artists"))
	testing.expect(t, ui.click(&s.h, "坂本龍一"))
	testing.expect_value(t, len(s.app.engine.listed), 1)
	testing.expect_value(t, window_title(&s.app), "Colophon · 坂本龍一")
}

@(test)
the_first_albums_show_until_the_rest_is_asked_for :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	// Ten albums, one track each: a fixture copied, each copy's album set and saved,
	// since the sidebar groups the tracks by their files' tags.
	copies: [10][2]string
	for &c, i in copies do c = {"v23_full.mp3", fmt.tprintf("%02d.mp3", i)}
	folder := folder_with_fixtures(t, copies[:])
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "10 tracks")
	e := &s.app.engine
	for id, i in e.listed {
		execute(&s.app, engine.Select{id})
		execute(&s.app, engine.Apply_Edit{{.Album, fmt.tprintf("Album %02d", i)}})
	}
	execute(&s.app, engine.Save{})
	wait_for_save(t, &s)
	ui.run_frame(&s.h)
	testing.expect(t, sidebar_shows(&s, "Album 07"))
	testing.expect(t, !sidebar_shows(&s, "Album 09"))
	testing.expect(t, ui.click(&s.h, "2 more albums"))
	ui.run_frame(&s.h)
	testing.expect(t, sidebar_shows(&s, "Album 09"))
}

@(test)
the_sidebar_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		screen_init(&s, {1440, 900}, kind)
		defer screen_destroy(&s)
		// A folder named the same on every run, since the sidebar shows its name.
		folder := folder_with_fixtures(
			t,
			{
				{"v23_full.mp3", "Music/1.mp3"},
				{"v23_full.mp3", "Music/2.mp3"},
				{"v23_unicode.mp3", "Music/3.mp3"},
				{"v24_full.mp3", "Music/4.mp3"},
				{"tiny_tag.mp3", "Music/5.mp3"},
			},
		)
		defer remove_folder(folder)
		delete(s.app.home)
		s.app.home = strings.clone(folder)
		open_folder_of(t, &s, fmt.tprintf("%s/Music", folder))
		wait_until_shown(t, &s, "5 tracks")
		testing.expect(t, ui.click(&s.h, "Artists"))
		testing.expect(t, ui.click(&s.h, "Small Hours"))
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "sidebar-dark.png" : "sidebar-light.png")
	}
}
