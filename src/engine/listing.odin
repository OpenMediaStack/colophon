package engine

import "core:path/filepath"
import "core:slice"
import "core:strings"

import lib "../library"

// An album: its title, and the album artist, or else the artist, that sets it apart
// from another album of the same title.
Album_Key :: struct {
	title:  string,
	artist: Maybe(string),
}

All_Tracks :: struct {}
// The tracks with changes waiting to be saved, or saved since Colophon started.
Recently_Changed :: struct {}
// The tracks whose tags could not be read.
Unreadable :: struct {}
// The tracks under a folder of the library.
Folder :: struct {
	path: string,
}
Artist :: struct {
	name: string,
}

// Where the table's tracks come from: what the sidebar chose. nil lists every track.
Source :: union {
	All_Tracks,
	Recently_Changed,
	Unreadable,
	Folder,
	Album_Key,
	Artist,
}

// What the table can be sorted by.
Sort_Column :: enum u8 {
	Number,
	Title,
	Artist,
	Album,
	Year,
	Genre,
	Time,
	Bitrate,
	Tags,
	File,
	Folder,
}

// The order of the table: by a column, up or down.
Sort :: struct {
	column:     Sort_Column,
	descending: bool,
}

// Lists the tracks of a source in the table.
Show_Source :: struct {
	source: Source,
}

// Lists only the tracks whose title, artist, album or file name holds this text.
Filter :: struct {
	text: string,
}

// Sorts the table by a column, or the other way round when it is sorted by it already.
Sort_By :: struct {
	column: Sort_Column,
}

// The albums and artists of the library, with how many tracks each has, in
// alphabetical order. Free it with destroy_groups.
Groups :: struct {
	albums:  [dynamic]Album,
	artists: [dynamic]Artist_Count,
}

Album :: struct {
	key:         Album_Key,
	tracks:      int,
	// The first of its tracks with a cover, to show it.
	cover_track: Maybe(Track_Id),
}

Artist_Count :: struct {
	name:   string,
	tracks: int,
}

// The album a track's tags make, or false without an album title.
album_key :: proc(tags: ^lib.Tags) -> (key: Album_Key, ok: bool) {
	key.title = tags.album.? or_return
	key.artist = tags.album_artist
	if key.artist == nil do key.artist = tags.artist
	return key, true
}

// Groups the readable tracks by album and by artist, from their files' tags. The
// strings belong to the tracks: the groups stay valid until the library changes.
groups :: proc(e: ^Engine, allocator := context.allocator) -> (g: Groups) {
	g.albums = make([dynamic]Album, allocator)
	g.artists = make([dynamic]Artist_Count, allocator)
	for &track, i in e.library.tracks {
		if track.error != .None do continue
		tags := &track.metadata.tags
		if key, ok := album_key(tags); ok {
			album := find_album(&g.albums, key)
			album.tracks += 1
			if album.cover_track == nil && tags.has_cover do album.cover_track = Track_Id(i)
		}
		if artist, ok := tags.artist.?; ok {
			count_artist(&g.artists, artist)
		}
	}
	slice.sort_by(g.albums[:], proc(a, b: Album) -> bool {
		return compare_names(a.key.title, b.key.title, artist_name(a.key), artist_name(b.key)) < 0
	})
	slice.sort_by(g.artists[:], proc(a, b: Artist_Count) -> bool {
		return compare_names(a.name, b.name, "", "") < 0
	})
	return
}

destroy_groups :: proc(g: ^Groups) {
	delete(g.albums)
	delete(g.artists)
	g^ = {}
}

@(private = "file")
find_album :: proc(albums: ^[dynamic]Album, key: Album_Key) -> ^Album {
	for &album in albums do if album.key == key do return &album
	append(albums, Album{key = key})
	return &albums[len(albums) - 1]
}

@(private = "file")
count_artist :: proc(artists: ^[dynamic]Artist_Count, name: string) {
	for &artist in artists {
		if artist.name == name {
			artist.tracks += 1
			return
		}
	}
	append(artists, Artist_Count{name, 1})
}

@(private = "file")
artist_name :: proc(key: Album_Key) -> string {
	return key.artist.? or_else ""
}

// Alphabetical, ignoring case; names equal but for case keep a fixed order.
@(private = "file")
compare_names :: proc(a, b, a_tie, b_tie: string) -> int {
	if c := strings.compare(lower(a), lower(b)); c != 0 do return c
	if c := strings.compare(a, b); c != 0 do return c
	return strings.compare(a_tie, b_tie)
}

@(private = "file")
lower :: proc(s: string) -> string {
	return strings.to_lower(s, context.temp_allocator)
}

