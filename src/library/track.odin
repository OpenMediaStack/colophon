// Colophon's library: finding the audio files of folders, reading their tags and
// audio properties, and writing them back. No UI types.
package library

import "base:runtime"
import "core:hash"
import "core:slice"
import "core:strings"
import "core:time"

import "../mpa"

// The extensions of the files Colophon reads, without the dot, matched whatever
// their case. Later versions add other formats here.
AUDIO_EXTENSIONS :: [?]string{"mp3"}

// An audio file found in an opened folder. Free it with destroy_track.
Track :: struct {
	path:     string,
	size:     i64,
	// The zero time when the system does not say.
	modified: time.Time,
	// Its tags and audio properties, when error is .None: the file stays in the
	// library either way.
	metadata: Metadata,
	error:    Read_Error,
}

Read_Error :: enum u8 {
	None,
	// The file is gone, or Colophon may not read it.
	Cannot_Open,
	// The file holds no MPEG audio Colophon can read, or starts with an ID3v2 header it
	// cannot use.
	Damaged,
}

// What Colophon read in a file.
Metadata :: struct {
	tags:    Tags,
	audio:   Audio_Properties,
	formats: Tag_Formats,
}

// The fields Colophon shows and edits, the same for every format. A field the file
// does not have is nil.
Tags :: struct {
	title:        Maybe(string),
	artist:       Maybe(string),
	album_artist: Maybe(string),
	album:        Maybe(string),
	year:         Maybe(int),
	track:        Maybe(int),
	track_total:  Maybe(int),
	disc:         Maybe(int),
	disc_total:   Maybe(int),
	genre:        Maybe(string),
	comment:      Maybe(string),
	// nil for none; the file's own, found without reading its bytes; or one held in
	// memory, to write.
	cover:        Cover_State,
}

// The cover of a track. A scan never reads pictures: a file's cover is known by its
// frame alone, and read on demand with read_cover. A cover to write holds its bytes.
Cover_State :: union {
	Own_Cover,
	Cover,
}

// The file's own cover, whose bytes stay in the file: its picture frame, of this many
// bytes.
Own_Cover :: struct {
	size: int,
}

// A cover held in memory with its MIME type: a JPEG or a PNG when Colophon made it,
// whatever the file names when read from one. Free it with destroy_cover.
Cover :: struct {
	mime: string,
	data: []u8,
}

// What tells the covers of two tracks apart without reading the files: a file's own
// by its frame's size, one in memory by its bytes. Two files whose picture frames
// have one size therefore look the same; and a file's own is keyed by its first
// picture frame, while read_cover gives the front cover when it comes later, since
// the type sits in the data a scan skips.
Cover_Key :: struct {
	size: int,
	hash: u64,
}

// The key of a cover; nil for none.
cover_key :: proc(state: Cover_State) -> Maybe(Cover_Key) {
	switch c in state {
	case Own_Cover:
		return Cover_Key{c.size, 0}
	case Cover:
		return Cover_Key{len(c.data), hash.fnv64a(c.data)}
	}
	return nil
}

// Whether a track's cover is the same in two sets of its tags: a file's own cover is
// itself whatever its frame's size, which a conversion changes; one held in memory
// is its bytes.
same_cover :: proc(a, b: Cover_State) -> bool {
	switch c in a {
	case Own_Cover:
		_, own := b.(Own_Cover)
		return own
	case Cover:
		other, held := b.(Cover)
		return held && c.mime == other.mime && slice.equal(c.data, other.data)
	}
	return b == nil
}

// Whether two sets of a track's tags hold the same values.
same_tags :: proc(a, b: Tags) -> bool {
	return(
		a.title == b.title &&
		a.artist == b.artist &&
		a.album_artist == b.album_artist &&
		a.album == b.album &&
		a.year == b.year &&
		a.track == b.track &&
		a.track_total == b.track_total &&
		a.disc == b.disc &&
		a.disc_total == b.disc_total &&
		a.genre == b.genre &&
		a.comment == b.comment &&
		same_cover(a.cover, b.cover) \
	)
}

// A copy of a cover's string and bytes, allocated with allocator. Free it with
// destroy_cover.
clone_cover :: proc(
	cover: Cover,
	allocator := context.allocator,
) -> (
	clone: Cover,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	clone.mime = strings.clone(cover.mime, allocator) or_return
	clone.data = slice.clone(cover.data, allocator) or_return
	return
}

