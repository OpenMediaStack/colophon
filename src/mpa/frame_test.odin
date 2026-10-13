package mpa

import "core:encoding/endian"
import "core:testing"
import "core:time"

// A frame of an MPEG-1 Layer III stream at 128 kbps and 44.1 kHz, stereo: 417 bytes.
@(private = "file")
FRAME_HEADER :: [4]u8{0xFF, 0xFB, 0x90, 0x00}
@(private = "file")
FRAME_LENGTH :: 417

// count frames of the stream above, the first one holding header at byte at.
@(private = "file")
stream_of :: proc(count: int, header: string = "", at := 0) -> []u8 {
	bytes := make([]u8, count * FRAME_LENGTH)
	for i in 0 ..< count {
		h := FRAME_HEADER
		copy(bytes[i * FRAME_LENGTH:], h[:])
	}
	copy(bytes[at:], header)
	return bytes
}

@(private = "file")
put_be32 :: proc(b: []u8, at: int, value: u32) {
	endian.put_u32(b[at:at + 4], .Big, value)
}

@(test)
an_mpeg1_layer3_header_gives_its_frame_length :: proc(t: ^testing.T) {
	header := FRAME_HEADER
	h, ok := parse_frame_header(header[:])
	testing.expect(t, ok)
	testing.expect_value(t, h.version, Version.MPEG_1)
	testing.expect_value(t, h.layer, Layer.III)
	testing.expect_value(t, h.bitrate_kbps, 128)
	testing.expect_value(t, h.sample_rate, 44100)
	testing.expect_value(t, h.samples, 1152)
	testing.expect_value(t, h.length, FRAME_LENGTH)
	testing.expect(t, !h.mono)
}

@(test)
layers_1_and_2_have_their_own_lengths :: proc(t: ^testing.T) {
	// Layer I at 288 kbps: (12 * 288000 / 44100) slots of 4 bytes.
	h, ok := parse_frame_header({0xFF, 0xFF, 0x90, 0x00})
	testing.expect(t, ok)
	testing.expect_value(t, h.layer, Layer.I)
	testing.expect_value(t, h.length, 312)
	testing.expect_value(t, h.samples, 384)
	// Layer II at 160 kbps: 144 * 160000 / 44100 bytes.
	h, ok = parse_frame_header({0xFF, 0xFD, 0x90, 0x00})
	testing.expect(t, ok)
	testing.expect_value(t, h.layer, Layer.II)
	testing.expect_value(t, h.length, 522)
	testing.expect_value(t, h.samples, 1152)
}

@(test)
padding_and_mono_are_read :: proc(t: ^testing.T) {
	h, ok := parse_frame_header({0xFF, 0xFB, 0x92, 0xC0})
	testing.expect(t, ok)
	testing.expect_value(t, h.length, 418)
	testing.expect(t, h.mono)
}

@(test)
mpeg2_and_2_5_have_half_the_samples :: proc(t: ^testing.T) {
	h, ok := parse_frame_header({0xFF, 0xF3, 0x80, 0x00})
	testing.expect(t, ok)
	testing.expect_value(t, h.version, Version.MPEG_2)
	testing.expect_value(t, h.samples, 576)
	testing.expect_value(t, h.sample_rate, 22050)
	h, ok = parse_frame_header({0xFF, 0xE3, 0x48, 0x00})
	testing.expect(t, ok)
	testing.expect_value(t, h.version, Version.MPEG_2_5)
	testing.expect_value(t, h.sample_rate, 8000)
}

@(test)
reserved_and_free_format_values_are_refused :: proc(t: ^testing.T) {
	headers := [?][4]u8 {
		{0xFF, 0xEB, 0x90, 0x00}, // version 1 is reserved
		{0xFF, 0xF9, 0x90, 0x00}, // layer 0 is reserved
		{0xFF, 0xFB, 0x00, 0x00}, // free format
		{0xFF, 0xFB, 0xF0, 0x00}, // bitrate index 15
		{0xFF, 0xFB, 0x9C, 0x00}, // sample rate index 3
		{0xFF, 0xFB, 0x90, 0x02}, // emphasis 2
		{0xFF, 0x7B, 0x90, 0x00}, // broken sync
	}
	for h, i in headers {
		bytes := h
		_, ok := parse_frame_header(bytes[:])
		testing.expectf(t, !ok, "header %d was accepted", i)
	}
	_, ok := parse_frame_header({0xFF, 0xFB})
	testing.expect(t, !ok)
}

@(test)
a_lone_header_is_not_a_stream :: proc(t: ^testing.T) {
	buf := make([]u8, 1000)
	defer delete(buf)
	h := FRAME_HEADER
	copy(buf[10:], h[:])
	_, _, err := find_first_frame(buf, false)
	testing.expect_value(t, err, Format_Error.No_Frame)
	copy(buf[10 + FRAME_LENGTH:], h[:])
	offset, _, found := find_first_frame(buf, false)
	testing.expect_value(t, found, Format_Error.None)
	testing.expect_value(t, offset, 10)
}

