package library

import "base:runtime"
import "core:os"
import "core:strings"

import id3 "../../libs/odid3"
import "../mpa"

// Reads the file at path: its size and date, its tags through odid3 and its audio
// through mpa. A file that cannot be read gives a Track all the same, with error
// saying why. The Track's strings are allocated with allocator; free it with
// destroy_track. Scratch memory comes from allocator too and is freed before
// returning. Safe to call from any thread, with an allocator that is.
read_track :: proc(path: string, allocator := context.allocator) -> (track: Track) {
	track.path = strings.clone(path, allocator)
	info, stat_err := os.stat(path, allocator)
	if stat_err != nil {
		track.error = .Cannot_Open
		return
	}
	track.size = info.size
	track.modified = info.modification_time
	os.file_info_delete(info, allocator)
	tags, read_err := id3.read_file(path, {skip_picture_data = true}, allocator)
	if read_err != nil {
		track.error = is_open_error(read_err) ? .Cannot_Open : .Damaged
		return
	}
	defer id3.destroy(&tags)
	audio := tags.layout.audio
	properties, audio_err := mpa.read_file(path, audio.offset, audio.size, allocator)
	if audio_err != nil {
		_, cannot_open := audio_err.(os.Error)
		track.error = cannot_open ? .Cannot_Open : .Damaged
		return
	}
	track.metadata = {
		tags = primary_tags(path, &tags, allocator),
		audio = {
			duration = properties.duration,
			bitrate_kbps = properties.bitrate_kbps,
			bitrate_mode = properties.bitrate_mode,
			sample_rate = properties.sample_rate,
			channels = properties.channels,
		},
		formats = formats_of(&tags),
	}
	return
}

@(private = "file")
is_open_error :: proc(err: id3.Error) -> bool {
	_, ok := err.(os.Error)
	return ok
}

// The fields of the file's richest tag, ID3v2, else ID3v1, else APE, never mixed
// field by field: a mix would hide the differences between two tags of one file.
@(private = "file")
primary_tags :: proc(path: string, tags: ^id3.Tags, allocator: runtime.Allocator) -> Tags {
	if tags.v2.version != .None {
		t := id3_fields(&tags.v2, allocator)
		t.cover = own_cover(&tags.v2)
		return t
	}
	// Without ID3v2, odid3 gives each field of the file from ID3v1.
	if tags.v1.version != .None do return id3_fields(tags, allocator)
	if tags.layout.ape.size > 0 {
		t, _ := read_ape(path, tags.layout.ape.offset, tags.layout.ape.size, allocator)
		return t
	}
	return {}
}

// The generic fields of an ID3v2 tag, or of a file's ID3v1 tag through its Tags.
@(private = "file")
id3_fields :: proc(tag: ^$T, allocator: runtime.Allocator) -> (t: Tags) {
	text :: proc(tag: ^T, field: id3.Field, allocator: runtime.Allocator) -> Maybe(string) {
		value := id3.get(tag, field, allocator)
		if len(value) > 0 do return value
		delete(value, allocator)
		return nil
	}
	number :: proc(n: int) -> Maybe(int) {
		return n > 0 ? n : nil
	}
	t.title = text(tag, .Title, allocator)
	t.artist = text(tag, .Artist, allocator)
	t.album_artist = text(tag, .Album_Artist, allocator)
	t.album = text(tag, .Album, allocator)
	t.genre = text(tag, .Genre, allocator)
	t.comment = text(tag, .Comment, allocator)
	if year, ok := id3.year(tag); ok do t.year = year
	track, track_total := id3.track(tag)
	t.track, t.track_total = number(track), number(track_total)
	disc, disc_total := id3.disc(tag)
	t.disc, t.disc_total = number(disc), number(disc_total)
	return
}

// The file's own cover, by its first picture frame: picture data is not read, so this
// looks at frame ids and sizes. Which picture read_cover gives, the front cover else
// the first, is known only once read.
@(private = "file")
own_cover :: proc(tag: ^id3.Tag) -> Cover_State {
	for f in tag.frames {
		if kind, known := id3.frame_kind(f.id, tag.version); known && kind == .APIC do return Own_Cover{f.size}
	}
	return nil
}

// The cover of the file at path, the front cover else its first picture, read from
// the file: a scan never reads pictures. found is false for a file without one, or
// that cannot be read, or whose picture is a link. The cover is allocated with
// allocator; free it with destroy_cover.
read_cover :: proc(path: string, allocator := context.allocator) -> (cover: Cover, found: bool) {
	tags, read_err := id3.read_file(path, {}, context.temp_allocator)
	if read_err != nil do return
	defer id3.destroy(&tags)
	picture, has, err := id3.front_cover(&tags.v2, context.temp_allocator)
	if err != nil || !has || picture.mime == "-->" do return
	return clone_cover({picture.mime, picture.data}, allocator), true
}

@(private = "file")
formats_of :: proc(tags: ^id3.Tags) -> (f: Tag_Formats) {
	switch tags.v2.version {
	case .None:
	case .V2_2:
		f.id3v2 = .V2_2
	case .V2_3:
		f.id3v2 = .V2_3
	case .V2_4:
		f.id3v2 = .V2_4
	}
	switch tags.v1.version {
	case .None:
	case .V1_0:
		f.id3v1 = .V1_0
	case .V1_1:
		f.id3v1 = .V1_1
	}
	f.ape = tags.layout.ape.size > 0
	return
}