// Frees a cover's string and bytes, allocated with allocator.
destroy_cover :: proc(cover: ^Cover, allocator := context.allocator) {
	delete(cover.mime, allocator)
	delete(cover.data, allocator)
	cover^ = {}
}

// The audio of a file whose MPEG frames could be read: a track whose audio cannot
// be read is .Damaged, so every value is known.
// Constant or variable, as the encoder wrote it.
Bitrate_Mode :: mpa.Bitrate_Mode

Audio_Properties :: struct {
	duration:     time.Duration,
	bitrate_kbps: int,
	bitrate_mode: Bitrate_Mode,
	// In hertz.
	sample_rate:  int,
	channels:     int,
}

Id3v2_Version :: enum u8 {
	V2_2,
	V2_3,
	V2_4,
}

Id3v1_Version :: enum u8 {
	V1_0,
	V1_1,
}

// The tags a file holds: an ID3v2 tag, an ID3v1 tag, an APE tag. The Tags column
// shows them, and saving keeps or converts them, so they belong to every format
// Colophon reads, as 1.0.0's list of formats did.
Tag_Formats :: struct {
	id3v2: Maybe(Id3v2_Version),
	id3v1: Maybe(Id3v1_Version),
	ape:   bool,
}

// Frees what a Track owns, with the allocator it was read with.
destroy_track :: proc(track: ^Track, allocator := context.allocator) {
	delete(track.path, allocator)
	destroy_tags(&track.metadata.tags, allocator)
	track^ = {}
}

// Frees the strings of tags, with the allocator they were made with.
destroy_tags :: proc(tags: ^Tags, allocator := context.allocator) {
	delete_text :: proc(text: Maybe(string), allocator: runtime.Allocator) {
		if s, ok := text.?; ok do delete(s, allocator)
	}
	delete_text(tags.title, allocator)
	delete_text(tags.artist, allocator)
	delete_text(tags.album_artist, allocator)
	delete_text(tags.album, allocator)
	delete_text(tags.genre, allocator)
	delete_text(tags.comment, allocator)
	if cover, held := &tags.cover.(Cover); held do destroy_cover(cover, allocator)
	tags^ = {}
}

// A copy of tags whose strings are allocated with allocator.
clone_tags :: proc(
	tags: Tags,
	allocator := context.allocator,
) -> (
	clone: Tags,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	clone = tags
	clone.title = clone_text(tags.title, allocator) or_return
	clone.artist = clone_text(tags.artist, allocator) or_return
	clone.album_artist = clone_text(tags.album_artist, allocator) or_return
	clone.album = clone_text(tags.album, allocator) or_return
	clone.genre = clone_text(tags.genre, allocator) or_return
	clone.comment = clone_text(tags.comment, allocator) or_return
	if cover, held := tags.cover.(Cover); held do clone.cover = clone_cover(cover, allocator) or_return
	return
}

@(private)
clone_text :: proc(
	text: Maybe(string),
	allocator: runtime.Allocator,
) -> (
	Maybe(string),
	runtime.Allocator_Error,
) {
	s, ok := text.?
	if !ok do return nil, nil
	return strings.clone(s, allocator)
}

@(private, rodata)
ID3V2_NAMES := [Id3v2_Version]string {
	.V2_2 = "ID3v2.2",
	.V2_3 = "ID3v2.3",
	.V2_4 = "ID3v2.4",
}

@(private, rodata)
ID3V1_NAMES := [Id3v1_Version]string {
	.V1_0 = "ID3v1.0",
	.V1_1 = "ID3v1.1",
}

// The tag formats a file holds, as the Tags column shows them: "ID3v2.3, ID3v1.1",
// "" without any. Allocated with allocator.
tag_formats_string :: proc(f: Tag_Formats, allocator := context.allocator) -> string {
	names: [3]string
	count := 0
	if v, ok := f.id3v2.?; ok {
		names[count] = ID3V2_NAMES[v]
		count += 1
	}
	if v, ok := f.id3v1.?; ok {
		names[count] = ID3V1_NAMES[v]
		count += 1
	}
	if f.ape {
		names[count] = "APE"
		count += 1
	}
	return strings.join(names[:count], ", ", allocator)
}
