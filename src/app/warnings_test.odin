package main

import "core:strings"
import "core:testing"

import "../engine"
import ui "../ui"

// Whether a row is in the warning state: its mark shows once nothing else does, as a
// change waiting to be saved comes first.
@(private = "file")
warned :: proc(s: ^Screen, row: int) -> bool {
	return .Warning in track_states(&s.app, row)
}

// Whether a row's status mark says the track looks wrong beside its album.
@(private = "file")
marked :: proc(s: ^Screen, row: int) -> bool {
	status := ui.child_id(ui.child_id(ui.widget_id("Tracks"), "row", row), "status")
	for w in s.h.ui.widgets do if w.id == status do return w.label == "Unlike the rest of its album"
	return false
}

@(test)
a_track_unlike_the_rest_of_its_album_is_marked :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v23_full.mp3", "2.mp3"}})
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "2 tracks")
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	testing.expect(t, !shows(&s, "Unlike the rest of its album"))
	retype(&s, "Track", "")
	ui.press_key(&s.h, .Backspace)
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "This track has no number, unlike the rest of its album."))
	testing.expect(t, warned(&s, 0))
	testing.expect(t, !warned(&s, 1))
	// The mark shows once the change is saved: the unsaved dot came first.
	testing.expect(t, !marked(&s, 0))
	execute(&s.app, engine.Save{})
	wait_for_save(t, &s)
	testing.expect(t, marked(&s, 0))
	testing.expect(t, !marked(&s, 1))
}

@(test)
the_warnings_of_several_tracks_speak_of_some_of_them :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with_fixtures(
		t,
		{{"v23_full.mp3", "1.mp3"}, {"v23_full.mp3", "2.mp3"}, {"v23_full.mp3", "3.mp3"}},
	)
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "3 tracks")
	e := &s.app.engine
	execute(&s.app, engine.Select{e.listed[0]})
	execute(&s.app, engine.Apply_Edit{{.Album_Artist, "Someone Else"}})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Its album artist differs from the rest of its album."))
	execute(&s.app, engine.Select_All{})
	ui.run_frame(&s.h)
	testing.expect(
		t,
		shows(
			&s,
			"Some of these tracks have an album artist that differs from the rest of their albums.",
		),
	)
	testing.expect(t, warned(&s, 0))
	testing.expect(t, !warned(&s, 1))
}

// A track without a number beside its album, saved so, marked in the table and
// explained in the inspector, in both themes.
@(test)
the_warnings_match_their_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		screen_init(&s, {1440, 900}, kind)
		defer screen_destroy(&s)
		folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v23_full.mp3", "2.mp3"}})
		defer remove_folder(folder)
		delete(s.app.home)
		s.app.home = strings.clone(folder)
		open_folder_of(t, &s, folder)
		wait_until_shown(t, &s, "2 tracks")
		e := &s.app.engine
		execute(&s.app, engine.Select{e.listed[0]})
		execute(&s.app, engine.Apply_Edit{{.Track, nil}})
		execute(&s.app, engine.Save{})
		wait_for_save(t, &s)
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "warnings-dark.png" : "warnings-light.png")
	}
}
