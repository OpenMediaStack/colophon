package mpa_tests

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"

import mpa ".."
import id3 "../../../libs/odid3"

TESTDATA :: #directory + "/../../../testdata"

// mpa counts whole milliseconds, ffprobe microseconds.
DURATION_TOLERANCE :: 2 * time.Millisecond
// mpa rounds the bitrate to whole kilobits per second, as ffmpeg computes it.
BITRATE_TOLERANCE :: 0.5

// What ffprobe read in a fixture: its `-of flat` output, which testdata/make.sh saves.
read_ffprobe :: proc(name: string) -> (values: map[string]string, ok: bool) {
	path := fmt.tprintf("%s/ffprobe/%s.txt", TESTDATA, name)
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil do return
	values = make(map[string]string, context.temp_allocator)
	for line in strings.split_lines(string(data), context.temp_allocator) {
		key, separator, value := strings.partition(line, "=")
		if len(separator) > 0 do values[key] = strings.trim(value, "\"")
	}
	return values, true
}

// Where the audio is, and the size of the file.
layout_of :: proc(path: string) -> (offset, size, file_size: i64, ok: bool) {
	tags, err := id3.read_file(path, {skip_picture_data = true})
	if err != nil do return
	defer id3.destroy(&tags)
	l := tags.layout
	return l.audio.offset, l.audio.size, l.file_size, true
}

properties_of :: proc(name: string) -> (p: mpa.Properties, err: mpa.Error, ok: bool) {
	path := fmt.tprintf("%s/%s.mp3", TESTDATA, name)
	offset, size, _ := layout_of(path) or_return
	p, err = mpa.read_file(path, offset, size)
	return p, err, true
}

// The duration ffprobe gives, or the one it would give if it stopped where the
// audio ends: without a header to count frames, it divides everything after the
// ID3v2 tag by the bitrate, APE and ID3v1 tags included.
expected_duration :: proc(probe: map[string]string, path: string) -> time.Duration {
	seconds := strconv.parse_f64(probe["format.duration"]) or_else -1
	duration := time.Duration(seconds * f64(time.Second))
	kbps := (strconv.parse_f64(probe["streams.stream.0.bit_rate"]) or_else -1) / 1000
	offset, size, file_size, ok := layout_of(path)
	if !ok || kbps <= 0 do return duration
	millisecond := f64(time.Millisecond)
	estimated := time.Duration(f64(file_size - offset) * 8 / kbps * millisecond)
	if abs(duration - estimated) < DURATION_TOLERANCE {
		return time.Duration(f64(size) * 8 / kbps * millisecond)
	}
	return duration
}

@(test)
every_fixture_matches_ffprobe :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	folder := fmt.tprintf("%s/ffprobe", TESTDATA)
	entries, err := os.read_all_directory_by_path(folder, context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	checked := 0
	for entry in entries {
		name := strings.trim_suffix(entry.name, ".txt")
		probe := read_ffprobe(name) or_continue
		path := fmt.tprintf("%s/%s.mp3", TESTDATA, name)
		p, read_err, found := properties_of(name)
		if !testing.expectf(t, found, "%s: odid3 could not read it", name) do continue
		if !testing.expectf(t, read_err == nil, "%s: %v", name, read_err) do continue
		checked += 1

		rate := strconv.parse_int(probe["streams.stream.0.sample_rate"]) or_else -1
		channels := strconv.parse_int(probe["streams.stream.0.channels"]) or_else -1
		testing.expectf(
			t,
			p.sample_rate == rate,
			"%s: sample rate %d, ffprobe %d",
			name,
			p.sample_rate,
			rate,
		)
		testing.expectf(
			t,
			p.channels == channels,
			"%s: channels %d, ffprobe %d",
			name,
			p.channels,
			channels,
		)

		want := expected_duration(probe, path)
		close := abs(p.duration - want) <= DURATION_TOLERANCE
		testing.expectf(t, close, "%s: duration %v, ffprobe %v", name, p.duration, want)

		kbps := (strconv.parse_f64(probe["streams.stream.0.bit_rate"]) or_else -1) / 1000
		same := abs(f64(p.bitrate_kbps) - kbps) <= BITRATE_TOLERANCE
		testing.expectf(t, same, "%s: bitrate %d, ffprobe %.3f", name, p.bitrate_kbps, kbps)
	}
	testing.expectf(t, checked >= 15, "only %d fixtures checked", checked)
}

@(test)
the_bitrate_mode_follows_the_encoder :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	Case :: struct {
		name: string,
		mode: mpa.Bitrate_Mode,
	}
	cases := [?]Case {
		{"cbr_stereo", .Constant},
		{"cbr_mono_32k", .Constant},
		{"cbr_mono_16k", .Constant},
		{"no_tag", .Constant},
		{"vbr_mono", .Variable},
		{"vbr_no_header", .Variable},
	}
	for c in cases {
		p, err, found := properties_of(c.name)
		if !testing.expect(t, found) do continue
		testing.expectf(
			t,
			err == nil && p.bitrate_mode == c.mode,
			"%s: %v %v",
			c.name,
			p.bitrate_mode,
			err,
		)
	}
}

@(test)
damaged_audio_never_panics :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for name in ([]string{"cbr_stereo.mp3", "vbr_mono.mp3"}) {
		data, err := os.read_entire_file_from_path(
			fmt.tprintf("%s/%s", TESTDATA, name),
			context.allocator,
		)
		if !testing.expect(t, err == nil) do continue
		defer delete(data)
		// Every length of the first frames, then larger cuts.
		for size in 0 ..< min(len(data), 1200) {
			_, _ = mpa.read_bytes(data[:size], i64(size))
		}
		for size := 1200; size < len(data); size += 997 {
			_, _ = mpa.read_bytes(data[:size], i64(len(data)))
		}
		mutated := make([]u8, len(data))
		defer delete(mutated)
		for round in 0 ..< 200 {
			copy(mutated, data)
			for _ in 0 ..< 1 + round % 20 {
				mutated[rand.int_max(len(mutated))] = u8(rand.int_max(256))
			}
			_, _ = mpa.read_bytes(mutated, i64(len(mutated)))
			_, _ = mpa.read_bytes(mutated[:rand.int_max(len(mutated))], i64(len(mutated)))
		}
	}
	_, missing := mpa.read_bytes({}, 0)
	testing.expect_value(t, missing, mpa.Error(mpa.Format_Error.No_Frame))
}

@(test)
a_region_past_the_end_of_the_file_reads_what_is_there :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	path := fmt.tprintf("%s/cbr_stereo.mp3", TESTDATA)
	offset, size, _, found := layout_of(path)
	if !testing.expect(t, found) do return
	p, err := mpa.read_file(path, offset, size + 10_000)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.sample_rate, 44100)
}
