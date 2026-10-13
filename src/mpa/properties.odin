package mpa

import "core:encoding/endian"
import "core:time"

// How many frames are compared to tell a variable bitrate when no header says.
@(private)
FRAMES_COMPARED :: 64

// The properties of the stream whose first frame, h, starts at offset in buf;
// audio_bytes counts the stream from that frame to its end.
@(private)
properties_of :: proc(
	buf: []u8,
	offset: int,
	h: Frame_Header,
	audio_bytes: i64,
) -> (
	p: Properties,
) {
	p.version = h.version
	p.layer = h.layer
	p.sample_rate = h.sample_rate
	p.channels = h.mono ? 1 : 2
	p.bitrate_kbps = h.bitrate_kbps
	frame := buf[offset:min(offset + h.length, len(buf))]
	if xing, ok := read_xing(frame, h); ok {
		apply_counted_frames(&p, h, xing, max(audio_bytes, 0))
		return
	}
	if vbri, ok := read_vbri(frame); ok {
		apply_counted_frames(&p, h, vbri, max(audio_bytes, 0))
		return
	}
	compare_frames(&p, buf[offset:], h)
	if p.bitrate_kbps > 0 {
		// bits divided by kilobits per second gives milliseconds.
		p.duration =
			time.Duration(max(audio_bytes, 0) * 8 / i64(p.bitrate_kbps)) * time.Millisecond
	}
	return
}

// What a Xing, Info or VBRI header in the first frame tells.
@(private)
Counted_Frames :: struct {
	frames:   i64,
	// The stream's size, or -1 when the header does not give it.
	bytes:    i64,
	variable: bool,
	// Samples the encoder added at the start and at the end, from the LAME header.
	delay:    i64,
	padding:  i64,
}

// The Xing header (variable bitrate) or Info header (constant), which encoders
// write in place of the first frame's audio, after its side information. See
// https://www.codeproject.com/Articles/8295/MPEG-Audio-Frame-Header#VBRHeaders.
@(private)
read_xing :: proc(frame: []u8, h: Frame_Header) -> (c: Counted_Frames, ok: bool) {
	if h.layer != .III do return
	side := h.version == .MPEG_1 ? (h.mono ? 17 : 32) : (h.mono ? 9 : 17)
	at := 4 + side
	if at + 8 > len(frame) do return
	tag := string(frame[at:at + 4])
	if tag != "Xing" && tag != "Info" do return
	flags := endian.unchecked_get_u32be(frame[at + 4:])
	pos := at + 8
	c.frames = -1
	c.bytes = -1
	if flags & 0x1 != 0 && pos + 4 <= len(frame) {
		c.frames = i64(endian.unchecked_get_u32be(frame[pos:]))
		pos += 4
	}
	if flags & 0x2 != 0 && pos + 4 <= len(frame) {
		c.bytes = i64(endian.unchecked_get_u32be(frame[pos:]))
		pos += 4
	}
	if flags & 0x4 != 0 do pos += 100
	if flags & 0x8 != 0 do pos += 4
	if c.frames <= 0 do return
	c.variable = tag == "Xing"
	// The LAME extension, which ffmpeg writes too, gives the encoder delay and padding
	// in 12 bits each, 21 bytes after the encoder's name.
	if pos + 24 <= len(frame) && is_encoder_name(frame[pos:pos + 4]) {
		d := frame[pos + 21:pos + 24]
		c.delay = i64(d[0]) << 4 | i64(d[1]) >> 4
		c.padding = i64(d[1] & 0x0F) << 8 | i64(d[2])
	}
	return c, true
}

// The VBRI header of Fraunhofer's encoder, 32 bytes after the frame header.
@(private)
read_vbri :: proc(frame: []u8) -> (c: Counted_Frames, ok: bool) {
	at := 4 + 32
	if at + 18 > len(frame) || string(frame[at:at + 4]) != "VBRI" do return
	c.bytes = i64(endian.unchecked_get_u32be(frame[at + 10:]))
	c.frames = i64(endian.unchecked_get_u32be(frame[at + 14:]))
	c.variable = true
	return c, c.frames > 0
}

@(private)
apply_counted_frames :: proc(
	p: ^Properties,
	h: Frame_Header,
	c: Counted_Frames,
	audio_bytes: i64,
) {
	samples := c.frames * i64(h.samples)
	if c.variable {
		p.bitrate_mode = .Variable
		// As ffmpeg does: the size of every frame over their duration, encoder delay
		// included.
		total := c.bytes > 0 ? c.bytes : audio_bytes
		p.bitrate_kbps = int((total * 8 * i64(h.sample_rate) + samples * 500) / (samples * 1000))
	}
	if c.delay + c.padding < samples do samples -= c.delay + c.padding
	p.duration = time.Duration(samples * 1000 / i64(h.sample_rate)) * time.Millisecond
}

// Without a header, a stream whose first frames do not share a bitrate is variable,
// and their average stands for the whole stream.
@(private)
compare_frames :: proc(p: ^Properties, stream: []u8, h: Frame_Header) {
	pos, frames, bytes, samples := 0, 0, i64(0), i64(0)
	for frames < FRAMES_COMPARED && pos + 4 <= len(stream) {
		next := parse_frame_header(stream[pos:]) or_break
		if !same_stream(next, h) || pos + next.length > len(stream) do break
		if next.bitrate_kbps != h.bitrate_kbps do p.bitrate_mode = .Variable
		frames += 1
		bytes += i64(next.length)
		samples += i64(next.samples)
		pos += next.length
	}
	if p.bitrate_mode == .Variable && samples > 0 {
		p.bitrate_kbps = int((bytes * 8 * i64(h.sample_rate) + samples * 500) / (samples * 1000))
	}
}

// Four letters or digits, such as "LAME" or "Lavc".
@(private)
is_encoder_name :: proc(b: []u8) -> bool {
	for c in b {
		switch c {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '.':
		case:
			return false
		}
	}
	return true
}
