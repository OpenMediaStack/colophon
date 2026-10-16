package main

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "../audio"
import "../engine"
import ui "../ui"

// What the fake speakers were asked, and what they say, as 1.0.0's player tests had
// them.
@(private = "file")
FIXTURES :: #directory + "/../../testdata"

@(private = "file")
Speakers :: struct {
	playing:  string,
	paused:   bool,
	position: time.Duration,
	volume:   f32,
	// The file has played to its end.
	finished: bool,
	// A file name that fails to play.
	broken:   string,
}

@(private = "file")
fake_output :: proc(s: ^Speakers) -> engine.Output {
	return {
		data = s,
		play = speakers_play,
		pause = speakers_pause,
		resume = speakers_resume,
		stop = speakers_stop,
		seek = speakers_seek,
		position = speakers_position,
		finished = speakers_finished,
		set_volume = speakers_set_volume,
	}
}

@(private = "file")
speakers_play :: proc(data: rawptr, path: string) -> engine.Play_Error {
	s := (^Speakers)(data)
	if filepath.base(path) == s.broken do return .Cannot_Decode
	s.playing, s.paused, s.position, s.finished = filepath.base(path), false, 0, false
	return .None
}

@(private = "file")
speakers_pause :: proc(data: rawptr) {
	(^Speakers)(data).paused = true
}

@(private = "file")
speakers_resume :: proc(data: rawptr) {
	(^Speakers)(data).paused = false
}

@(private = "file")
speakers_stop :: proc(data: rawptr) {
	(^Speakers)(data).playing = ""
}

@(private = "file")
speakers_seek :: proc(data: rawptr, position: time.Duration) -> engine.Play_Error {
	(^Speakers)(data).position = position
	return .None
}

@(private = "file")
speakers_position :: proc(data: rawptr) -> time.Duration {
	return (^Speakers)(data).position
}

@(private = "file")
speakers_finished :: proc(data: rawptr) -> bool {
	return (^Speakers)(data).finished
}

@(private = "file")
speakers_set_volume :: proc(data: rawptr, volume: f32) {
	(^Speakers)(data).volume = volume
}

// The main screen in English playing through fake speakers, over "Paper Satellites" and
// "Café", the first selected.
@(private = "file")
screen_playing :: proc(
	t: ^testing.T,
	s: ^Screen,
	speakers: ^Speakers,
	size := [2]f32{1440, 900},
	kind := ui.Theme_Kind.Dark,
) -> (
	folder: string,
) {
	screen_init(s, size, kind)
	s.app.engine.output = fake_output(speakers)
	folder = folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v23_unicode.mp3", "2.mp3"}})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "2 tracks")
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	ui.run_frame(&s.h)
	return
}

// A widget of the player, found through it: the table shows the same words.
@(private = "file")
in_player :: proc(s: ^Screen, label: string) -> (info: ui.Widget_Info, found: bool) {
	player, has_player := ui.find_widget(&s.h.ui, "Player")
	if !has_player do return
	for w in s.h.ui.widgets do if w.parent == player.id && w.label == label do return w, true
	return
}

@(test)
space_plays_the_selected_track_and_marks_its_row :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect_value(t, speakers.playing, "1.mp3")
	_, titled := in_player(&s, "Paper Satellites")
	testing.expect(t, titled)
	_, artist := in_player(&s, "Marlowe Kite")
	testing.expect(t, artist)
	testing.expect(t, engine.playing(s.app.engine.playback))
	testing.expect(t, .Playing in track_states(&s.app, 0))
	_, pausable := in_player(&s, "Pause")
	testing.expect(t, pausable)
}

@(test)
the_player_pauses_and_moves_to_the_next_track :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Pause"))
	ui.run_frame(&s.h)
	testing.expect(t, speakers.paused)
	testing.expect(t, !engine.playing(s.app.engine.playback))
	_, playable := in_player(&s, "Play")
	testing.expect(t, playable)
	testing.expect(t, ui.click(&s.h, "Next track"))
	ui.run_frame(&s.h)
	testing.expect_value(t, speakers.playing, "2.mp3")
	_, next_title := in_player(&s, "Café")
	testing.expect(t, next_title)
	testing.expect(t, .Playing not_in track_states(&s.app, 0))
	testing.expect(t, ui.click(&s.h, "Previous track"))
	ui.run_frame(&s.h)
	// Within the first seconds, the one before.
	testing.expect_value(t, speakers.playing, "1.mp3")
}

