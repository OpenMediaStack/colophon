// Colophon's library: finding the audio files of folders, reading their tags and
// audio properties, and writing them back. No UI types.
package library

import "base:runtime"
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
	// Its tags and audio properties, when read_error is .None: the file stays in the
	// library either way.
	metadata: Metadata,
	error:    Read_Error,
}

Read_Error :: enum u8 {
	None,
	// The file is gone, or Colophon may not read it.
	Cannot_Open,
	// The file holds no MPEG audio Colophon can read.
	Damaged,
}

Metadata :: struct {
	tags:    Tags,
	audio:   Audio_Properties,
	// The tag formats the file holds, in the order they come in it.
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
	has_cover:    bool,
}

Audio_Properties :: struct {
	duration:     time.Duration,
	bitrate_kbps: int,
	bitrate_mode: mpa.Bitrate_Mode,
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

// The tags a file holds: an ID3v2 tag, an ID3v1 tag, an APE tag.
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
	for text in ([?]Maybe(string) {
			tags.title,
			tags.artist,
			tags.album_artist,
			tags.album,
			tags.genre,
			tags.comment,
		}) {
		if s, ok := text.?; ok do delete(s, allocator)
	}
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
	return clone_string(s, allocator)
}

@(private)
clone_string :: proc(
	s: string,
	allocator: runtime.Allocator,
) -> (
	string,
	runtime.Allocator_Error,
) {
	bytes, err := make([]u8, len(s), allocator)
	if err != nil do return "", err
	copy(bytes, s)
	return string(bytes), nil
}
