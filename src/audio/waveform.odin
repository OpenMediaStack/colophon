// How loud a track is over its length, for the waveform of the player.
package audio

import "base:runtime"
import "core:math"
import "core:time"

// The frames of a slice of the finest resolution.
@(private)
FRAMES_PER_PEAK :: 256

// The lowest and the highest sample of a slice, from -1 to 1, and what tells how loud
// it sounds. Merge peaks with merge_peaks; read the loudness with loudness. squares and
// frames are the parts of the loudness that merge.
Peak :: struct {
	low:     f32,
	high:    f32,
	// The sum of the squares of its samples, and how many there are.
	squares: f64,
	frames:  u32,
}

// A track's peaks, finest first, each level half as many as the one before. Free it
// with destroy_waveform.
Waveform :: struct {
	levels:   [][]Peak,
	// How many frames the peaks cover.
	frames:   u64,
	duration: time.Duration,
}

// What a track's peaks are made of while its samples arrive, in chunks of any size.
// Make it with init_waveform_builder, feed it with push_samples, and take the waveform
// with finish_waveform.
Waveform_Builder :: struct {
	channels:  int,
	rate:      int,
	finest:    [dynamic]Peak,
	// The peak being made, how many frames it holds so far.
	current:   Peak,
	in_peak:   int,
	// The frame being made: its samples' sum, and how many samples it holds so far.
	sum:       f32,
	in_frame:  int,
	frames:    u64,
	allocator: runtime.Allocator,
}

// A builder for interleaved samples of channels channels at rate frames per second.
// Fewer than one channel or one frame per second count as one. The builder allocates
// with allocator: finish it with finish_waveform, or free it with
// destroy_waveform_builder.
init_waveform_builder :: proc(
	b: ^Waveform_Builder,
	channels, rate: int,
	allocator := context.allocator,
) {
	b^ = {
		channels  = max(channels, 1),
		rate      = max(rate, 1),
		finest    = make([dynamic]Peak, allocator),
		allocator = allocator,
	}
}

// Frees a builder that was not finished.
destroy_waveform_builder :: proc(b: ^Waveform_Builder) {
	delete(b.finest)
	b^ = {}
}

// Takes in interleaved samples, all channels mixed into one. A frame may be split
// between two calls. A sample that is not a number counts as silence and one beyond
// -1 or 1 is brought back to it, so that the peaks of a damaged decoder's output are
// always finite, from -1 to 1.
push_samples :: proc(b: ^Waveform_Builder, samples: []f32) {
	for sample in samples {
		b.sum += sample
		b.in_frame += 1
		if b.in_frame < b.channels do continue
		value := b.sum / f32(b.channels)
		value = 0 if math.is_nan(value) else clamp(value, -1, 1)
		b.sum, b.in_frame = 0, 0
		b.frames += 1
		peak := Peak {
			low     = value,
			high    = value,
			squares = f64(value) * f64(value),
			frames  = 1,
		}
		b.current = peak if b.in_peak == 0 else merge_peaks(b.current, peak)
		b.in_peak += 1
		if b.in_peak == FRAMES_PER_PEAK do close_peak(b)
	}
}

@(private = "file")
close_peak :: proc(b: ^Waveform_Builder) {
	append(&b.finest, b.current)
	b.current, b.in_peak = {}, 0
}

// The waveform of the samples taken in, with its coarser levels, and the builder is
// spent. The waveform is the caller's: free it with destroy_waveform.
finish_waveform :: proc(b: ^Waveform_Builder) -> Waveform {
	if b.in_peak > 0 do close_peak(b)
	allocator := b.allocator
	levels := make([dynamic][]Peak, allocator)
	append(&levels, b.finest[:])
	for len(levels[len(levels) - 1]) > 1 {
		finer := levels[len(levels) - 1]
		coarser := make([]Peak, (len(finer) + 1) / 2, allocator)
		for i in 0 ..< len(coarser) {
			pair := finer[2 * i:min(2 * i + 2, len(finer))]
			coarser[i] = pair[0]
			for other in pair[1:] do coarser[i] = merge_peaks(coarser[i], other)
		}
		append(&levels, coarser)
	}
	waveform := Waveform {
		levels   = levels[:],
		frames   = b.frames,
		duration = time.Duration(math.round(f64(b.frames) * f64(time.Second) / f64(b.rate))),
	}
	b^ = {}
	return waveform
}

// The peaks of interleaved samples of channels channels, all channels mixed, at rate
// frames per second. Free the waveform with destroy_waveform.
waveform_from_samples :: proc(
	samples: []f32,
	channels, rate: int,
	allocator := context.allocator,
) -> Waveform {
	b: Waveform_Builder
	init_waveform_builder(&b, channels, rate, allocator)
	push_samples(&b, samples)
	return finish_waveform(&b)
}

// Frees a waveform made with finish_waveform or waveform_from_samples, with the
// allocator its builder was given.
destroy_waveform :: proc(w: ^Waveform, allocator := context.allocator) {
	for level in w.levels do delete(level, allocator)
	delete(w.levels, allocator)
	w^ = {}
}

// The lowest and highest of two peaks, with their loudness taken together.
@(private)
merge_peaks :: proc(a, b: Peak) -> Peak {
	return {
		low = min(a.low, b.low),
		high = max(a.high, b.high),
		squares = a.squares + b.squares,
		frames = a.frames + min(b.frames, max(u32) - a.frames),
	}
}

// How loud a slice sounds: the root mean square of its samples, from 0 to 1.
loudness :: proc(p: Peak) -> f32 {
	if p.frames == 0 do return 0
	return f32(math.sqrt(p.squares / f64(p.frames)))
}

// count peaks across the whole track, each from the frames of its share of the track,
// read from the coarsest level whose peaks are no longer than an eighth of a share, so
// that a share takes in little of its neighbours. Empty for an empty track or no
// count, or when there is no room for that many. Allocated with allocator: free it with
// delete(peaks, allocator).
peaks :: proc(w: ^Waveform, count: int, allocator := context.allocator) -> []Peak {
	if count <= 0 || w.frames == 0 || len(w.levels) == 0 do return nil
	share := w.frames / u64(count)
	level := 0
	#reverse for _, i in w.levels {
		if u64(FRAMES_PER_PEAK) << uint(i) <= max(share / 8, 1) {
			level = i
			break
		}
	}
	span := u64(FRAMES_PER_PEAK) << uint(level)
	finer := w.levels[level]
	result, err := make([]Peak, count, allocator)
	if err != nil do return nil
	for bar in 0 ..< count {
		start := u64(bar) * w.frames / u64(count)
		end := u64(bar + 1) * w.frames / u64(count)
		first := min(int(start / span), len(finer) - 1)
		last := min(max(int((end + span - 1) / span), first + 1), len(finer))
		merged := finer[first]
		for other in finer[first + 1:last] do merged = merge_peaks(merged, other)
		result[bar] = merged
	}
	return result
}
