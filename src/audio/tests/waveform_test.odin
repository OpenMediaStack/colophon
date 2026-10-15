package audio_tests

import "core:math"
import "core:testing"
import "core:time"

import audio ".."

@(private = "file")
sine :: proc(frames: int, amplitude: f32, step: f32) -> []f32 {
	samples := make([]f32, frames, context.temp_allocator)
	for i in 0 ..< frames do samples[i] = amplitude * math.sin(f32(i) * step)
	return samples
}

@(test)
a_sine_peaks_at_its_amplitude_whatever_the_width :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	waveform := audio.waveform_from_samples(sine(44_100, 0.5, 0.5), 1, 44_100)
	defer audio.destroy_waveform(&waveform)
	for count in ([?]int{1, 7, 100, 1000}) {
		peaks := audio.peaks(&waveform, count)
		defer delete(peaks)
		testing.expect_value(t, len(peaks), count)
		for peak in peaks {
			testing.expect(t, peak.high > 0.45 && peak.low < -0.45)
		}
	}
	testing.expect_value(t, waveform.duration, time.Second)
}

@(test)
channels_are_mixed_and_silence_stays_flat :: proc(t: ^testing.T) {
	samples := make([]f32, 2000, context.temp_allocator)
	defer free_all(context.temp_allocator)
	for i in 0 ..< 1000 {
		samples[2 * i] = 0.8
		samples[2 * i + 1] = -0.8
	}
	waveform := audio.waveform_from_samples(samples, 2, 1000)
	defer audio.destroy_waveform(&waveform)
	peaks := audio.peaks(&waveform, 4)
	defer delete(peaks)
	for peak in peaks {
		testing.expect(t, abs(peak.high) < 1e-6 && abs(peak.low) < 1e-6)
	}
	testing.expect_value(t, waveform.duration, time.Second)
}

@(test)
a_loud_moment_shows_where_it_is :: proc(t: ^testing.T) {
	samples := make([]f32, 10_000, context.temp_allocator)
	defer free_all(context.temp_allocator)
	for i in 5000 ..< 5100 do samples[i] = 1
	waveform := audio.waveform_from_samples(samples, 1, 10_000)
	defer audio.destroy_waveform(&waveform)
	peaks := audio.peaks(&waveform, 10)
	defer delete(peaks)
	loudest := 0
	// The last of equal peaks: the slices around a moment lend each other a little.
	for peak, bar in peaks do if peak.high >= peaks[loudest].high do loudest = bar
	testing.expect_value(t, loudest, 5)
}

@(test)
loudness_is_the_root_mean_square :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	samples := make([]f32, 88_200, context.temp_allocator)
	for i in 0 ..< 44_100 {
		samples[i] = 0.5 * math.sin(math.TAU * 440 * f32(i) / 44_100)
	}
	waveform := audio.waveform_from_samples(samples, 1, 44_100)
	defer audio.destroy_waveform(&waveform)
	halves := audio.peaks(&waveform, 2)
	defer delete(halves)
	// A sine's root mean square is its amplitude over the square root of two.
	testing.expect(t, abs(audio.loudness(halves[0]) - 0.5 / math.sqrt(f32(2))) < 0.01)
	// The slice that straddles the middle lends the silence a little of the sine.
	testing.expect(t, audio.loudness(halves[1]) < 0.1)
	testing.expect_value(t, audio.loudness({}), 0)
}

@(test)
nothing_to_read_gives_no_peaks :: proc(t: ^testing.T) {
	waveform := audio.waveform_from_samples({}, 2, 44_100)
	defer audio.destroy_waveform(&waveform)
	testing.expect_value(t, len(audio.peaks(&waveform, 100)), 0)
	testing.expect_value(t, waveform.duration, time.Duration(0))
}

