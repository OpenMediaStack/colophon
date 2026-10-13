// MPEG audio properties: the duration, bitrate, sample rate and channels of an MP3's
// audio, read from its first frames.
package mpa

import "base:runtime"
import "core:os"
import "core:time"

// The MPEG version of a stream: MPEG-2.5 is the unofficial extension to low rates.
Version :: enum u8 {
	MPEG_2_5,
	MPEG_2,
	MPEG_1,
}

Layer :: enum u8 {
	I,
	II,
	III,
}

// Constant when every frame has the same bitrate, as an Info header or the first
// frames show; variable with a Xing or VBRI header, or frames that differ.
Bitrate_Mode :: enum u8 {
	Constant,
	Variable,
}

// What the first frames of an MPEG audio stream say about it.
Properties :: struct {
	version:      Version,
	layer:        Layer,
	// Without the encoder's delay and padding when a LAME header gives them, as
	// ffprobe counts it; 0 when the bitrate is unknown.
	duration:     time.Duration,
	// In kilobits per second, the average over the stream when it is variable.
	bitrate_kbps: int,
	bitrate_mode: Bitrate_Mode,
	// In hertz.
	sample_rate:  int,
	channels:     int,
}

Format_Error :: enum u8 {
	None,
	// No valid frame header followed by a second one of the same stream in the first
	// SCAN_LIMIT bytes of the audio.
	No_Frame,
}

// Why properties could not be read: the stream (Format_Error), the file (os.Error),
// or memory (runtime.Allocator_Error).
Error :: union #shared_nil {
	Format_Error,
	os.Error,
	runtime.Allocator_Error,
}

// How far into the audio the first frame is looked for. Encoders write a few bytes of
// junk at most; more than this means the file is not an MPEG audio stream.
SCAN_LIMIT :: 512 * 1024

// How much of the stream is read first: the first frame, its Xing or VBRI header,
// and the frames compared when there is none.
@(private)
FIRST_READ :: 64 * 1024

// Reads the properties of an MP3's audio from data, which holds the start of the
// stream between the tags (odid3's Layout.audio) or all of it; audio_size is the
// size of the whole stream. Only data[:audio_size] is read. Gives No_Frame when no
// frame starts within it.
read_bytes :: proc(data: []u8, audio_size: i64) -> (properties: Properties, err: Error) {
	region := data[:clamp(audio_size, 0, i64(len(data)))]
	limit := min(len(region), SCAN_LIMIT)
	whole := i64(len(region)) == audio_size && limit == len(region)
	offset, first := find_first_frame(region[:limit], whole) or_return
	return properties_of(region, offset, first, audio_size - i64(offset)), nil
}

// Reads the properties of the audio of the file at path, the size bytes from offset
// (odid3's Layout.audio). Reads its first 64 KB, and up to SCAN_LIMIT when no frame
// starts there. Scratch memory comes from allocator and is freed before returning.
// Gives No_Frame, or the os.Error that kept the file from being read.
read_file :: proc(
	path: string,
	offset, size: i64,
	allocator := context.allocator,
) -> (
	properties: Properties,
	err: Error,
) {
	if size <= 0 do return {}, .No_Frame
	f := os.open(path) or_return
	defer os.close(f)
	first := read_region(f, offset, min(size, FIRST_READ), allocator) or_return
	defer delete(first, allocator)
	properties, err = read_bytes(first, size)
	if err != .No_Frame || size <= FIRST_READ do return
	more := read_region(f, offset, min(size, SCAN_LIMIT), allocator) or_return
	defer delete(more, allocator)
	return read_bytes(more, size)
}

// The size bytes from offset, or fewer at the end of the file.
@(private = "file")
read_region :: proc(
	f: ^os.File,
	offset, size: i64,
	allocator: runtime.Allocator,
) -> (
	bytes: []u8,
	err: Error,
) {
	bytes = make([]u8, int(size), allocator) or_return
	read, read_err := os.read_at(f, bytes, offset)
	// Windows reports the end of the file as an error, other systems do not.
	if read_err != nil && read_err != .EOF {
		delete(bytes, allocator)
		return nil, read_err
	}
	return bytes[:read], nil
}
