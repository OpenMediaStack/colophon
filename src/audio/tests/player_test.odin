package audio_tests

import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"

import ma "vendor:miniaudio"

import audio ".."

TESTDATA :: #directory + "/../../../testdata"

@(private = "file")
fixture :: proc(name: string) -> string {
	return fmt.tprintf("%s/%s", TESTDATA, name)
}

// How long a test waits for the audio thread, which runs in real time.
@(private = "file")
PATIENCE :: 3 * time.Second

@(private = "file")
wait_until :: proc(until: proc(p: ^audio.Player) -> bool, p: ^audio.Player) -> bool {
	start := time.tick_now()
	for !until(p) {
		if time.tick_since(start) > PATIENCE do return false
		time.sleep(5 * time.Millisecond)
	}
	return true
}

@(private = "file")
has_played :: proc(p: ^audio.Player) -> bool {
	return audio.player_position(p) > 100 * time.Millisecond
}

@(private = "file")
has_finished :: proc(p: ^audio.Player) -> bool {
	return audio.player_finished(p)
}

@(test)
a_file_plays_pauses_and_goes_on :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.player_position(player), time.Duration(0))
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	testing.expect(t, wait_until(has_played, player))
	audio.pause_player(player)
	time.sleep(50 * time.Millisecond)
	held := audio.player_position(player)
	time.sleep(100 * time.Millisecond)
	testing.expect_value(t, audio.player_position(player), held)
	audio.resume_player(player)
	start := time.tick_now()
	for audio.player_position(player) <= held && time.tick_since(start) < PATIENCE {
		time.sleep(5 * time.Millisecond)
	}
	testing.expect(t, audio.player_position(player) > held)
	audio.stop_player(player)
	testing.expect_value(t, audio.player_position(player), time.Duration(0))
	testing.expect(t, !audio.player_finished(player))
}

@(test)
a_file_played_to_its_end_says_so :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	waveform, read_err := audio.read_waveform(fixture("cbr_stereo.mp3"))
	defer audio.destroy_waveform(&waveform)
	testing.expect_value(t, read_err, audio.Error.None)
	// Near the end: the last moments play out.
	near_end := waveform.duration - 80 * time.Millisecond
	testing.expect_value(t, audio.seek_player(player, near_end), audio.Error.None)
	testing.expect(t, audio.player_position(player) >= near_end - time.Millisecond)
	testing.expect(t, wait_until(has_finished, player))
	// Playing again starts from the start, and is not finished.
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	testing.expect(t, !audio.player_finished(player))
	testing.expect(t, audio.player_position(player) < near_end)
}

@(test)
seeking_moves_the_position_and_a_stopped_player_cannot_seek :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.seek_player(player, time.Second), audio.Error.Cannot_Seek)
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	audio.pause_player(player)
	testing.expect_value(t, audio.seek_player(player, 300 * time.Millisecond), audio.Error.None)
	position := audio.player_position(player)
	testing.expect(t, position >= 299 * time.Millisecond && position <= 301 * time.Millisecond)
	// A negative position is the start.
	testing.expect_value(t, audio.seek_player(player, -time.Second), audio.Error.None)
	testing.expect_value(t, audio.player_position(player), time.Duration(0))
}

@(test)
files_that_cannot_play_say_why :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(
		t,
		audio.play_file(player, fixture("does_not_exist.mp3")),
		audio.Error.Cannot_Open,
	)
	folder, folder_err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, folder_err == nil)
	defer delete(folder)
	defer os.remove_all(folder)
	path := fmt.tprintf("%s/not_audio.mp3", folder)
	testing.expect(
		t,
		os.write_entire_file(path, transmute([]u8)string("this is not audio at all")) == nil,
	)
	testing.expect_value(t, audio.play_file(player, path), audio.Error.Cannot_Decode)
	// A good file plays after the failures.
	testing.expect_value(t, audio.play_file(player, fixture("vbr_mono.mp3")), audio.Error.None)
	volume: f32
	audio.set_player_volume(player, 0.3)
	_ = ma.device_get_master_volume(&player.device, &volume)
	testing.expect_value(t, volume, 0.3)
	audio.set_player_volume(player, 7)
	_ = ma.device_get_master_volume(&player.device, &volume)
	testing.expect_value(t, volume, 1)
}

