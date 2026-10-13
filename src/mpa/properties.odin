package mpa

import "core:encoding/endian"
import "core:time"

// How many frames are compared to tell a variable bitrate when no header says.
@(private)
FRAMES_COMPARED :: 64

// The properties of the stream whose first frame, h, starts at offset in buf;
// stream_bytes counts the stream from that frame to its end.
@(private)
properties_of :: proc(
	buf: []u8,
	offset: int,
	h: Frame_Header,
	stream_bytes: i64,
) -> (
	p: Properties,
) {
	audio_bytes := max(stream_bytes, 0)
	p.version = h.version
	p.layer = h.layer
	p.sample_rate = h.sample_rate
	p.channels = h.mono ? 1 : 2
	p.bitrate_kbps = h.bitrate_kbps
	frame := buf[offset:min(offset + h.length, len(buf))]
	counted, found := read_xing(frame, h)
	if !found do counted, found = read_vbri(frame)
	if found && trusted(counted, audio_bytes) {
		apply_counted_frames(&p, h, counted, audio_bytes)
		return
	}
	frames := compare_frames(buf[offset:], h)
	p.bitrate_mode = frames.mode
	if frames.mode == .Variable && frames.samples > 0 {
		p.bitrate_kbps = average_kbps(frames.bytes, frames.samples, h.sample_rate)
		// The average rate of the frames compared, in bytes and samples, not rounded
		// to whole kilobits, stands for the whole stream.
		ms := audio_bytes * frames.samples * 1000 / (frames.bytes * i64(h.sample_rate))
		p.duration = time.Duration(ms) * time.Millisecond
	} else if p.bitrate_kbps > 0 {
		// bits divided by kilobits per second gives milliseconds.
		p.duration = time.Duration(audio_bytes * 8 / i64(p.bitrate_kbps)) * time.Millisecond
	}
	return
}

// What a Xing, Info or VBRI header in the first frame tells.
@(private)
Counted_Frames :: struct {
	frames:  i64,
	// The stream's size, or -1 when the header does not give it.
	bytes:   i64,
	mode:    Bitrate_Mode,
	// Samples the encoder added at the start and at the end, from the LAME header.
	delay:   i64,
	padding: i64,
}

// Like ffmpeg, a header whose byte count falls short of the stream by more than a
// sixteenth is taken for that of the first of files joined end to end, and ignored.
@(private)
trusted :: proc(c: Counted_Frames, audio_bytes: i64) -> bool {
	if c.frames <= 0 do return false
	if c.bytes > 0 && audio_bytes > c.bytes + c.bytes / 16 do return false
	return true
}

// The Xing header (variable bitrate) or Info header (constant), which encoders
// write in place of the first frame's audio, after its side information. See
// http://gabriel.mp3-tech.org/mp3infotag.html.
@(private)
read_xing :: proc(frame: []u8, h: Frame_Header) -> (c: Counted_Frames, ok: bool) {
	if h.layer != .III do return
	side := h.version == .MPEG_1 ? (h.mono ? 17 : 32) : (h.mono ? 9 : 17)
	at := 4 + side
	if at + 8 > len(frame) do return
	tag := string(frame[at:at + 4])
	if tag != "Xing" && tag != "Info" do return
	flags := be32(frame, at + 4) or_return
	pos := at + 8
	c.frames = -1
	c.bytes = -1
	if flags & 0x1 != 0 {
		c.frames = i64(be32(frame, pos) or_return)
		pos += 4
	}
	if flags & 0x2 != 0 {
		c.bytes = i64(be32(frame, pos) or_return)
		pos += 4
	}
	if flags & 0x4 != 0 do pos += 100
	if flags & 0x8 != 0 do pos += 4
	c.mode = tag == "Xing" ? .Variable : .Constant
	// The LAME extension, which ffmpeg writes too, gives the encoder delay and padding
	// in 12 bits each, 21 bytes after the encoder's name.
	if pos + 24 <= len(frame) && is_lame_extension(frame[pos:pos + 4]) {
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
	c.bytes = i64(be32(frame, at + 10) or_return)
	c.frames = i64(be32(frame, at + 14) or_return)
	c.mode = .Variable
	return c, true
}

@(private)
apply_counted_frames :: proc(
	p: ^Properties,
	h: Frame_Header,
	c: Counted_Frames,
	audio_bytes: i64,
) {
	samples := c.frames * i64(h.samples)
	p.bitrate_mode = c.mode
	if c.mode == .Variable {
		// As ffmpeg does: the size of every frame over their duration, encoder delay
		// included; a byte count larger than the stream is not believed.
		total := c.bytes > 0 && c.bytes <= audio_bytes ? c.bytes : audio_bytes
		p.bitrate_kbps = average_kbps(total, samples, h.sample_rate)
	}
	if c.delay + c.padding < samples do samples -= c.delay + c.padding
	p.duration = time.Duration(samples * 1000 / i64(h.sample_rate)) * time.Millisecond
}

// The bitrate of bytes lasting samples at sample_rate, in kbps, rounded.
@(private)
average_kbps :: proc(bytes, samples: i64, sample_rate: int) -> int {
	return int((bytes * 8 * i64(sample_rate) + samples * 500) / (samples * 1000))
}

// What the first frames of a stream without a header show.
@(private)
Compared_Frames :: struct {
	mode:    Bitrate_Mode,
	bytes:   i64,
	samples: i64,
}

// A stream whose first frames do not share a bitrate is variable.
@(private)
compare_frames :: proc(stream: []u8, h: Frame_Header) -> (c: Compared_Frames) {
	pos, frames := 0, 0
	for frames < FRAMES_COMPARED && pos + 4 <= len(stream) {
		next := parse_frame_header(stream[pos:]) or_break
		if !same_stream(next, h) || pos + next.length > len(stream) do break
		if next.bitrate_kbps != h.bitrate_kbps do c.mode = .Variable
		frames += 1
		c.bytes += i64(next.length)
		c.samples += i64(next.samples)
		pos += next.length
	}
	return
}

// The encoders whose extension of the Xing header ffmpeg reads.
@(private)
is_lame_extension :: proc(name: []u8) -> bool {
	switch string(name) {
	case "LAME", "Lavf", "Lavc":
		return true
	}
	return false
}

@(private)
be32 :: proc(b: []u8, at: int) -> (u32, bool) {
	if at < 0 || at + 4 > len(b) do return 0, false
	return endian.get_u32(b[at:at + 4], .Big)
}
