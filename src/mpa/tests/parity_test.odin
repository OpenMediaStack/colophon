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

// ffprobe removes the encoder delay and padding the LAME header gives, as mpa does;
// one frame at 44.1 kHz lasts 26 ms.
DURATION_TOLERANCE :: 30 * time.Millisecond
// The 1 second fixtures put a few percent of their size in the LAME header's frame.
BITRATE_TOLERANCE :: 0.03

// What ffprobe read in a fixture: its `-of flat` output, which testdata/make.sh saves.
@(private)
read_ffprobe :: proc(name: string) -> (values: map[string]string, ok: bool) {
	data, err := os.read_entire_file_from_path(
		fmt.tprintf("%s/ffprobe/%s.txt", TESTDATA, name),
		context.temp_allocator,
	)
	if err != nil do return
	values = make(map[string]string, context.temp_allocator)
	for line in strings.split_lines(string(data), context.temp_allocator) {
		key, separator, value := strings.partition(line, "=")
		if len(separator) > 0 do values[key] = strings.trim(value, "\"")
	}
	return values, true
}

@(private)
audio_of :: proc(path: string) -> (offset, size: i64, ok: bool) {
	offset, size, _, ok = layout_of(path)
	return
}

// Where the audio is, and the size of what follows it that ffprobe counts as audio
// when it divides a file's size by its bitrate: an APE tag and ID3v1.
@(private)
layout_of :: proc(path: string) -> (offset, size, trailing: i64, ok: bool) {
	tags, err := id3.read_file(path, {skip_picture_data = true})
	if err != nil do return
	defer id3.destroy(&tags)
	l := tags.layout
	trailing = l.ape.size + l.lyrics3.size + l.v1_enhanced.size + l.v1.size
	return l.audio.offset, l.audio.size, trailing, true
}

@(test)
every_fixture_matches_ffprobe :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	entries, err := os.read_all_directory_by_path(
		fmt.tprintf("%s/ffprobe", TESTDATA),
		context.temp_allocator,
	)
	if !testing.expect(t, err == nil) do return
	checked := 0
	for entry in entries {
		name := strings.trim_suffix(entry.name, ".txt")
		probe := read_ffprobe(name) or_continue
		path := fmt.tprintf("%s/%s.mp3", TESTDATA, name)
		offset, size, trailing, found := layout_of(path)
		if !testing.expectf(t, found, "%s: odid3 could not read it", name) do continue
		p, read_err := mpa.read_file(path, offset, size)
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

		seconds := strconv.parse_f64(probe["format.duration"]) or_else -1
		want := time.Duration(seconds * f64(time.Second))
		bits := strconv.parse_f64(probe["streams.stream.0.bit_rate"]) or_else -1
		kbps := bits / 1000
		if p.bitrate_mode == .Constant && trailing > 0 && kbps > 0 {
			// Without a Xing header, ffprobe divides the file's size by the bitrate and
			// counts an APE tag after the audio as audio; mpa stops where the audio ends.
			want -= time.Duration(f64(trailing) * 8 / kbps * f64(time.Millisecond))
		}
		testing.expectf(
			t,
			abs(p.duration - want) <= DURATION_TOLERANCE,
			"%s: duration %v, ffprobe %v",
			name,
			p.duration,
			want,
		)

		testing.expectf(
			t,
			abs(f64(p.bitrate_kbps) - kbps) <= kbps * BITRATE_TOLERANCE,
			"%s: bitrate %d, ffprobe %.1f",
			name,
			p.bitrate_kbps,
			kbps,
		)
	}
	testing.expectf(t, checked >= 15, "only %d fixtures checked", checked)
}

@(test)
the_bitrate_mode_follows_the_encoder :: proc(t: ^testing.T) {
	cases := [?]struct {
		name: string,
		mode: mpa.Bitrate_Mode,
	}{{"cbr_stereo", .Constant}, {"vbr_mono", .Variable}, {"vbr_no_header", .Variable}}
	for c in cases {
		path := fmt.tprintf("%s/%s.mp3", TESTDATA, c.name)
		offset, size, found := audio_of(path)
		if !testing.expect(t, found) do continue
		p, err := mpa.read_file(path, offset, size)
		testing.expectf(
			t,
			err == nil && p.bitrate_mode == c.mode,
			"%s: %v %v",
			c.name,
			p.bitrate_mode,
			err,
		)
	}
	free_all(context.temp_allocator)
}

@(test)
damaged_audio_never_panics :: proc(t: ^testing.T) {
	data, err := os.read_entire_file_from_path(
		fmt.tprintf("%s/cbr_stereo.mp3", TESTDATA),
		context.allocator,
	)
	if !testing.expect(t, err == nil) do return
	defer delete(data)
	defer free_all(context.temp_allocator)
	for cut in ([]int{0, 1, 3, 4, 100, 417, 418, 1000, len(data) / 2}) {
		size := min(cut, len(data))
		_, _ = mpa.read_bytes(data[:size], i64(size))
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
	_, missing := mpa.read_bytes({}, 0)
	testing.expect_value(t, missing, mpa.Error(mpa.Format_Error.No_Frame))
}