@(test)
a_waveform_is_read_from_a_fixture :: proc(t: ^testing.T) {
	for name in ([?]string{"cbr_stereo.mp3", "vbr_mono.mp3", "v23_full.mp3"}) {
		waveform, err := audio.read_waveform(fixture(name))
		testing.expectf(t, err == .None, "%s: %v", name, err)
		testing.expectf(t, waveform.duration > 0, "%s has no duration", name)
		peaks := audio.peaks(&waveform, 50)
		testing.expect_value(t, len(peaks), 50)
		delete(peaks)
		audio.destroy_waveform(&waveform)
	}
	_, missing := audio.read_waveform(fixture("does_not_exist.mp3"))
	testing.expect_value(t, missing, audio.Error.Cannot_Open)
}

@(test)
reading_a_waveform_can_be_cancelled :: proc(t: ^testing.T) {
	cancelled := true
	_, err := audio.read_waveform(fixture("cbr_stereo.mp3"), &cancelled)
	testing.expect_value(t, err, audio.Error.Cancelled)
}

// Truncated and mutated files give a waveform of what decodes, or an error, never a
// panic or a hang.
@(test)
damaged_files_do_not_stop_the_reading :: proc(t: ^testing.T) {
	whole, read_err := os.read_entire_file(fixture("cbr_stereo.mp3"), context.allocator)
	testing.expect(t, read_err == nil)
	defer delete(whole)
	folder, folder_err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, folder_err == nil)
	defer delete(folder)
	defer os.remove_all(folder)
	path := fmt.tprintf("%s/damaged.mp3", folder)
	for length in ([?]int{0, 1, 4, 100, 417, 1000, 9000, 17000}) {
		testing.expect(t, os.write_entire_file(path, whole[:length]) == nil)
		waveform, _ := audio.read_waveform(path)
		audio.destroy_waveform(&waveform)
	}
	mutated := make([]u8, len(whole), context.allocator)
	defer delete(mutated)
	for seed in 0 ..< 20 {
		copy(mutated, whole)
		for i := seed; i < len(mutated); i += 97 + seed do mutated[i] ~= u8(seed * 37 + 11)
		testing.expect(t, os.write_entire_file(path, mutated) == nil)
		waveform, _ := audio.read_waveform(path)
		audio.destroy_waveform(&waveform)
	}
}

// A seek the decoder cannot make leaves the file where it was and playing on, not at
// its end.
@(test)
a_seek_past_the_end_leaves_the_file_where_it_was :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	audio.pause_player(player)
	testing.expect_value(t, audio.seek_player(player, 220 * time.Millisecond), audio.Error.None)
	testing.expect_value(t, audio.seek_player(player, time.Hour), audio.Error.Cannot_Seek)
	position := audio.player_position(player)
	testing.expect(t, position >= 219 * time.Millisecond && position <= 221 * time.Millisecond)
	audio.resume_player(player)
	// Long enough for a decoder left at the end to say so, and not for the file to end.
	time.sleep(300 * time.Millisecond)
	testing.expect(t, !audio.player_finished(player))
	testing.expect(t, audio.player_position(player) > position)
}

// A new file in place of the playing one, and a file after a stop, start from the start
// with nothing left of the other; a failed play leaves nothing of it either.
@(test)
a_new_file_starts_clean :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	testing.expect(t, wait_until(has_played, player))
	testing.expect_value(t, audio.play_file(player, fixture("vbr_mono.mp3")), audio.Error.None)
	testing.expect(t, audio.player_position(player) < 100 * time.Millisecond)
	testing.expect(t, wait_until(has_played, player))
	audio.stop_player(player)
	testing.expect_value(t, audio.play_file(player, fixture("cbr_stereo.mp3")), audio.Error.None)
	testing.expect(t, audio.player_position(player) < 100 * time.Millisecond)
	testing.expect(t, wait_until(has_played, player))
	testing.expect_value(
		t,
		audio.play_file(player, fixture("does_not_exist.mp3")),
		audio.Error.Cannot_Open,
	)
	testing.expect_value(t, audio.player_position(player), time.Duration(0))
	testing.expect(t, !audio.player_finished(player))
}

