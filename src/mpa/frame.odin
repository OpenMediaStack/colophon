package mpa

// One MPEG audio frame header, from its four bytes.
@(private)
Frame_Header :: struct {
	version:      Version,
	layer:        Layer,
	bitrate_kbps: int,
	sample_rate:  int,
	padding:      bool,
	mono:         bool,
	// In bytes, the header included.
	length:       int,
	// Samples per channel.
	samples:      int,
}

// In kilobits per second, by version (MPEG-1, or MPEG-2 and 2.5), layer and the 4
// bits of the header; the first and the last index are invalid.
@(private, rodata)
BITRATES := [2][3][16]int {
	{
		{0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0},
		{0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0},
		{0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0},
	},
	{
		{0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0},
		{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},
		{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0},
	},
}

@(private, rodata)
SAMPLE_RATES := [Version][3]int {
	.MPEG_2_5 = {11025, 12000, 8000},
	.MPEG_2   = {22050, 24000, 16000},
	.MPEG_1   = {44100, 48000, 32000},
}

// Parses the frame header at the start of b. Free format streams, whose bitrate
// the header does not give, are refused: their frame length is unknown.
@(private)
parse_frame_header :: proc(b: []u8) -> (h: Frame_Header, ok: bool) {
	if len(b) < 4 || b[0] != 0xFF || b[1] & 0xE0 != 0xE0 do return
	version_bits := (b[1] >> 3) & 0x03
	layer_bits := (b[1] >> 1) & 0x03
	bitrate_index := b[2] >> 4
	rate_index := (b[2] >> 2) & 0x03
	if version_bits == 1 || layer_bits == 0 || bitrate_index == 0 || bitrate_index == 15 || rate_index == 3 do return
	// An emphasis of 2 is reserved: these bytes are not a header.
	if b[3] & 0x03 == 2 do return
	switch version_bits {
	case 0:
		h.version = .MPEG_2_5
	case 2:
		h.version = .MPEG_2
	case:
		h.version = .MPEG_1
	}
	h.layer = Layer(4 - layer_bits)
	h.bitrate_kbps = BITRATES[h.version == .MPEG_1 ? 0 : 1][int(h.layer) - 1][bitrate_index]
	h.sample_rate = SAMPLE_RATES[h.version][rate_index]
	h.padding = b[2] & 0x02 != 0
	h.mono = b[3] >> 6 == 3
	pad := h.padding ? 1 : 0
	switch h.layer {
	case .I:
		h.samples = 384
		h.length = (12 * h.bitrate_kbps * 1000 / h.sample_rate + pad) * 4
	case .II:
		h.samples = 1152
		h.length = 144 * h.bitrate_kbps * 1000 / h.sample_rate + pad
	case .III:
		h.samples = h.version == .MPEG_1 ? 1152 : 576
		h.length = h.samples / 8 * h.bitrate_kbps * 1000 / h.sample_rate + pad
	}
	if h.length < 4 do return {}, false
	return h, true
}

// Two headers of the same stream: a match of version, layer and sample rate.
@(private)
same_stream :: proc(a, b: Frame_Header) -> bool {
	return a.version == b.version && a.layer == b.layer && a.sample_rate == b.sample_rate
}

// The first frame of buf whose header is followed by a second one of the same
// stream right after it. When the frame ends exactly at the end of buf and buf is
// the whole stream (at_end), no second header is needed.
@(private)
find_first_frame :: proc(buf: []u8, at_end: bool) -> (offset: int, h: Frame_Header, ok: bool) {
	for i := 0; i + 4 <= len(buf); i += 1 {
		if buf[i] != 0xFF || buf[i + 1] & 0xE0 != 0xE0 do continue
		first := parse_frame_header(buf[i:]) or_continue
		next := i + first.length
		if next + 4 <= len(buf) {
			second, valid := parse_frame_header(buf[next:])
			if valid && same_stream(first, second) do return i, first, true
		} else if at_end && next == len(buf) {
			return i, first, true
		}
	}
	return
}
