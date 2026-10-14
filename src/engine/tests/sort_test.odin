package engine_tests

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"

import "../../engine"
import lib "../../library"

// Adds a track to the library by hand, as if a scan had read it from path, and lists
// the library again. Its strings are copied.
@(private = "file")
add :: proc(
	e: ^engine.Engine,
	path: string,
	tags := lib.Tags{},
	audio := lib.Audio_Properties{},
	formats := lib.Tag_Formats{},
) -> engine.Track_Id {
	track := lib.Track {
		path = strings.clone(path),
		metadata = {tags = lib.clone_tags(tags), audio = audio, formats = formats},
	}
	append(&e.library.tracks, track)
	engine.execute(e, engine.Filter{e.filter})
	return engine.Track_Id(len(e.library.tracks) - 1)
}

@(private = "file")
expect_listed :: proc(
	t: ^testing.T,
	e: ^engine.Engine,
	want: []engine.Track_Id,
	loc := #caller_location,
) {
	got := e.listed[:]
	if !testing.expectf(t, len(got) == len(want), "got %v, want %v", got, want, loc = loc) do return
	for id, i in got do testing.expectf(t, id == want[i], "got %v, want %v", got, want, loc = loc)
}

@(test)
ties_follow_the_album_then_the_library :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	a := add(&e, "/m/a.mp3", {genre = "Folk", album = "B", disc = 1, track = 2})
	b := add(&e, "/m/b.mp3", {genre = "Folk", album = "B", disc = 1, track = 1})
	c := add(&e, "/m/c.mp3", {genre = "Folk", album = "A", disc = 2, track = 1})
	d := add(&e, "/m/d.mp3", {genre = "Folk", album = "B", disc = 1, track = 1})
	f := add(&e, "/m/f.mp3", {genre = "Jazz", album = "A"})
	engine.execute(&e, engine.Sort_By{.Genre})
	expect_listed(t, &e, {c, b, d, a, f})
	engine.execute(&e, engine.Sort_By{.Genre})
	expect_listed(t, &e, {f, c, b, d, a})
}

@(test)
a_missing_value_comes_first_when_sorting_down :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	none := add(&e, "/m/a.mp3")
	old := add(&e, "/m/b.mp3", {year = 1999})
	new := add(&e, "/m/c.mp3", {year = 2024})
	engine.execute(&e, engine.Sort_By{.Year})
	expect_listed(t, &e, {old, new, none})
	engine.execute(&e, engine.Sort_By{.Year})
	expect_listed(t, &e, {none, new, old})
}

@(test)
every_column_sorts_by_its_value :: proc(t: ^testing.T) {
	Case :: struct {
		column:        engine.Sort_Column,
		first, second: lib.Tags,
		audio:         [2]lib.Audio_Properties,
		formats:       [2]lib.Tag_Formats,
		paths:         [2]string,
	}
	cases := [?]Case {
		{column = .Number, first = {track = 2}, second = {track = 10}},
		{column = .Title, first = {title = "apple"}, second = {title = "Banana"}},
		{column = .Artist, first = {artist = "Abba"}, second = {artist = "beck"}},
		{column = .Album, first = {album = "alpha"}, second = {album = "Beta"}},
		{column = .Year, first = {year = 1971}, second = {year = 2001}},
		{column = .Genre, first = {genre = "folk"}, second = {genre = "Jazz"}},
		{column = .Time, audio = {{duration = 3 * time.Second}, {duration = 5 * time.Second}}},
		{column = .Bitrate, audio = {{bitrate_kbps = 128}, {bitrate_kbps = 320}}},
		{column = .Tags, formats = {{ape = true}, {id3v2 = .V2_4}}},
		{column = .File, paths = {"/m/z/a.mp3", "/m/a/b.mp3"}},
		{column = .Folder, paths = {"/m/a/z.mp3", "/m/b/a.mp3"}},
	}
	for c in cases {
		e: engine.Engine
		engine.init(&e)
		defer engine.destroy(&e)
		paths := c.paths
		if paths[0] == "" do paths = {"/m/b.mp3", "/m/a.mp3"}
		// Added second first, so that library order alone would get it wrong.
		second := add(&e, paths[1], c.second, c.audio[1], c.formats[1])
		first := add(&e, paths[0], c.first, c.audio[0], c.formats[0])
		engine.execute(&e, engine.Sort_By{c.column})
		testing.expectf(
			t,
			len(e.listed) == 2 && e.listed[0] == first && e.listed[1] == second,
			"%v: %v",
			c.column,
			e.listed,
		)
	}
}