// Saving a file that is playing writes a copy and renames it over the file: the file
// must not be held open in a way that forbids it, as Windows would if it were.
@(test)
a_playing_file_can_be_replaced :: proc(t: ^testing.T) {
	folder, folder_err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, folder_err == nil)
	defer delete(folder)
	defer os.remove_all(folder)
	playing := fmt.tprintf("%s/playing.mp3", folder)
	other := fmt.tprintf("%s/other.mp3", folder)
	testing.expect(t, os.copy_file(playing, fixture("cbr_stereo.mp3")) == nil)
	testing.expect(t, os.copy_file(other, fixture("vbr_mono.mp3")) == nil)
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.play_file(player, playing), audio.Error.None)
	testing.expect(t, wait_until(has_played, player))
	// While it plays, and again while a waveform of it is read.
	testing.expect(t, os.rename(other, playing) == nil)
	testing.expect(t, os.copy_file(other, fixture("cbr_stereo.mp3")) == nil)
	testing.expect(t, os.rename(other, playing) == nil)
	testing.expect_value(t, audio.player_finished(player), false)
}

// Names with spaces and characters outside ASCII open on every system, which the
// Windows call through wide characters is what this checks there.
@(test)
a_file_with_a_name_outside_ascii_plays_and_reads :: proc(t: ^testing.T) {
	folder, folder_err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, folder_err == nil)
	defer delete(folder)
	defer os.remove_all(folder)
	path := fmt.tprintf("%s/café 日本語.mp3", folder)
	testing.expect(t, os.copy_file(path, fixture("cbr_stereo.mp3")) == nil)
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	testing.expect_value(t, audio.play_file(player, path), audio.Error.None)
	waveform, read_err := audio.read_waveform(path)
	defer audio.destroy_waveform(&waveform)
	testing.expect_value(t, read_err, audio.Error.None)
	testing.expect(t, waveform.duration > 0)
}

// Truncated and mutated files give an error or a sound, never a panic or a hang, on the
// way to the speakers as on the way to a waveform.
@(test)
damaged_files_do_not_stop_the_player :: proc(t: ^testing.T) {
	player, err := audio.make_player(silent = true)
	if !testing.expect_value(t, err, audio.Error.None) do return
	defer audio.destroy_player(player)
	whole, read_err := os.read_entire_file(fixture("cbr_stereo.mp3"), context.allocator)
	testing.expect(t, read_err == nil)
	defer delete(whole)
	folder, folder_err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, folder_err == nil)
	defer delete(folder)
	defer os.remove_all(folder)
	path := fmt.tprintf("%s/damaged.mp3", folder)
	for length in ([?]int{0, 1, 4, 100, 417, 1000, 9000, min(17000, len(whole))}) {
		testing.expect(t, os.write_entire_file(path, whole[:length]) == nil)
		_ = audio.play_file(player, path)
		_ = audio.seek_player(player, 100 * time.Millisecond)
		audio.pause_player(player)
		audio.resume_player(player)
	}
	mutated := make([]u8, len(whole), context.allocator)
	defer delete(mutated)
	for seed in 0 ..< 20 {
		copy(mutated, whole)
		for i := seed; i < len(mutated); i += 97 + seed do mutated[i] ~= u8(seed * 37 + 11)
		testing.expect(t, os.write_entire_file(path, mutated) == nil)
		_ = audio.play_file(player, path)
		_ = audio.seek_player(player, 100 * time.Millisecond)
	}
}
