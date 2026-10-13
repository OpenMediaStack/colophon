// MPEG audio properties: the duration, bitrate, sample rate and channels of an MP3's
// audio, read from its first frames.
package mpa

import "core:os"
import "core:time"

Version :: enum u8 {
	MPEG_2_5,
	MPEG_2,
	MPEG_1,
}

Layer :: enum u8 {
	I   = 1,
	II  = 2,
	III = 3,
}

Bitrate_Mode :: enum u8 {
	Constant,
	Variable,
}

// What the first frames of an MPEG audio stream say about it.
Properties :: struct {
	version:      Version,
	layer:        Layer,
	// Without the encoder's delay and padding when a LAME header gives them, as
	// ffprobe counts it.
	duration:     time.Duration,
	// The average over the stream when the bitrate is variable.
	bitrate_kbps: int,
	bitrate_mode: Bitrate_Mode,
	sample_rate:  int,
	channels:     int,
}

Format_Error :: enum u8 {
	None,
	// No two consecutive valid frame headers in the first SCAN_LIMIT bytes of the audio.
	No_Frame,
}

Error :: union #shared_nil {
	Format_Error,
	os.Error,
}

// How far into the audio the first frame is looked for. Encoders write a few bytes of
// junk at most; more than this means the file is not an MPEG audio stream.
SCAN_LIMIT :: 512 * 1024

// Reads the properties of the audio of an MP3 held in data: the stream between the
// tags, which odid3's Layout.audio locates. data may be only the start of the
// stream, as long as audio_size is the size of all of it.
read_bytes :: proc(data: []u8, audio_size: i64) -> (properties: Properties, err: Error) {
	limit := min(len(data), SCAN_LIMIT)
	at_end := i64(len(data)) >= audio_size
	offset, first, found := find_first_frame(data[:limit], at_end && limit == len(data))
	if !found do return {}, .No_Frame
	return properties_of(data, offset, first, audio_size - i64(offset)), nil
}

// Reads the properties of the audio of the file at path, whose stream is the size
// bytes from offset (odid3's Layout.audio). Only the start of the stream is read.
read_file :: proc(path: string, offset, size: i64) -> (properties: Properties, err: Error) {
	if size <= 0 do return {}, .No_Frame
	f := os.open(path) or_return
	defer os.close(f)
	buffer := make([]u8, int(min(size, SCAN_LIMIT)))
	defer delete(buffer)
	read := os.read_at(f, buffer, offset) or_return
	return read_bytes(buffer[:read], size)
}
