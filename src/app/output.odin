package main

import "core:time"

import "../audio"
import "../engine"

// The engine's output over a player: what the engine asks of the speakers, and what
// the player answers. data is the player, which must outlive the engine's use of the
// output.
output_of :: proc(player: ^audio.Player) -> engine.Output {
	return {
		data = player,
		play = output_play,
		pause = output_pause,
		resume = output_resume,
		stop = output_stop,
		seek = output_seek,
		position = output_position,
		finished = output_finished,
		set_volume = output_set_volume,
	}
}

@(private = "file")
play_error :: proc(err: audio.Error) -> engine.Play_Error {
	switch err {
	case .None:
		return .None
	case .Cannot_Open, .No_Device, .Cancelled:
		return .Cannot_Open
	case .Cannot_Decode:
		return .Cannot_Decode
	case .Cannot_Seek:
		return .Cannot_Seek
	}
	return .None
}

@(private = "file")
output_play :: proc(data: rawptr, path: string) -> engine.Play_Error {
	return play_error(audio.play_file((^audio.Player)(data), path))
}

@(private = "file")
output_pause :: proc(data: rawptr) {
	audio.pause_player((^audio.Player)(data))
}

@(private = "file")
output_resume :: proc(data: rawptr) {
	audio.resume_player((^audio.Player)(data))
}

@(private = "file")
output_stop :: proc(data: rawptr) {
	audio.stop_player((^audio.Player)(data))
}

@(private = "file")
output_seek :: proc(data: rawptr, position: time.Duration) -> engine.Play_Error {
	return play_error(audio.seek_player((^audio.Player)(data), position))
}

@(private = "file")
output_position :: proc(data: rawptr) -> time.Duration {
	return audio.player_position((^audio.Player)(data))
}

@(private = "file")
output_finished :: proc(data: rawptr) -> bool {
	return audio.player_finished((^audio.Player)(data))
}

@(private = "file")
output_set_volume :: proc(data: rawptr, volume: f32) {
	audio.set_player_volume((^audio.Player)(data), volume)
}