@(test)
a_zero_time_or_bitrate_is_unknown :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	five := add(&e, "/m/a.mp3", audio = {duration = 5 * time.Second, bitrate_kbps = 320})
	zero := add(&e, "/m/b.mp3")
	three := add(&e, "/m/c.mp3", audio = {duration = 3 * time.Second, bitrate_kbps = 128})
	engine.execute(&e, engine.Sort_By{.Time})
	expect_listed(t, &e, {three, five, zero})
	engine.execute(&e, engine.Sort_By{.Bitrate})
	expect_listed(t, &e, {three, five, zero})
}

@(test)
the_filter_ignores_spaces_around_it_and_greek_final_sigmas :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	kite := add(&e, "/m/a.mp3", {artist = "Marlowe Kite"})
	road := add(&e, "/m/b.mp3", {title = "ΟΔΟΣ"})
	engine.execute(&e, engine.Filter{"  marlowe  "})
	expect_listed(t, &e, {kite})
	engine.execute(&e, engine.Filter{"οδος"})
	expect_listed(t, &e, {road})
}

@(test)
the_engine_takes_back_its_own_source_and_filter :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	kite := add(&e, "/m/a.mp3", {artist = "Marlowe Kite"})
	add(&e, "/m/b.mp3", {artist = "Someone Else"})
	engine.execute(&e, engine.Show_Source{engine.Artist{"Marlowe Kite"}})
	engine.execute(&e, engine.Show_Source{e.source})
	engine.execute(&e, engine.Filter{"Marlowe"})
	engine.execute(&e, engine.Filter{e.filter})
	testing.expect_value(t, e.source, engine.Source(engine.Artist{"Marlowe Kite"}))
	testing.expect_value(t, e.filter, "Marlowe")
	expect_listed(t, &e, {kite})
}

@(test)
an_album_is_set_apart_by_its_album_artist_else_its_artist :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	add(&e, "/m/a.mp3", {album = "Hits", album_artist = "Various", artist = "A"})
	add(&e, "/m/b.mp3", {album = "Hits", album_artist = "Various", artist = "B"})
	add(&e, "/m/c.mp3", {album = "Hits", artist = "C"})
	g := engine.groups(&e)
	defer engine.destroy_groups(&g)
	if !testing.expect_value(t, len(g.albums), 2) do return
	testing.expect_value(t, g.albums[0].key, engine.Album_Key{"Hits", "C"})
	testing.expect_value(t, g.albums[1].key, engine.Album_Key{"Hits", "Various"})
	testing.expect_value(t, g.albums[1].tracks, 2)
}

@(test)
groups_count_the_tracks_and_find_the_first_cover :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	for i in 0 ..< 3 {
		path := fmt.tprintf("/m/%d.mp3", i)
		tags := lib.Tags {
			album  = "Hits",
			artist = i < 2 ? "A" : "b",
		}
		if i > 0 do tags.cover = lib.Own_Cover{}
		add(&e, path, tags)
	}
	add(&e, "/m/3.mp3", {album = "another", artist = "a"})
	g := engine.groups(&e)
	defer engine.destroy_groups(&g)
	if !testing.expect_value(t, len(g.albums), 3) do return
	testing.expect_value(t, g.albums[0].key.title, "another")
	testing.expect_value(t, g.albums[0].cover_track, nil)
	testing.expect_value(t, g.albums[1].key, engine.Album_Key{"Hits", "A"})
	testing.expect_value(t, g.albums[1].tracks, 2)
	testing.expect_value(t, g.albums[1].cover_track, engine.Track_Id(1))
	if !testing.expect_value(t, len(g.artists), 3) do return
	testing.expect_value(t, g.artists[0], engine.Artist_Count{"A", 2})
	testing.expect_value(t, g.artists[1], engine.Artist_Count{"a", 1})
	testing.expect_value(t, g.artists[2], engine.Artist_Count{"b", 1})
}