@(test)
the_position_and_the_volume_reach_the_output :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	// A track long enough for a seek to the middle: the fixture's is a blink.
	s.app.engine.library.tracks[0].metadata.audio.duration = 10 * time.Second
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	position, has_position := in_player(&s, "Position")
	volume, has_volume := in_player(&s, "Volume")
	if !testing.expect(t, has_position && has_volume) do return
	middle := ui.rect_center(position.rect)
	ui.move_mouse(&s.h, {position.rect.x + position.rect.w / 2, middle.y})
	ui.press(&s.h)
	ui.release(&s.h)
	testing.expect(t, speakers.position > 0)
	ui.move_mouse(&s.h, {volume.rect.x + volume.rect.w * 0.3, volume.rect.y + 8})
	ui.press(&s.h)
	ui.release(&s.h)
	testing.expect(t, abs(speakers.volume - 0.3) < 0.02)
	testing.expect_value(t, s.app.engine.playback.volume, speakers.volume)
}

@(test)
the_player_shows_once_a_track_plays :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, !shows(&s, "Player"))
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Player"))
	// The playhead moves while it plays: a frame is asked for.
	testing.expect(t, s.h.ui.wake_at < max(f64))
}

@(test)
without_a_sound_device_the_player_is_off :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "1 track")
	testing.expect(t, ui.click(&s.h, "Marlowe Kite"))
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, !engine.can_play(&s.app.engine))
	testing.expect(t, !shows(&s, "Player"))
}

@(test)
a_narrow_bar_drops_the_volume :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers, {1200, 900})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	_, position := in_player(&s, "Position")
	_, volume := in_player(&s, "Volume")
	testing.expect(t, position)
	testing.expect(t, !volume)
}

@(test)
a_track_that_cannot_play_is_told_each_time :: proc(t: ^testing.T) {
	s: Screen
	speakers := Speakers {
		broken = "1.mp3",
	}
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Could not play “1.mp3”"))
	testing.expect(t, !shows(&s, "Player"))
	// Dismissed, then tried again: told again.
	forget_notice(&s.app)
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Could not play “1.mp3”"))
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Could not play “1.mp3”"))
}

// The player in French, from 1.0.0's catalogue: checked on the catalogue itself, since
// the one in use is shared by every test.
@(test)
the_player_speaks_french :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(t, ui.catalog_tr(&c, "Player"), "Lecteur")
	testing.expect_value(t, ui.catalog_tr(&c, "Previous track"), "Piste précédente")
	testing.expect_value(t, ui.catalog_tr(&c, "Next track"), "Piste suivante")
	testing.expect_value(t, ui.catalog_tr(&c, "Play", "Player"), "Lecture")
	testing.expect_value(t, ui.catalog_tr(&c, "Position"), "Position")
	testing.expect_value(
		t,
		ui.fill(ui.catalog_tr(&c, "Could not play “{}”"), "a.mp3"),
		"Impossible de lire « a.mp3 »",
	)
}

// The bar with a track half played, in both themes.
@(test)
the_player_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		speakers: Speakers
		folder := screen_playing(t, &s, &speakers, {1440, 900}, kind)
		defer remove_folder(folder)
		defer screen_destroy(&s)
		// The folder shows as the home, "~": the same on every platform.
		delete(s.app.home)
		s.app.home = strings.clone(folder)
		ui.press_key(&s.h, .Space)
		s.app.engine.library.tracks[0].metadata.audio.duration = 3 * time.Minute + 24 * time.Second
		speakers.position = 70 * time.Second
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "player-dark.png" : "player-light.png")
	}
}

// The adapter of the audio player to the engine's output answers as the engine expects:
// what plays, where it is, and why a file cannot play.
@(test)
the_output_over_the_player_plays_and_says_why_not :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	output := output_of(player)
	fixture := fmt.tprintf("%s/cbr_stereo.mp3", FIXTURES)
	testing.expect_value(t, output.play(output.data, fixture), engine.Play_Error.None)
	output.pause(output.data)
	testing.expect_value(
		t,
		output.seek(output.data, 300 * time.Millisecond),
		engine.Play_Error.None,
	)
	testing.expect(t, output.position(output.data) >= 299 * time.Millisecond)
	testing.expect(t, !output.finished(output.data))
	output.set_volume(output.data, 0.5)
	testing.expect_value(t, output.seek(output.data, time.Hour), engine.Play_Error.Cannot_Seek)
	output.stop(output.data)
	testing.expect_value(t, output.position(output.data), time.Duration(0))
	missing := fmt.tprintf("%s/does_not_exist.mp3", FIXTURES)
	testing.expect_value(t, output.play(output.data, missing), engine.Play_Error.Cannot_Open)
	text := fmt.tprintf("%s/../README.md", FIXTURES)
	testing.expect_value(t, output.play(output.data, text), engine.Play_Error.Cannot_Decode)
}

