package engine

import "core:path/filepath"

import lib "../library"

// What the inspector shows of the selected tracks; nil when nothing is selected.
Inspection :: union {
	Unreadable_Track,
	Summary,
}

// One track is selected, and its tags could not be read.
Unreadable_Track :: struct {
	track: Track_Id,
	error: lib.Read_Error,
}

// One value of the selected tracks: the same for all of them, or not. nil when no
// selected track has a value.
Shared :: union($T: typeid) {
	T,
	Mixed,
}

// The selected tracks do not all have the same value, some having none perhaps.
Mixed :: struct {}

// The audio properties shown in one line, when every track shares them.
Audio_Line :: struct {
	bitrate_kbps: int,
	// In hertz.
	sample_rate:  int,
	mode:         lib.Bitrate_Mode,
}

// The selected tracks whose tags could be read, field by field. Its strings belong to
// the engine: it is valid until the next command or poll.
Summary :: struct {
	// How many tracks are selected, the unreadable ones included.
	count:        int,
	unreadable:   int,
	// The title of a single track; for one without a title tag, its file name.
	heading:      Maybe(string),
	title:        Shared(string),
	artist:       Shared(string),
	album_artist: Shared(string),
	album:        Shared(string),
	year:         Shared(int),
	track:        Shared(int),
	track_total:  Shared(int),
	disc:         Shared(int),
	disc_total:   Shared(int),
	genre:        Shared(string),
	comment:      Shared(string),
	audio:        Shared(Audio_Line),
	formats:      Shared(lib.Tag_Formats),
	// The tag versions saving writes the selected tracks in.
	versions:     Shared(lib.Tag_Versions),
	// The size of every selected file, in bytes.
	size:         i64,
	// The fields with a value waiting to be saved, in at least one selected track.
	modified:     Fields,
	// The tags the selected tracks with pending changes will hold once saved.
	saved_as:     Shared(lib.Tag_Formats),
	// How many of them saving converts to other tags or versions.
	converted:    int,
	// What the ID3v1 tags of the selected tracks with pending changes will lose.
	id3v1_losses: lib.Id3v1_Losses,
}

// What the inspector shows of the selected tracks. It walks the whole selection: call
// it once after each command or poll that changed something, not every frame.
inspect :: proc(e: ^Engine) -> Inspection {
	selected := e.selection.tracks[:]
	switch len(selected) {
	case 0:
		return nil
	case 1:
		track := &e.library.tracks[selected[0]]
		if track.error != .None do return Unreadable_Track{selected[0], track.error}
	}
	return summarise(e, selected)
}

@(private = "file")
summarise :: proc(e: ^Engine, selected: []Track_Id) -> (s: Summary) {
	s.count = len(selected)
	read := 0
	for id in selected {
		track := &e.library.tracks[id]
		s.size += track.size
		tags, readable := shown_tags(e, id)
		if !readable do continue
		first := read == 0
		read += 1
		share(&s.title, tags.title, first)
		share(&s.artist, tags.artist, first)
		share(&s.album_artist, tags.album_artist, first)
		share(&s.album, tags.album, first)
		share(&s.year, tags.year, first)
		share(&s.track, tags.track, first)
		share(&s.track_total, tags.track_total, first)
		share(&s.disc, tags.disc, first)
		share(&s.disc_total, tags.disc_total, first)
		share(&s.genre, tags.genre, first)
		share(&s.comment, tags.comment, first)
		share(&s.audio, audio_line(track.metadata.audio), first)
		share(&s.formats, Maybe(lib.Tag_Formats)(track.metadata.formats), first)
		versions, _ := versions_of(e, id)
		share(&s.versions, Maybe(lib.Tag_Versions)(versions), first)
		if s.count == 1 {
			s.heading = tags.title.? or_else filepath.stem(track.path)
		}
	}
	s.unreadable = s.count - read
	s.modified = modified_fields(e, selected)
	pending_seen := false
	for id in selected {
		pending := pending_tags(e, id) or_continue
		formats := e.library.tracks[id].metadata.formats
		versions, _ := versions_of(e, id)
		after := lib.formats_after_write(formats, pending, versions)
		share(&s.saved_as, Maybe(lib.Tag_Formats)(after), !pending_seen)
		pending_seen = true
		if after != formats do s.converted += 1
		if version, ok := versions.id3v1.?; ok do s.id3v1_losses += lib.id3v1_losses(pending, version)
	}
	return
}

// Folds one more track's value into what the tracks have in common; first is true
// for the first track.
@(private)
share :: proc(shared: ^Shared($T), value: Maybe(T), first: bool) {
	if first {
		if v, ok := value.?; ok do shared^ = v
		return
	}
	switch current in shared^ {
	case T:
		if v, ok := value.?; !ok || v != current do shared^ = Mixed{}
	case Mixed:
	case:
		if value != nil do shared^ = Mixed{}
	}
}

// The audio line of a track, or nil when its bitrate or sample rate is unknown.
@(private = "file")
audio_line :: proc(audio: lib.Audio_Properties) -> Maybe(Audio_Line) {
	if audio.bitrate_kbps <= 0 || audio.sample_rate <= 0 do return nil
	return Audio_Line{audio.bitrate_kbps, audio.sample_rate, audio.bitrate_mode}
}
