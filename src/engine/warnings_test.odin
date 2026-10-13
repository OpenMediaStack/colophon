package engine

import "core:strings"
import "core:testing"

import lib "../library"

@(private = "file")
Fixture :: struct {
	path:         string,
	album:        string,
	track:        Maybe(int),
	album_artist: Maybe(string),
}

// The warnings of an engine whose library holds these tracks.
@(private = "file")
found :: proc(e: ^Engine, tracks: []Fixture) -> map[Track_Id]Warnings {
	init(e)
	for f in tracks {
		tags := lib.Tags {
			album        = f.album,
			track        = f.track,
			album_artist = f.album_artist,
		}
		track := lib.Track {
			path = strings.clone(f.path),
			metadata = {tags = lib.clone_tags(tags)},
		}
		append(&e.library.tracks, track)
	}
	return warnings(e, context.temp_allocator)
}

@(test)
a_track_without_a_number_stands_out_in_a_numbered_album :: proc(t: ^testing.T) {
	e: Engine
	defer destroy(&e)
	w := found(
		&e,
		{
			{"/music/a/1.mp3", "Analog Hearts", 1, nil},
			{"/music/a/2.mp3", "Analog Hearts", nil, nil},
			{"/music/b/3.mp3", "Field Notes", nil, nil},
			{"/music/b/4.mp3", "Field Notes", nil, nil},
		},
	)
	testing.expect_value(t, len(w), 1)
	testing.expect_value(t, w[1], Warnings{.Missing_Number})
	free_all(context.temp_allocator)
}

@(test)
an_album_artist_unlike_the_others_stands_out :: proc(t: ^testing.T) {
	e: Engine
	defer destroy(&e)
	w := found(
		&e,
		{
			{"/music/a/1.mp3", "Analog Hearts", 1, "Cassette Bloom"},
			{"/music/a/2.mp3", "Analog Hearts", 2, "Cassette Bloom"},
			{"/music/a/3.mp3", "Analog Hearts", 3, "Casette Bloom"},
		},
	)
	testing.expect_value(t, len(w), 1)
	testing.expect_value(t, w[2], Warnings{.Odd_Album_Artist})
	free_all(context.temp_allocator)
}

@(test)
a_tie_or_a_lone_track_raises_nothing :: proc(t: ^testing.T) {
	e: Engine
	defer destroy(&e)
	w := found(
		&e,
		{
			{"/music/a/1.mp3", "Analog Hearts", 1, "One"},
			{"/music/a/2.mp3", "Analog Hearts", 2, "Other"},
			{"/music/b/1.mp3", "Field Notes", nil, nil},
		},
	)
	testing.expect_value(t, len(w), 0)
	free_all(context.temp_allocator)
}

@(test)
the_same_title_in_two_folders_makes_two_albums :: proc(t: ^testing.T) {
	e: Engine
	defer destroy(&e)
	w := found(
		&e,
		{
			{"/music/a/1.mp3", "Greatest Hits", 1, "One"},
			{"/music/b/1.mp3", "Greatest Hits", nil, "Other"},
		},
	)
	testing.expect_value(t, len(w), 0)
	free_all(context.temp_allocator)
}

@(test)
most_tracks_without_an_album_artist_make_one_odd :: proc(t: ^testing.T) {
	e: Engine
	defer destroy(&e)
	w := found(
		&e,
		{
			{"/music/a/1.mp3", "Hits", 1, nil},
			{"/music/a/2.mp3", "Hits", 2, nil},
			{"/music/a/3.mp3", "Hits", 3, "Someone"},
		},
	)
	testing.expect_value(t, len(w), 1)
	testing.expect_value(t, w[2], Warnings{.Odd_Album_Artist})
	free_all(context.temp_allocator)
}