// Tab goes from the left to the right: the buttons, the position, the volume; Space on
// the play button pauses.
@(test)
the_bar_is_reached_by_the_keyboard_from_left_to_right :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	player, _ := ui.find_widget(&s.h.ui, "Player")
	order := make([dynamic]string, context.temp_allocator)
	for w in s.h.ui.widgets do if w.parent == player.id && w.focusable do append(&order, w.label)
	testing.expect_value(t, len(order), 5)
	expected := [?]string{"Previous track", "Pause", "Next track", "Position", "Volume"}
	for label, i in expected do if i < len(order) do testing.expect_value(t, order[i], label)
	// From the first button, Tab reaches the play button, and Space presses it.
	ui.request_focus(&s.h.ui, ui.child_id(player.id, "previous"), by_key = true)
	ui.ui_end_frame(&s.h.ui)
	ui.run_frame(&s.h)
	ui.press_key(&s.h, .Tab)
	ui.run_frame(&s.h)
	info, _ := ui.find_widget(&s.h.ui, "Pause")
	testing.expect(t, .Focused in info.states)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, speakers.paused)
}

@(test)
the_bar_goes_when_the_last_track_ends :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Next track"))
	ui.run_frame(&s.h)
	testing.expect_value(t, speakers.playing, "2.mp3")
	// The second, the last, plays to its end: nothing is left to play.
	speakers.finished = true
	engine.poll(&s.app.engine)
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Player"))
	testing.expect_value(t, s.app.engine.playback.track, nil)
}

// A track without a duration shows how far it has played, and has nothing to seek in.
@(test)
a_track_without_a_duration_shows_its_position_and_cannot_be_seeked :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.app.engine.library.tracks[0].metadata.audio.duration = 0
	ui.press_key(&s.h, .Space)
	speakers.position = 5 * time.Second
	ui.run_frame(&s.h)
	_, advanced := in_player(&s, "0:05")
	testing.expect(t, advanced)
	position, found := in_player(&s, "Position")
	testing.expect(t, found && .Disabled in position.states)
}

// A click at the very end seeks to a little before it: a position the decoder does not
// reach ends the track.
@(test)
a_seek_to_the_end_stops_a_little_before_it :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.app.engine.library.tracks[0].metadata.audio.duration = 10 * time.Second
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	position, _ := in_player(&s, "Position")
	ui.move_mouse(&s.h, {position.rect.x + position.rect.w - 1, position.rect.y + 8})
	ui.press(&s.h)
	ui.release(&s.h)
	testing.expect(t, speakers.position > 9 * time.Second)
	testing.expect(t, speakers.position <= 10 * time.Second - SEEK_MARGIN)
}

// A toast shows above the bar, not over it.
@(test)
a_toast_stays_above_the_bar :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	ui.press_key(&s.h, .Space)
	ui.run_frame(&s.h)
	notify(&s.app, .Success, "Saved 1 file", nil, s.h.ui.input.time)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	toast, has_toast := ui.find_widget(&s.h.ui, "Saved 1 file")
	player, has_player := ui.find_widget(&s.h.ui, "Player")
	if !testing.expect(t, has_toast && has_player) do return
	testing.expect(t, toast.rect.y + toast.rect.h <= player.rect.y)
}

// An hour of a track, "1:02:03", does not run into what lies beside it.
@(test)
long_times_do_not_run_into_the_bars :: proc(t: ^testing.T) {
	s: Screen
	speakers: Speakers
	folder := screen_playing(t, &s, &speakers)
	defer remove_folder(folder)
	defer screen_destroy(&s)
	s.app.engine.library.tracks[0].metadata.audio.duration = 10 * time.Hour + 2 * time.Minute
	ui.press_key(&s.h, .Space)
	speakers.position = time.Hour + 2 * time.Minute + 3 * time.Second
	ui.run_frame(&s.h)
	position_text, has_text := in_player(&s, "1:02:03")
	duration_text, has_duration := in_player(&s, "10:02:00")
	position, has_position := in_player(&s, "Position")
	if !testing.expect(t, has_text && has_duration && has_position) do return
	testing.expect(t, position_text.rect.x + position_text.rect.w <= position.rect.x)
	testing.expect(t, position.rect.x + position.rect.w <= duration_text.rect.x)
	volume, _ := in_player(&s, "Volume")
	testing.expect(t, duration_text.rect.x + duration_text.rect.w <= volume.rect.x)
}
