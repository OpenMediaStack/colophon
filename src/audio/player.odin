package audio

import "base:runtime"
import "core:sync"
import "core:time"

import ma "vendor:miniaudio"

// Why a file could not be played or reached.
Error :: enum u8 {
	None,
	// The file could not be opened.
	Cannot_Open,
	// The file is not audio that can be decoded.
	Cannot_Decode,
	// The position could not be reached.
	Cannot_Seek,
	// There is no sound device to play through.
	No_Device,
	// The work was stopped before it ended.
	Cancelled,
}

// Plays one file at a time through the system's speakers, decoded by miniaudio on its
// audio thread. Make it with make_player and free it with destroy_player: it must not
// move once made, since the audio thread holds its address. Its procedures may be
// called from any thread but not from the audio thread, which only the player runs.
//
// The audio thread decodes under a mutex that opening a file and seeking also hold. It
// never waits for it: while a caller holds it, the speakers get silence for that
// moment, so a slow seek (an MP3 has no index: it decodes up to the position, which
// grows with it) is heard as a gap, and stalls the caller that asked.
Player :: struct {
	context_:    ma.context_type,
	// Whether context_ was made, for a player on a given backend.
	has_context: bool,
	device:      ma.device,
	decoder:     ma.decoder,
	// The bytes of the file the decoder reads, while one is loaded: the file itself is
	// closed as soon as it is read (see open_decoder).
	data:        []byte,
	// The frames the device asks for a second, and its channels: the decoder converts
	// the file to them.
	rate:        u32,
	channels:    u32,
	// What the audio thread and the callers share: held for the whole of a read of the
	// decoder, a seek, a change of file.
	mutex:       sync.Mutex,
	loaded:      bool,
	paused:      bool,
	// The frames played of the file, and whether it has played to its end: read without
	// the mutex.
	frames:      u64,
	done:        bool,
	allocator:   runtime.Allocator,
}

// A player on the system's default speakers, or, with silent, on a device that plays
// nothing and keeps time, for tests and machines without a sound card. No_Device when
// there is none.
make_player :: proc(silent := false, allocator := context.allocator) -> (p: ^Player, err: Error) {
	made, new_err := new(Player, allocator)
	if new_err != nil do return nil, .No_Device
	p = made
	p.allocator = allocator
	if silent {
		backends := [?]ma.backend{.null}
		if ma.context_init(raw_data(backends[:]), 1, nil, &p.context_) != .SUCCESS {
			free(p, allocator)
			return nil, .No_Device
		}
		p.has_context = true
	}
	config := ma.device_config_init(.playback)
	config.playback.format = .f32
	config.playback.channels = 2
	// A music player has no need of the shortest periods: fewer, longer ones.
	config.performanceProfile = .conservative
	config.dataCallback = on_data
	config.pUserData = p
	if ma.device_init(&p.context_ if p.has_context else nil, &config, &p.device) != .SUCCESS {
		if p.has_context do ma.context_uninit(&p.context_)
		free(p, allocator)
		return nil, .No_Device
	}
	p.rate = p.device.sampleRate
	p.channels = p.device.playback.channels
	return p, .None
}

// Stops the sound and frees the player.
destroy_player :: proc(p: ^Player) {
	if p == nil do return
	ma.device_uninit(&p.device)
	if p.loaded do close_decoder(&p.decoder, p.data, p.allocator)
	if p.has_context do ma.context_uninit(&p.context_)
	free(p, p.allocator)
}

@(private = "file")
on_data :: proc "c" (device: ^ma.device, output, input: rawptr, frame_count: u32) {
	context = runtime.default_context()
	p := (^Player)(device.pUserData)
	// The buffer starts silent, and stays so while nothing plays, or while a caller
	// holds the mutex: the audio thread never waits for it.
	if !sync.mutex_try_lock(&p.mutex) do return
	defer sync.mutex_unlock(&p.mutex)
	if !p.loaded || p.paused do return
	read: u64
	_ = ma.decoder_read_pcm_frames(&p.decoder, output, u64(frame_count), &read)
	sync.atomic_add(&p.frames, read)
	if read < u64(frame_count) do sync.atomic_store(&p.done, true)
}

// Unloads the file, if one is loaded, and forgets how far it had played. The mutex is
// held.
@(private = "file")
unload :: proc(p: ^Player) {
	if p.loaded do close_decoder(&p.decoder, p.data, p.allocator)
	p.data = nil
	p.loaded, p.paused = false, false
	sync.atomic_store(&p.frames, 0)
	sync.atomic_store(&p.done, false)
}

// Plays the file at path from its start, in place of what played. It reads the whole
// file into memory on the calling thread, and probes its first frames: a file that is
// not audio can take a while to be refused. The file is closed again at once. Cannot_Open
// when the file cannot be read, Cannot_Decode when it is not audio or is over half a
// gigabyte.
play_file :: proc(p: ^Player, path: string) -> Error {
	if sync.mutex_guard(&p.mutex) {
		unload(p)
		config := ma.decoder_config_init(.f32, p.channels, p.rate)
		data, err := open_decoder(path, &config, &p.decoder, p.allocator)
		if err != .None do return err
		p.data, p.loaded = data, true
	}
	// Outside the mutex: starting waits for the audio thread, which takes it.
	if !ma.device_is_started(&p.device) && ma.device_start(&p.device) != .SUCCESS do return .No_Device
	return .None
}

// Holds the sound where it is.
pause_player :: proc(p: ^Player) {
	if sync.mutex_guard(&p.mutex) do p.paused = true
}

// Goes on from where the sound was held.
resume_player :: proc(p: ^Player) {
	if sync.mutex_guard(&p.mutex) do p.paused = false
}

// Stops the file: nothing plays and the position goes back to the start.
stop_player :: proc(p: ^Player) {
	if sync.mutex_guard(&p.mutex) do unload(p)
}

// Moves the file to a position, from where the audio thread goes on. A position the
// decoder cannot reach, such as one past the end, leaves the file where it was and gives
// Cannot_Seek. It decodes up to the position (see Player): a long file takes a while.
seek_player :: proc(p: ^Player, position: time.Duration) -> Error {
	if sync.mutex_guard(&p.mutex) {
		if !p.loaded do return .Cannot_Seek
		frame := u64(max(time.duration_seconds(position), 0) * f64(p.rate))
		if ma.decoder_seek_to_pcm_frame(&p.decoder, frame) != .SUCCESS {
			// A seek that failed may have left the decoder at the end: back to where it was.
			_ = ma.decoder_seek_to_pcm_frame(&p.decoder, sync.atomic_load(&p.frames))
			return .Cannot_Seek
		}
		sync.atomic_store(&p.frames, frame)
		sync.atomic_store(&p.done, false)
	}
	return .None
}

// How far the file has played, as the speakers have asked for it.
player_position :: proc(p: ^Player) -> time.Duration {
	frames := sync.atomic_load(&p.frames)
	return time.Duration(f64(frames) / f64(max(p.rate, 1)) * f64(time.Second))
}

// Whether the file has played to its end.
player_finished :: proc(p: ^Player) -> bool {
	return sync.atomic_load(&p.done)
}

// From 0, silent, to 1, as loud as the file.
set_player_volume :: proc(p: ^Player, volume: f32) {
	_ = ma.device_set_master_volume(&p.device, clamp(volume, 0, 1))
}