// Samples that arrive in chunks, a frame split between two of them, make the waveform
// that all of them at once make.
@(test)
chunks_of_any_size_make_the_same_waveform :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	samples := sine(2 * 5000, 0.7, 0.01)
	whole := audio.waveform_from_samples(samples, 2, 8000)
	defer audio.destroy_waveform(&whole)
	b: audio.Waveform_Builder
	audio.init_waveform_builder(&b, 2, 8000)
	at := 0
	for size in ([?]int{1, 3, 1000, 7, 4096}) {
		end := min(at + size, len(samples))
		audio.push_samples(&b, samples[at:end])
		at = end
	}
	audio.push_samples(&b, samples[at:])
	split := audio.finish_waveform(&b)
	defer audio.destroy_waveform(&split)
	testing.expect_value(t, split.frames, whole.frames)
	testing.expect_value(t, split.duration, whole.duration)
	for count in ([?]int{3, 50}) {
		one, other := audio.peaks(&whole, count), audio.peaks(&split, count)
		defer delete(one)
		defer delete(other)
		for i in 0 ..< count do testing.expect_value(t, other[i], one[i])
	}
}

// Short and odd tracks, and impossible asks, give peaks without a bounds error.
@(test)
short_tracks_and_odd_asks_are_safe :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for frames in ([?]int{1, 2, 10, 255, 256, 257, 511, 513, 100_000}) {
		waveform := audio.waveform_from_samples(sine(frames, 0.3, 0.2), 1, 44_100)
		for count in ([?]int{-1, 0, 1, 2, 3, 100, 1000, 100_000}) {
			peaks := audio.peaks(&waveform, count)
			testing.expectf(
				t,
				len(peaks) == (count > 0 ? count : 0),
				"%d frames, %d peaks",
				frames,
				count,
			)
			for peak in peaks do testing.expect(t, peak.low <= peak.high)
			delete(peaks)
		}
		audio.destroy_waveform(&waveform)
	}
	// No channel and no rate count as one.
	waveform := audio.waveform_from_samples(sine(100, 0.3, 0.2), 0, 0)
	defer audio.destroy_waveform(&waveform)
	testing.expect_value(t, waveform.frames, 100)
	testing.expect_value(t, waveform.duration, 100 * time.Second)
}

// Samples that are not numbers, or beyond what a sample can be, give peaks that are
// finite and from -1 to 1, whatever the channels.
@(test)
damaged_samples_give_finite_peaks :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for channels in ([?]int{1, 2, 3}) {
		samples := make([]f32, 3000 * channels, context.temp_allocator)
		for i in 0 ..< len(samples) do samples[i] = 0.25
		samples[7] = math.nan_f32()
		samples[100] = math.inf_f32(1)
		samples[101] = math.inf_f32(-1)
		samples[900] = 1e30
		samples[901] = -1e30
		waveform := audio.waveform_from_samples(samples, channels, 8000)
		peaks := audio.peaks(&waveform, 5)
		whole := audio.peaks(&waveform, 1)
		for peak in ([]audio.Peak{peaks[0], peaks[1], peaks[2], peaks[3], peaks[4], whole[0]}) {
			testing.expectf(t, peak.low >= -1 && peak.high <= 1, "%d channels: %v", channels, peak)
			loud := audio.loudness(peak)
			testing.expectf(t, loud >= 0 && loud <= 1, "%d channels: loudness %v", channels, loud)
		}
		delete(peaks)
		delete(whole)
		audio.destroy_waveform(&waveform)
	}
}

// A coarser level sums the squares of its peaks once each: the loudness of the whole
// track is that of all its frames, even with an odd number of peaks. 1.0.0 counted the
// first of each pair twice, a small error recorded in the plan.
@(test)
the_loudness_of_the_whole_track_is_exact :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	frames := 256 * 5 + 17
	samples := make([]f32, frames, context.temp_allocator)
	squares: f64
	for i in 0 ..< frames {
		samples[i] = 0.9 * math.sin(f32(i) * 0.013) * f32(i % 7) / 7
		squares += f64(samples[i]) * f64(samples[i])
	}
	waveform := audio.waveform_from_samples(samples, 1, 44_100)
	defer audio.destroy_waveform(&waveform)
	whole := audio.peaks(&waveform, 1)
	defer delete(whole)
	testing.expect_value(t, audio.loudness(whole[0]), f32(math.sqrt(squares / f64(frames))))
}

// The duration is rounded to the nanosecond, not cut.
@(test)
the_duration_is_rounded :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	waveform := audio.waveform_from_samples(make([]f32, 88_641, context.temp_allocator), 1, 44_100)
	defer audio.destroy_waveform(&waveform)
	testing.expect_value(t, waveform.duration, time.Duration(2_010_000_000))
}
