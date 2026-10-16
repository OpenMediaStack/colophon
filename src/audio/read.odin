package audio

import "core:sync"

import ma "vendor:miniaudio"

// The frames decoded at a time while a waveform is read.
@(private = "file")
CHUNK_FRAMES :: 4096

// Decodes the whole file at path, as it plays, and gives its waveform. It reads the
// file and decodes it, which takes a while for a long track: call it off the UI thread.
// With cancelled, set from another thread, it stops at the next chunk and gives
// Cancelled. A file it cannot open or decode gives that error; one that breaks off
// gives the waveform of what could be decoded. Free the waveform with destroy_waveform
// and the same allocator.
read_waveform :: proc(
	path: string,
	cancelled: ^bool = nil,
	allocator := context.allocator,
) -> (
	waveform: Waveform,
	err: Error,
) {
	// Asked to stop before it began, it does not even open the file.
	if cancelled != nil && sync.atomic_load(cancelled) do return {}, .Cancelled
	decoder: ma.decoder
	config := ma.decoder_config_init(.f32, 0, 0)
	data, open_err := open_decoder(path, &config, &decoder, allocator)
	if open_err != .None do return {}, open_err
	defer close_decoder(&decoder, data, allocator)
	channels := max(int(decoder.outputChannels), 1)
	builder: Waveform_Builder
	init_waveform_builder(&builder, channels, int(decoder.outputSampleRate), allocator)
	buffer := make([]f32, CHUNK_FRAMES * channels, allocator)
	defer delete(buffer, allocator)
	for {
		if cancelled != nil && sync.atomic_load(cancelled) {
			destroy_waveform_builder(&builder)
			return {}, .Cancelled
		}
		read: u64
		result := ma.decoder_read_pcm_frames(&decoder, raw_data(buffer), CHUNK_FRAMES, &read)
		push_samples(&builder, buffer[:int(read) * channels])
		if result != .SUCCESS || read == 0 do break
	}
	return finish_waveform(&builder), .None
}
