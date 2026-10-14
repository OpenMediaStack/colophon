package engine

import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

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

// Where the table's tracks come from: what the sidebar chose, every track at first.
Source :: union #no_nil {
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

// Lists the tracks of a source in the table. The engine keeps a copy of the source.
Show_Source :: struct {
	source: Source,
}

// Lists only the tracks whose title, artist, album or file name holds this text,
// ignoring case and the spaces around it. The engine keeps a copy of the text.
Filter :: struct {
	text: string,
}

// Sorts the table by a column, or the other way round when it is sorted by it already.
Sort_By :: struct {
	column: Sort_Column,
}

// The folders, albums and artists of the library, with how many tracks each has: the
// folders in the order of the roots, the others in alphabetical order. Free it with
// destroy_groups.
Groups :: struct {
	folders: [dynamic]Folder_Count,
	albums:  [dynamic]Album,
	artists: [dynamic]Artist_Count,
}

// A folder of the library, with how many of its tracks lie under it.
Folder_Count :: struct {
	path:   string,
	tracks: int,
}

// An album of the sidebar.
Album :: struct {
	key:         Album_Key,
	tracks:      int,
	// The first of its tracks with a cover, to show it.
	cover_track: Maybe(Track_Id),
}

// An artist of the sidebar.
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

// Counts the tracks under each root and groups the readable ones by album and by
// artist, from their files' tags. The strings belong to the roots and the tracks: the
// groups stay valid until the library changes.
groups :: proc(e: ^Engine, allocator := context.allocator) -> (g: Groups) {
	Album_Entry :: struct {
		folded:    string,
		key:       Album_Key,
		track:     Track_Id,
		has_cover: bool,
	}
	Artist_Entry :: struct {
		folded, name: string,
	}
	g.folders = make([dynamic]Folder_Count, 0, len(e.library.roots), allocator)
	for root in e.library.roots {
		count := 0
		for &track in e.library.tracks do if within(track.path, root) do count += 1
		append(&g.folders, Folder_Count{root, count})
	}
	albums := make([dynamic]Album_Entry, context.temp_allocator)
	artists := make([dynamic]Artist_Entry, context.temp_allocator)
	for &track, i in e.library.tracks {
		if track.error != .None do continue
		tags := &track.metadata.tags
		if key, ok := album_key(tags); ok {
			append(&albums, Album_Entry{lower(key.title), key, Track_Id(i), tags.has_cover})
		}
		if artist, ok := tags.artist.?; ok do append(&artists, Artist_Entry{lower(artist), artist})
	}
	// Sorted so that the tracks of an album or an artist follow each other, in library
	// order: one pass then counts them.
	slice.sort_by_cmp(albums[:], proc(a, b: Album_Entry) -> slice.Ordering {
		order := compare_names(a.folded, b.folded, a.key.title, b.key.title)
		if order == .Equal do order = compare_artists(a.key.artist, b.key.artist)
		if order == .Equal do order = slice.cmp(a.track, b.track)
		return order
	})
	slice.sort_by_cmp(artists[:], proc(a, b: Artist_Entry) -> slice.Ordering {
		return compare_names(a.folded, b.folded, a.name, b.name)
	})
	g.albums = make([dynamic]Album, allocator)
	for entry, i in albums {
		if i == 0 || entry.key != albums[i - 1].key do append(&g.albums, Album{key = entry.key})
		album := &g.albums[len(g.albums) - 1]
		album.tracks += 1
		if album.cover_track == nil && entry.has_cover do album.cover_track = entry.track
	}
	g.artists = make([dynamic]Artist_Count, allocator)
	for entry, i in artists {
		if i == 0 || entry.name != artists[i - 1].name do append(&g.artists, Artist_Count{entry.name, 0})
		g.artists[len(g.artists) - 1].tracks += 1
	}
	return
}

// Frees the lists of groups, whose strings belong to the library.
destroy_groups :: proc(g: ^Groups) {
	delete(g.folders)
	delete(g.albums)
	delete(g.artists)
	g^ = {}
}

// Alphabetical, ignoring case, from the names lowered once; names equal but for case
// keep a fixed order.
@(private = "file")
compare_names :: proc(a_folded, b_folded, a, b: string) -> slice.Ordering {
	if order := slice.Ordering(strings.compare(a_folded, b_folded)); order != .Equal do return order
	return slice.Ordering(strings.compare(a, b))
}