// Lists the tracks of the source again, filtered and sorted: those whose title,
// artist, album or file name holds the filter, ignoring case, sorted by the sort or
// else in library order.
@(private)
relist :: proc(e: ^Engine) {
	clear(&e.listed)
	filter := lower(strings.trim_space(e.filter))
	for _, i in e.library.tracks {
		id := Track_Id(i)
		if in_source(e, id, e.source) && (len(filter) == 0 || matches(e, id, filter)) do append(&e.listed, id)
	}
	sort, sorted := e.sort.?
	if !sorted do return
	keyed := make([]Keyed, len(e.listed), context.temp_allocator)
	for id, i in e.listed do keyed[i] = {sort_key(e, id, sort.column), id}
	context.user_ptr = &sort
	slice.sort_by(keyed, proc(a, b: Keyed) -> bool {
		sort := (^Sort)(context.user_ptr)
		order := compare_values(a.key.primary, b.key.primary)
		if sort.descending do order = -order
		if order == 0 do order = compare_values(a.key.album, b.key.album)
		if order == 0 do order = compare_ints(a.key.disc, b.key.disc)
		if order == 0 do order = compare_ints(a.key.track, b.key.track)
		if order == 0 do order = compare_ints(int(a.id), int(b.id))
		return order < 0
	})
	for k, i in keyed do e.listed[i] = k.id
}

@(private = "file")
in_source :: proc(e: ^Engine, id: Track_Id, source: Source) -> bool {
	track := &e.library.tracks[id]
	switch s in source {
	case nil, All_Tracks:
		return true
	case Recently_Changed:
		return is_changed(e, id)
	case Unreadable:
		return track.error != .None
	case Folder:
		return within(track.path, s.path)
	case Album_Key:
		if track.error != .None do return false
		key, ok := album_key(&track.metadata.tags)
		return ok && key == s
	case Artist:
		if track.error != .None do return false
		artist, ok := track.metadata.tags.artist.?
		return ok && artist == s.name
	}
	return false
}

@(private = "file")
matches :: proc(e: ^Engine, id: Track_Id, filter: string) -> bool {
	holds :: proc(value: Maybe(string), filter: string) -> bool {
		s, ok := value.?
		return ok && strings.contains(lower(s), filter)
	}
	if holds(filepath.base(e.library.tracks[id].path), filter) do return true
	tags := shown_tags(e, id) or_return
	return holds(tags.title, filter) || holds(tags.artist, filter) || holds(tags.album, filter)
}

// A value to sort by: a number, text ignoring case, or nothing, which comes last
// when sorting up.
@(private = "file")
Value :: union {
	u64,
	string,
}

@(private = "file")
Sort_Key :: struct {
	primary: Value,
	// The order of an album, which settles ties: album, disc and track number.
	album:   Value,
	disc:    int,
	track:   int,
}

@(private = "file")
Keyed :: struct {
	key: Sort_Key,
	id:  Track_Id,
}

@(private = "file")
compare_values :: proc(a, b: Value) -> int {
	rank :: proc(v: Value) -> int {
		switch _ in v {
		case u64:
			return 0
		case string:
			return 1
		}
		return 2
	}
	if c := compare_ints(rank(a), rank(b)); c != 0 do return c
	#partial switch x in a {
	case u64:
		y := b.(u64)
		return x < y ? -1 : (x > y ? 1 : 0)
	case string:
		return strings.compare(x, b.(string))
	}
	return 0
}

@(private = "file")
compare_ints :: proc(a, b: int) -> int {
	return a < b ? -1 : (a > b ? 1 : 0)
}

@(private = "file")
sort_key :: proc(e: ^Engine, id: Track_Id, column: Sort_Column) -> (key: Sort_Key) {
	track := &e.library.tracks[id]
	text :: proc(value: Maybe(string)) -> Value {
		s, ok := value.?
		return ok ? Value(lower(s)) : nil
	}
	number :: proc(value: Maybe(int)) -> Value {
		n, ok := value.?
		return ok && n >= 0 ? Value(u64(n)) : nil
	}
	readable := track.error == .None
	tags, has_tags := shown_tags(e, id)
	empty: lib.Tags
	if !has_tags do tags = &empty
	file := filepath.base(track.path)
	switch column {
	case .Number:
		key.primary = number(tags.track)
	case .Title:
		key.primary = text(tags.title.? or_else file)
	case .Artist:
		key.primary = text(tags.artist)
	case .Album:
		key.primary = text(tags.album)
	case .Year:
		key.primary = number(tags.year)
	case .Genre:
		key.primary = text(tags.genre)
	case .Time:
		if readable do key.primary = u64(track.metadata.audio.duration / 1_000_000)
	case .Bitrate:
		if readable do key.primary = u64(track.metadata.audio.bitrate_kbps)
	case .Tags:
		formats :=
			readable ? lib.tag_formats_string(track.metadata.formats, context.temp_allocator) : ""
		if len(formats) > 0 do key.primary = lower(formats)
	case .File:
		key.primary = text(file)
	case .Folder:
		key.primary = text(filepath.dir(track.path))
	}
	key.album = text(tags.album)
	key.disc = tags.disc.? or_else 0
	key.track = tags.track.? or_else 0
	return
}
