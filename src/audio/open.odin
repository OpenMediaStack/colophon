package audio

import "base:runtime"
import "core:os"

import ma "vendor:miniaudio"

// The largest file played or read: a file this big is more than anyone has in tags to
// edit, and it is held in memory while it plays.
@(private)
MAX_FILE_BYTES :: 512 * 1024 * 1024

// Reads the file at path (UTF-8) and opens a decoder over its bytes, which stay where
// they are until close_decoder. The file is read and closed at once, so that nothing
// holds it while it plays or its waveform is read: saving renames a copy over a file,
// which Windows refuses while any handle is open to it, however it was opened.
// Cannot_Open when the file cannot be read, Cannot_Decode when it is not audio.
@(private)
open_decoder :: proc(
	path: string,
	config: ^ma.decoder_config,
	decoder: ^ma.decoder,
	allocator: runtime.Allocator,
) -> (
	data: []byte,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	read, read_err := os.read_entire_file(path, allocator)
	if read_err != nil do return nil, .Cannot_Open
	if len(read) == 0 || len(read) > MAX_FILE_BYTES {
		delete(read, allocator)
		return nil, .Cannot_Decode
	}
	if ma.decoder_init_memory(raw_data(read), uint(len(read)), config, decoder) != .SUCCESS {
		delete(read, allocator)
		return nil, .Cannot_Decode
	}
	return read, .None
}

// Frees a decoder made with open_decoder, and the bytes it read.
@(private)
close_decoder :: proc(decoder: ^ma.decoder, data: []byte, allocator: runtime.Allocator) {
	ma.decoder_uninit(decoder)
	delete(data, allocator)
}
