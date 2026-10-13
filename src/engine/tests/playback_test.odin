package engine_tests

import "core:path/filepath"
import "core:testing"
import "core:time"

import "../../engine"

// What the fake output was asked, and what it says.
@(private = "file")
Speakers :: struct {
	playing:  string,
	paused:   bool,
	position: time.Duration,
	finished: bool,
	volume:   f32,
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
	s.playing = filepath.base(path)
	s.paused = false
	s.position = 0
	s.finished = false
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

// An engine playing through s, over a.mp3, b.mp3 and c.mp3.
@(private = "file")
engine_playing :: proc(t: ^testing.T, e: ^engine.Engine, s: ^Speakers) -> string {
	folder := folder_with(t, {"a.mp3", "b.mp3", "c.mp3"})
	engine_reading(t, e, folder)
	e.output = fake_output(s)
	return folder
}

@(test)
a_track_plays_pauses_and_resumes :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Play{1})
	testing.expect_value(t, s.playing, "b.mp3")
	testing.expect(t, engine.playing(e.playback))

	engine.execute(&e, engine.Play_Pause{})
	testing.expect(t, s.paused)
	testing.expect(t, !engine.playing(e.playback))

	engine.execute(&e, engine.Play_Pause{})
	testing.expect(t, !s.paused)
}

@(test)
play_pause_with_nothing_playing_plays_the_focused_track :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{2})

	engine.execute(&e, engine.Play_Pause{})

	testing.expect_value(t, s.playing, "c.mp3")
}

@(test)
the_next_track_is_the_next_the_table_lists :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Sort_By{.File})
	engine.execute(&e, engine.Sort_By{.File})
	engine.execute(&e, engine.Play{2})

	engine.execute(&e, engine.Play_Next{})
	testing.expect_value(t, s.playing, "b.mp3")

	s.finished = true
	testing.expect(t, engine.poll(&e))
	testing.expect_value(t, s.playing, "a.mp3")

	s.finished = true
	engine.poll(&e)
	testing.expect_value(t, s.playing, "")
	testing.expect_value(t, e.playback.track, nil)
}

@(test)
previous_starts_the_track_again_once_it_has_played_a_while :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{1})

	engine.execute(&e, engine.Seek{10 * time.Second})
	engine.execute(&e, engine.Play_Previous{})
	testing.expect_value(t, s.playing, "b.mp3")
	testing.expect_value(t, engine.position(&e), 0)

	engine.execute(&e, engine.Play_Previous{})
	testing.expect_value(t, s.playing, "a.mp3")
}

@(test)
a_track_that_cannot_play_is_reported :: proc(t: ^testing.T) {
	e: engine.Engine
	s := Speakers {
		broken = "a.mp3",
	}
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Play{0})

	testing.expect_value(t, e.playback.track, nil)
	failure, failed := e.play_failure.?
	testing.expect(t, failed)
	testing.expect_value(t, failure, engine.Play_Failure{0, .Cannot_Decode})
}

@(test)
the_volume_reaches_the_output :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Set_Volume{25})
	engine.execute(&e, engine.Play{0})

	testing.expect(t, abs(s.volume - 0.25) < 1e-6)
}

@(test)
without_an_output_nothing_plays :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with(t, {"a.mp3"})
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Play{0})

	testing.expect(t, !engine.can_play(&e))
	testing.expect_value(t, e.playback.track, nil)
}

@(test)
playback_commands_keep_the_ids_of_1_0 :: proc(t: ^testing.T) {
	ids := [?][2]string {
		{engine.command_id(engine.Play{}), "playback.play"},
		{engine.command_id(engine.Play_Pause{}), "playback.play_pause"},
		{engine.command_id(engine.Play_Next{}), "playback.next"},
		{engine.command_id(engine.Play_Previous{}), "playback.previous"},
		{engine.command_id(engine.Seek{}), "playback.seek"},
		{engine.command_id(engine.Set_Volume{}), "playback.volume"},
	}
	for id in ids do testing.expect_value(t, id[0], id[1])
}

@(test)
a_position_before_the_start_seeks_to_the_start :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{0})
	s.position = 5 * time.Second

	engine.execute(&e, engine.Seek{-5 * time.Second})

	testing.expect_value(t, s.position, 0)
}

@(test)
a_playing_track_filtered_out_plays_on :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{1})

	engine.execute(&e, engine.Filter{"a.mp3"})
	testing.expect_value(t, s.playing, "b.mp3")
	engine.execute(&e, engine.Play_Previous{})
	testing.expect_value(t, s.playing, "b.mp3")
	engine.execute(&e, engine.Play_Next{})
	testing.expect_value(t, e.playback.track, nil)
}

@(test)
previous_on_the_first_track_starts_it_again :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{0})
	s.position = time.Second

	engine.execute(&e, engine.Play_Previous{})

	testing.expect_value(t, s.playing, "a.mp3")
	testing.expect_value(t, s.position, 0)
}

@(test)
a_paused_track_that_ended_does_not_move_on :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{0})
	engine.execute(&e, engine.Play_Pause{})
	s.finished = true

	testing.expect(t, !engine.poll(&e))

	testing.expect_value(t, s.playing, "a.mp3")
}

@(test)
moving_on_to_a_file_that_cannot_play_stops :: proc(t: ^testing.T) {
	e: engine.Engine
	s := Speakers {
		broken = "b.mp3",
	}
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{0})
	s.finished = true

	engine.poll(&e)

	testing.expect_value(t, e.playback.track, nil)
	testing.expect_value(t, e.play_failure, engine.Play_Failure{1, .Cannot_Decode})
}

@(test)
the_volume_is_kept_in_range_and_restored_to_the_output :: proc(t: ^testing.T) {
	e: engine.Engine
	s: Speakers
	folder := engine_playing(t, &e, &s)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Play{0})

	engine.execute(&e, engine.Set_Volume{500})
	testing.expect_value(t, s.volume, 1)
	engine.execute(&e, engine.Set_Volume{-5})
	testing.expect_value(t, s.volume, 0)
	preferences := engine.DEFAULT_PREFERENCES
	preferences.volume = 40
	engine.restore(&e, preferences)
	testing.expect(t, abs(s.volume - 0.4) < 1e-6)
}