@(test)
a_run_of_ff_bytes_is_no_frame :: proc(t: ^testing.T) {
	buf := make([]u8, 4096)
	defer delete(buf)
	for &b in buf do b = 0xFF
	_, err := read_bytes(buf, i64(len(buf)))
	testing.expect_value(t, err, Error(Format_Error.No_Frame))
}

@(test)
only_the_region_given_is_read :: proc(t: ^testing.T) {
	stream := stream_of(4)
	defer delete(stream)
	for size in ([]i64{0, -5, 3}) {
		_, err := read_bytes(stream, size)
		testing.expectf(
			t,
			err == Error(Format_Error.No_Frame),
			"a region of %d bytes gave %v",
			size,
			err,
		)
	}
	p, err := read_bytes(stream, 2 * FRAME_LENGTH)
	testing.expect_value(t, err, nil)
	// Two frames of 1152 samples at 44.1 kHz.
	testing.expect_value(t, p.duration, 52 * time.Millisecond)
}

@(test)
a_vbri_header_counts_the_frames :: proc(t: ^testing.T) {
	stream := stream_of(3, "VBRI", 36)
	defer delete(stream)
	put_be32(stream, 36 + 10, 3 * FRAME_LENGTH)
	put_be32(stream, 36 + 14, 1000)
	p, err := read_bytes(stream, i64(len(stream)))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.bitrate_mode, Bitrate_Mode.Variable)
	// 1000 frames of 1152 samples at 44.1 kHz.
	testing.expect_value(t, p.duration, 26122 * time.Millisecond)
}

@(test)
a_xing_header_gives_frames_bytes_and_the_lame_delay :: proc(t: ^testing.T) {
	// MPEG-1 stereo: the Xing header comes 4 + 32 bytes into the frame.
	at :: 36
	stream := stream_of(3, "Xing", at)
	defer delete(stream)
	put_be32(stream, at + 4, 0x3)
	put_be32(stream, at + 8, 100)
	put_be32(stream, at + 12, 3 * FRAME_LENGTH)
	copy(stream[at + 16:], "LAME")
	// 576 samples of delay and 1152 of padding, 12 bits each.
	stream[at + 16 + 21] = 0x24
	stream[at + 16 + 22] = 0x04
	stream[at + 16 + 23] = 0x80
	p, err := read_bytes(stream, i64(len(stream)))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.bitrate_mode, Bitrate_Mode.Variable)
	// 100 frames of 1152 samples, less 1728, at 44.1 kHz.
	testing.expect_value(t, p.duration, (100 * 1152 - 1728) * 1000 / 44100 * time.Millisecond)
}

@(test)
an_info_header_without_a_frame_count_is_ignored :: proc(t: ^testing.T) {
	stream := stream_of(3, "Info", 36)
	defer delete(stream)
	put_be32(stream, 36 + 4, 0x2)
	put_be32(stream, 36 + 8, 3 * FRAME_LENGTH)
	p, err := read_bytes(stream, i64(len(stream)))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.bitrate_mode, Bitrate_Mode.Constant)
	testing.expect_value(t, p.duration, 3 * FRAME_LENGTH * 8 / 128 * time.Millisecond)
}

@(test)
a_delay_longer_than_the_stream_is_not_taken_off :: proc(t: ^testing.T) {
	stream := stream_of(3, "Xing", 36)
	defer delete(stream)
	put_be32(stream, 36 + 4, 0x1)
	put_be32(stream, 36 + 8, 1)
	copy(stream[36 + 12:], "Lavc")
	stream[36 + 12 + 21] = 0xFF
	stream[36 + 12 + 22] = 0xFF
	stream[36 + 12 + 23] = 0xFF
	p, err := read_bytes(stream, i64(len(stream)))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.duration, 1152 * 1000 / 44100 * time.Millisecond)
}

@(test)
a_header_for_a_shorter_stream_is_ignored :: proc(t: ^testing.T) {
	// Files joined end to end keep the first one's header: ffmpeg then counts frames.
	stream := stream_of(40, "Xing", 36)
	defer delete(stream)
	put_be32(stream, 36 + 4, 0x3)
	put_be32(stream, 36 + 8, 2)
	put_be32(stream, 36 + 12, 2 * FRAME_LENGTH)
	p, err := read_bytes(stream, i64(len(stream)))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.bitrate_mode, Bitrate_Mode.Constant)
	testing.expect_value(t, p.duration, 40 * FRAME_LENGTH * 8 / 128 * time.Millisecond)
}

@(test)
only_lame_and_ffmpeg_extensions_are_read :: proc(t: ^testing.T) {
	testing.expect(t, is_lame_extension(transmute([]u8)string("LAME")))
	testing.expect(t, is_lame_extension(transmute([]u8)string("Lavc")))
	testing.expect(t, is_lame_extension(transmute([]u8)string("Lavf")))
	testing.expect(t, !is_lame_extension(transmute([]u8)string("GOGO")))
}