// An album without an artist comes before those with one, as in 1.0.0.
@(private = "file")
compare_artists :: proc(a, b: Maybe(string)) -> slice.Ordering {
	x, has_x := a.?
	y, has_y := b.?
	if has_x != has_y do return has_x ? .Greater : .Less
	return slice.Ordering(strings.compare(x, y))
}

@(private = "file")
lower :: proc(s: string) -> string {
	return strings.to_lower(s, context.temp_allocator)
}

// Lowers s for the filter to find it whatever its case. Greek has two lowercase
// sigmas, ς at the end of a word and σ elsewhere: both become σ, so that "ΟΔΟΣ"
// lowered to "οδοσ" is found by "οδος".
@(private = "file")
fold :: proc(s: string) -> string {
	folded, _ := strings.replace_all(lower(s), "ς", "σ", context.temp_allocator)
	return folded
}

// Lists the tracks of the source again, filtered and sorted: those whose title,
// artist, album or file name holds the filter, ignoring case, sorted by the sort or
// else in library order.
@(private)
relist :: proc(e: ^Engine) {
	clear(&e.listed)
	filter := fold(strings.trim_space(e.filter))
	for _, i in e.library.tracks {
		id := Track_Id(i)
		if in_source(e, id, e.source) && (len(filter) == 0 || matches(e, id, filter)) do append(&e.listed, id)
	}
	sort, sorted := e.sort.?
	if !sorted do return
	keyed := make([]Keyed, len(e.listed), context.temp_allocator)
	for id, i in e.listed do keyed[i] = {sort_key(e, id, sort.column), id}
	slice.sort_by_cmp_with_data(keyed, compare_keyed, &sort)
	for k, i in keyed do e.listed[i] = k.id
}

// The order of the table: the sort's column, up or down, then the order of an
// album, then the library's.
@(private = "file")
compare_keyed :: proc(a, b: Keyed, data: rawptr) -> slice.Ordering {
	sort := (^Sort)(data)
	order := compare_values(a.key.primary, b.key.primary)
	if sort.descending do order = slice.Ordering(-int(order))
	if order == .Equal do order = compare_values(a.key.album, b.key.album)
	if order == .Equal do order = slice.cmp(a.key.disc, b.key.disc)
	if order == .Equal do order = slice.cmp(a.key.track, b.key.track)
	if order == .Equal do order = slice.cmp(a.id, b.id)
	return order
}

@(private = "file")
in_source :: proc(e: ^Engine, id: Track_Id, source: Source) -> bool {
	track := &e.library.tracks[id]
	switch s in source {
	case All_Tracks:
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
		return ok && strings.contains(fold(s), filter)
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

// Numbers before text, and nothing last.
@(private = "file")
compare_values :: proc(a, b: Value) -> slice.Ordering {
	rank :: proc(v: Value) -> int {
		switch _ in v {
		case u64:
			return 0
		case string:
			return 1
		}
		return 2
	}
	if order := slice.cmp(rank(a), rank(b)); order != .Equal do return order
	#partial switch x in a {
	case u64:
		return slice.cmp(x, b.(u64))
	case string:
		return slice.Ordering(strings.compare(x, b.(string)))
	}
	return .Equal
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
	// A duration or a bitrate of 0 is unknown, as 1.0.0 read it.
	case .Time:
		duration := track.metadata.audio.duration
		if readable && duration > 0 do key.primary = u64(duration / time.Millisecond)
	case .Bitrate:
		bitrate := track.metadata.audio.bitrate_kbps
		if readable && bitrate > 0 do key.primary = u64(bitrate)
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

// The genres to suggest: those an ID3v1 tag can name and those of the files read, once
// each whatever their case, in alphabetical order. A genre only typed so far is not one
// of them. Allocated with allocator; the strings belong to the library. It reads every
// track: call it once after each change, not on every frame.
genres :: proc(e: ^Engine, allocator := context.allocator) -> []string {
	Named :: struct {
		folded, name: string,
	}
	all := make([dynamic]Named, context.temp_allocator)
	for name in lib.id3v1_genres(context.temp_allocator) do append(&all, Named{lower(name), name})
	for &track in e.library.tracks {
		if track.error != .None do continue
		if genre, ok := track.metadata.tags.genre.?; ok do append(&all, Named{lower(genre), genre})
	}
	// The first spelling of a genre wins: ID3v1's, then the first file's.
	slice.stable_sort_by(all[:], proc(a, b: Named) -> bool {return a.folded < b.folded})
	result := make([dynamic]string, 0, len(all), allocator)
	for named, i in all {
		if i > 0 && named.folded == all[i - 1].folded do continue
		append(&result, named.name)
	}
	return result[:]
}
