package library

import "core:os"
import "core:strings"

import id3 "../../libs/odid3"
import "../mpa"

// Reads the file at path: its size and date, its tags through odid3 and its audio
// through mpa. A file that cannot be read gives a Track all the same, with
// read_error saying why. The Track's strings are allocated with allocator; free it
// with destroy_track. Scratch memory comes from allocator too and is freed before
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
	properties, audio_err := mpa.read_file(path, audio.offset, audio.size)
	if audio_err != nil {
		_, cannot_open := audio_err.(os.Error)
		track.error = cannot_open ? .Cannot_Open : .Damaged
		return
	}
	track.metadata = {
		tags = tags_of(&tags, allocator),
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

// The generic fields of a file's ID3 tags: ID3v2's, else ID3v1's.
@(private = "file")
tags_of :: proc(tags: ^id3.Tags, allocator := context.allocator) -> (t: Tags) {
	text :: proc(
		tags: ^id3.Tags,
		field: id3.Field,
		allocator := context.allocator,
	) -> Maybe(string) {
		value := id3.get(tags, field, context.temp_allocator)
		if len(value) == 0 do return nil
		return strings.clone(value, allocator)
	}
	number :: proc(n: int) -> Maybe(int) {
		return n > 0 ? n : nil
	}
	t.title = text(tags, .Title, allocator)
	t.artist = text(tags, .Artist, allocator)
	t.album_artist = text(tags, .Album_Artist, allocator)
	t.album = text(tags, .Album, allocator)
	t.genre = text(tags, .Genre, allocator)
	t.comment = text(tags, .Comment, allocator)
	if year, ok := id3.year(tags); ok do t.year = year
	track, track_total := id3.track(tags)
	t.track, t.track_total = number(track), number(track_total)
	disc, disc_total := id3.disc(tags)
	t.disc, t.disc_total = number(disc), number(disc_total)
	cover, found, _ := id3.front_cover(&tags.v2, allocator)
	if found {
		t.has_cover = true
		id3.destroy(&cover, allocator)
	}
	return
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
