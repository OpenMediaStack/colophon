package engine

import "core:time"

// Where the engine sends the sound of a track: the system's speakers, or a fake in
// tests. Each procedure gets data, which must outlive the engine's use of it: the app
// stops and frees its player after engine.destroy. The engine calls them from the
// thread that runs execute and poll; a player with an audio thread of its own makes
// position and finished safe to read from there. finished speaks of the file the last
// play started, never of one before it. path is only borrowed for the call.
Output :: struct {
	data:       rawptr,
	// Plays a file from its start, in place of what played.
	play:       proc(data: rawptr, path: string) -> Play_Error,
	pause:      proc(data: rawptr),
	resume:     proc(data: rawptr),
	stop:       proc(data: rawptr),
	seek:       proc(data: rawptr, position: time.Duration) -> Play_Error,
	// How far the file has played.
	position:   proc(data: rawptr) -> time.Duration,
	// The file has played to its end.
	finished:   proc(data: rawptr) -> bool,
	// From 0, silent, to 1, as loud as the file.
	set_volume: proc(data: rawptr, volume: f32),
}

// Why the output could not play a file or reach a position.
Play_Error :: enum u8 {
	None,
	// The file could not be opened.
	Cannot_Open,
	// The file is not audio the output can decode.
	Cannot_Decode,
	// The output could not reach that position.
	Cannot_Seek,
}

// A track that could not play, and why.
Play_Failure :: struct {
	track: Track_Id,
	error: Play_Error,
}

// What plays: a track of the library, playing or paused, and how loud.
Playback :: struct {
	track:  Maybe(Track_Id),
	paused: bool,
	// From 0, silent, to 1, as loud as the file.
	volume: f32,
}

// Nothing plays, at 80 percent.
DEFAULT_PLAYBACK :: Playback {
	volume = 0.8,
}

// Previous plays the track before only within its first seconds; later, it starts
// the playing one again.
@(private = "file")
RESTART_AFTER :: 3 * time.Second

// Plays a track from its start.
Play :: struct {
	track: Track_Id,
}

// Pauses or resumes; with nothing playing, plays the focused track, or the first
// selected, or the first listed.
Play_Pause :: struct {}

// Plays the next track the table lists.
Play_Next :: struct {}

// Plays the track before, or this one again from its start once a few seconds have
// played.
Play_Previous :: struct {}

// Moves the playing track to this position.
Seek :: struct {
	position: time.Duration,
}

// From 0, silent, to 100, as loud as the file.
Set_Volume :: struct {
	percent: int,
}

// Whether a track plays and is not paused.
playing :: proc(p: Playback) -> bool {
	return p.track != nil && !p.paused
}

// Whether the engine has an output to play through.
can_play :: proc(e: ^Engine) -> bool {
	return e.output != nil
}

// How far the playing track has played.
position :: proc(e: ^Engine) -> time.Duration {
	output, ok := e.output.?
	if !ok || e.playback.track == nil do return 0
	return output.position(output.data)
}

@(private)
play :: proc(e: ^Engine, track: Track_Id) {
	output, ok := e.output.?
	if !ok || !has_track(e, track) do return
	if err := output.play(output.data, e.library.tracks[track].path); err != .None {
		stop_playing(e)
		e.play_failure = Play_Failure{track, err}
		return
	}
	output.set_volume(output.data, e.playback.volume)
	e.playback.track = track
	e.playback.paused = false
	e.play_failure = nil
}

@(private)
play_pause :: proc(e: ^Engine) {
	output, ok := e.output.?
	if ok && e.playback.track != nil {
		if e.playback.paused {
			output.resume(output.data)
		} else {
			output.pause(output.data)
		}
		e.playback.paused = !e.playback.paused
		return
	}
	first: Maybe(Track_Id) = e.selection.focus
	if first == nil && len(e.selection.tracks) > 0 do first = e.selection.tracks[0]
	if first == nil && len(e.listed) > 0 do first = e.listed[0]
	if track, found := first.?; found do play(e, track)
}

// The track the table lists step places from the playing one.
@(private = "file")
listed_from_playing :: proc(e: ^Engine, step: int) -> (track: Track_Id, ok: bool) {
	playing := e.playback.track.? or_return
	for listed, place in e.listed {
		if listed != playing do continue
		next := place + step
		if next < 0 || next >= len(e.listed) do return
		return e.listed[next], true
	}
	return
}

@(private)
play_next :: proc(e: ^Engine) {
	if track, ok := listed_from_playing(e, 1); ok {
		play(e, track)
	} else {
		stop_playing(e)
	}
}

@(private)
play_previous :: proc(e: ^Engine) {
	playing, ok := e.playback.track.?
	if !ok do return
	if before, found := listed_from_playing(e, -1); found && position(e) < RESTART_AFTER {
		play(e, before)
	} else {
		play(e, playing)
	}
}

@(private)
seek :: proc(e: ^Engine, to: time.Duration) {
	output, ok := e.output.?
	// A position the decoder cannot reach leaves the track where it was.
	if ok && e.playback.track != nil do _ = output.seek(output.data, max(to, 0))
}

@(private)
set_volume :: proc(e: ^Engine, percent: int) {
	e.playback.volume = f32(clamp(percent, 0, 100)) / 100
	if output, ok := e.output.?; ok do output.set_volume(output.data, e.playback.volume)
}

// Plays the next track once the playing one has played to its end; true when it did.
@(private)
advance_playback :: proc(e: ^Engine) -> bool {
	output, ok := e.output.?
	if !ok || !playing(e.playback) || !output.finished(output.data) do return false
	play_next(e)
	return true
}

@(private = "file")
stop_playing :: proc(e: ^Engine) {
	if output, ok := e.output.?; ok do output.stop(output.data)
	e.playback.track = nil
	e.playback.paused = false
}
