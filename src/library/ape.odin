package library

import "base:runtime"
import "core:bytes"
import "core:encoding/endian"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// An APEv2 tag ends with a footer of this size, after its items.
@(private = "file")
APE_FOOTER_SIZE :: 32

// Larger tags hold pictures or worse; Colophon reads none of them.
@(private = "file")
APE_MAX_SIZE :: 1 << 20

// The generic fields of the APEv2 tag that odid3 found at offset in the file at path,
// size bytes long with its header and footer. MP3Gain and foobar2000 write one, most
// often alongside ID3 tags, whose fields come first. Binary items, values that are not
// UTF-8 and unknown keys are skipped. ok is false when the tag cannot be read.
@(private)
read_ape :: proc(
	path: string,
	offset, size: i64,
	allocator: runtime.Allocator,
) -> (
	t: Tags,
	ok: bool,
) {
	if size < APE_FOOTER_SIZE || size > APE_MAX_SIZE do return
	f, open_err := os.open(path)
	if open_err != nil do return
	defer os.close(f)
	data := make([]u8, size, allocator)
	defer delete(data, allocator)
	n, read_err := os.read_at(f, data, offset)
	if read_err != nil || i64(n) != size do return
	return ape_fields(data, allocator), true
}

// The fields of an APEv2 tag, data ending with its footer.
@(private)
ape_fields :: proc(data: []u8, allocator: runtime.Allocator) -> (t: Tags) {
	if len(data) < APE_FOOTER_SIZE do return
	footer := data[len(data) - APE_FOOTER_SIZE:]
	if string(footer[:8]) != "APETAGEX" do return
	tag_size := int(endian.unchecked_get_u32le(footer[12:]))
	count := int(endian.unchecked_get_u32le(footer[16:]))
	if tag_size < APE_FOOTER_SIZE || tag_size > len(data) do return
	items := data[len(data) - tag_size:len(data) - APE_FOOTER_SIZE]
	for _ in 0 ..< count {
		// The value's size and the item's flags, then the key and a NUL.
		if len(items) < 9 do break
		value_size := int(endian.unchecked_get_u32le(items[0:]))
		flags := endian.unchecked_get_u32le(items[4:])
		key_size := bytes.index_byte(items[8:], 0)
		if key_size < 0 do break
		key := string(items[8:][:key_size])
		items = items[8 + key_size + 1:]
		if value_size > len(items) do break
		value := string(items[:value_size])
		items = items[value_size:]
		// Bits 1 and 2 say text, binary or a link; only text is UTF-8.
		if (flags >> 1) & 3 != 0 || !utf8.valid_string(value) do continue
		// A list of values is separated by NULs; Colophon shows the first.
		first, _, _ := strings.partition(value, "\x00")
		set_ape_field(&t, key, first, allocator)
	}
	return
}

// Sets the field of tags that the item key names, unless an earlier item set it.
@(private = "file")
set_ape_field :: proc(t: ^Tags, key, value: string, allocator: runtime.Allocator) {
	text :: proc(slot: ^Maybe(string), value: string, allocator: runtime.Allocator) {
		if slot^ == nil && len(value) > 0 do slot^ = strings.clone(value, allocator)
	}
	pair :: proc(number, total: ^Maybe(int), value: string) {
		if number^ != nil do return
		n, separator, of := strings.partition(value, "/")
		if parsed, ok := leading_number(n); ok do number^ = parsed
		if len(separator) == 0 || number^ == nil do return
		if parsed, ok := leading_number(of); ok do total^ = parsed
	}
	switch {
	case strings.equal_fold(key, "Title"):
		text(&t.title, value, allocator)
	case strings.equal_fold(key, "Artist"):
		text(&t.artist, value, allocator)
	case strings.equal_fold(key, "Album Artist"), strings.equal_fold(key, "AlbumArtist"):
		text(&t.album_artist, value, allocator)
	case strings.equal_fold(key, "Album"):
		text(&t.album, value, allocator)
	case strings.equal_fold(key, "Genre"):
		text(&t.genre, value, allocator)
	case strings.equal_fold(key, "Comment"):
		text(&t.comment, value, allocator)
	case strings.equal_fold(key, "Year"):
		if t.year == nil {
			if year, ok := leading_number(value); ok do t.year = year
		}
	case strings.equal_fold(key, "Track"):
		pair(&t.track, &t.track_total, value)
	case strings.equal_fold(key, "Disc"):
		pair(&t.disc, &t.disc_total, value)
	}
}

// The number s starts with, after spaces; false when it starts with none or with 0.
@(private = "file")
leading_number :: proc(text: string) -> (n: int, ok: bool) {
	s := strings.trim_left_space(text)
	end := 0
	for end < len(s) && end < 9 && s[end] >= '0' && s[end] <= '9' do end += 1
	n = strconv.parse_int(s[:end]) or_return
	return n, n > 0
}
