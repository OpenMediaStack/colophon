package audio

import "core:testing"

// Each level has half the peaks of the one before, down to one.
@(test)
the_levels_halve_down_to_one_peak :: proc(t: ^testing.T) {
	samples := make([]f32, 256 * 37 + 5, context.temp_allocator)
	defer free_all(context.temp_allocator)
	for &sample, i in samples do sample = 0.9 * f32(i % 11) / 11
	waveform := waveform_from_samples(samples, 1, 44_100)
	defer destroy_waveform(&waveform)
	testing.expect_value(t, len(waveform.levels[0]), 38)
	for level, i in waveform.levels[1:] {
		testing.expect_value(t, len(level), (len(waveform.levels[i]) + 1) / 2)
	}
	testing.expect_value(t, len(waveform.levels[len(waveform.levels) - 1]), 1)
}

// Merging peaks adds up what they hold, and their frames stop at the most a count
// can hold instead of wrapping around.
@(test)
merged_peaks_add_up_and_do_not_wrap :: proc(t: ^testing.T) {
	a := Peak{-0.5, 0.25, 2, 4}
	b := Peak{-0.25, 0.75, 3, 6}
	merged := merge_peaks(a, b)
	testing.expect_value(t, merged, Peak{-0.5, 0.75, 5, 10})
	full := Peak{0, 0, 1, max(u32) - 2}
	testing.expect_value(t, merge_peaks(full, b).frames, max(u32))
	testing.expect_value(t, merge_peaks(b, Peak{frames = max(u32)}).frames, max(u32))
}
