package main

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:thread"

import "../audio"
import "../engine"
import lib "../library"

// The waveform of the playing track: read on a thread of its own as the track starts,
// then drawn as bars. The UI thread asks, polls and draws; the thread decodes the file
// and says it is done, waking the loop. Free it with destroy_waveform_state.
Waveform_State :: struct {
	allocator: runtime.Allocator,
	wake:      lib.Wake,
	// The track whose waveform shows or is being read, nil while nothing plays.
	track:     Maybe(engine.Track_Id),
	reading:   ^Waveform_Reading,
	// Readings asked to stop, until their threads are done and can be freed.
	stopping:  [dynamic]^Waveform_Reading,
	waveform:  Maybe(audio.Waveform),
	// The bars drawn, each from 0 to 1 as loud as the loudest, for this many.
	bars:      [dynamic]f32,
	bars_for:  int,
}

// A file being decoded for its waveform.
@(private = "file")
Waveform_Reading :: struct {
	allocator: runtime.Allocator,
	wake:      lib.Wake,
	path:      string,
	thread:    ^thread.Thread,
	cancelled: bool,
	done:      bool,
	waveform:  audio.Waveform,
	failed:    bool,
}

init_waveform_state :: proc(w: ^Waveform_State, wake: lib.Wake, allocator := context.allocator) {
	w.allocator = allocator
	w.wake = wake
	w.stopping = make([dynamic]^Waveform_Reading, allocator)
	w.bars = make([dynamic]f32, allocator)
}

// Stops what is being read and frees what is held.
destroy_waveform_state :: proc(w: ^Waveform_State) {
	stop_reading(w)
	for reading in w.stopping do free_reading(reading)
	delete(w.stopping)
	forget_waveform(w)
	delete(w.bars)
}

@(private = "file")
read_waveform_thread :: proc(t: ^thread.Thread) {
	reading := (^Waveform_Reading)(t.data)
	waveform, err := audio.read_waveform(reading.path, &reading.cancelled, reading.allocator)
	reading.waveform = waveform
	reading.failed = err != .None
	sync.atomic_store(&reading.done, true)
	if reading.wake.procedure != nil do reading.wake.procedure(reading.wake.data)
}

@(private = "file")
free_reading :: proc(reading: ^Waveform_Reading) {
	thread.join(reading.thread)
	thread.destroy(reading.thread)
	audio.destroy_waveform(&reading.waveform, reading.allocator)
	delete(reading.path, reading.allocator)
	free(reading, reading.allocator)
}

// Asks the reading to stop: it is freed once its thread has ended, without waiting.
@(private = "file")
stop_reading :: proc(w: ^Waveform_State) {
	if w.reading == nil do return
	sync.atomic_store(&w.reading.cancelled, true)
	append(&w.stopping, w.reading)
	w.reading = nil
}

@(private)
forget_waveform :: proc(w: ^Waveform_State) {
	if waveform, has := &w.waveform.?; has do audio.destroy_waveform(waveform, w.allocator)
	w.waveform = nil
	clear(&w.bars)
	w.bars_for = 0
}

// Starts reading the file at path on a thread of its own. Without a thread, the bars
// stay flat and nothing is retried until the track changes.
@(private = "file")
start_reading :: proc(w: ^Waveform_State, path: string) {
	made := thread.create(read_waveform_thread)
	if made == nil do return
	reading := new(Waveform_Reading, w.allocator)
	reading.allocator = w.allocator
	reading.wake = w.wake
	reading.path = strings.clone(path, w.allocator)
	reading.thread = made
	made.data = reading
	thread.start(made)
	w.reading = reading
}

// Follows the playing track: a new one has its waveform read, and a waveform read comes
// in. Call it every frame the player shows, or does not.
follow_waveform :: proc(app: ^App) {
	w := &app.waveform
	e := &app.engine
	// Readings that were stopped are freed once their threads are done.
	for i := len(w.stopping) - 1; i >= 0; i -= 1 {
		if sync.atomic_load(&w.stopping[i].done) {
			free_reading(w.stopping[i])
			unordered_remove(&w.stopping, i)
		}
	}
	playing := e.playback.track if engine.can_play(e) else nil
	if playing != w.track {
		stop_reading(w)
		forget_waveform(w)
		w.track = playing
		if track, has := playing.?; has && int(track) < len(e.library.tracks) {
			start_reading(w, e.library.tracks[track].path)
		}
	}
	if w.reading != nil && sync.atomic_load(&w.reading.done) {
		reading := w.reading
		w.reading = nil
		if !reading.failed do w.waveform = reading.waveform
		reading.waveform = {}
		free_reading(reading)
		w.bars_for = 0
	}
}

// The bars to draw for count: how loud each share of the track sounds beside the
// loudest, from 0 to 1; flat until the waveform is read. Made again only when the count
// or the waveform changes.
waveform_bars :: proc(w: ^Waveform_State, count: int) -> []f32 {
	if w.bars_for == count && len(w.bars) == max(count, 0) do return w.bars[:]
	w.bars_for = count
	_ = runtime.resize_dynamic_array(&w.bars, max(count, 0))
	for &bar in w.bars do bar = 0
	if waveform, has := &w.waveform.?; has && count > 0 {
		peaks := audio.peaks(waveform, count, context.temp_allocator)
		loudest: f32
		for peak in peaks do loudest = max(loudest, audio.loudness(peak))
		if loudest > 0 {
			for peak, i in peaks[:min(len(peaks), len(w.bars))] do w.bars[i] = audio.loudness(peak) / loudest
		}
	}
	return w.bars[:]
}
