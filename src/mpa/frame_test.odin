package mpa

import "core:testing"

@(test)
an_mpeg1_layer3_header_gives_its_frame_length :: proc(t: ^testing.T) {
	// 128 kbps, 44.1 kHz, no padding, stereo.
	h, ok := parse_frame_header({0xFF, 0xFB, 0x90, 0x00})
	testing.expect(t, ok)
	testing.expect_value(t, h.version, Version.MPEG_1)
	testing.expect_value(t, h.layer, Layer.III)
	testing.expect_value(t, h.bitrate_kbps, 128)
	testing.expect_value(t, h.sample_rate, 44100)
	testing.expect_value(t, h.samples, 1152)
	testing.expect_value(t, h.length, 417)
	testing.expect(t, !h.mono)
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
	// MPEG-2 Layer III, 64 kbps, 22.05 kHz.
	h, ok := parse_frame_header({0xFF, 0xF3, 0x80, 0x00})
	testing.expect(t, ok)
	testing.expect_value(t, h.version, Version.MPEG_2)
	testing.expect_value(t, h.samples, 576)
	testing.expect_value(t, h.sample_rate, 22050)
	// MPEG-2.5 Layer III, 32 kbps, 8 kHz.
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
	copy(buf[10:], []u8{0xFF, 0xFB, 0x90, 0x00})
	_, _, found := find_first_frame(buf, false)
	testing.expect(t, !found)
	// Two frames in a row are.
	copy(buf[10 + 417:], []u8{0xFF, 0xFB, 0x90, 0x00})
	offset, _, ok := find_first_frame(buf, false)
	testing.expect(t, ok)
	testing.expect_value(t, offset, 10)
}

@(test)
an_encoder_name_is_letters_and_digits :: proc(t: ^testing.T) {
	testing.expect(t, is_encoder_name(transmute([]u8)string("LAME")))
	testing.expect(t, is_encoder_name(transmute([]u8)string("Lavc")))
	testing.expect(t, !is_encoder_name([]u8{0, 0, 0, 0}))
}
