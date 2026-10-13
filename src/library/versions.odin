package library

// The tag versions to write a file in; nil removes that tag.
Tag_Versions :: struct {
	id3v2: Maybe(Id3v2_Version),
	id3v1: Maybe(Id3v1_Version),
}

// Whether a file keeps the ID3v1 tag it has, always gets one, or never does.
Id3v1_Policy :: enum u8 {
	Keep,
	Always,
	Never,
}

// The versions Colophon writes the tracks the user chose none for in.
Write_Policy :: struct {
	id3v2: Id3v2_Version,
	id3v1: Id3v1_Policy,
}

// ID3v2.4, and ID3v1 kept where a file has one.
DEFAULT_WRITE_POLICY :: Write_Policy{.V2_4, .Keep}

// The versions to write a file holding formats in, following policy.
versions_following :: proc(policy: Write_Policy, formats: Tag_Formats) -> Tag_Versions {
	has_id3v1 := formats.id3v1 != nil
	keeps := policy.id3v1 == .Always || (policy.id3v1 == .Keep && has_id3v1)
	return {id3v2 = policy.id3v2, id3v1 = keeps ? Id3v1_Version.V1_1 : nil}
}

// The tag formats a file holding formats will have once tags are written into it in
// versions: its ID3v2 tag, its ID3v1 tag (an ID3v1.1 tag without a track number
// reads as ID3v1.0), and its APE tag, left as it is.
formats_after_write :: proc(
	formats: Tag_Formats,
	tags: ^Tags,
	versions: Tag_Versions,
) -> (
	after: Tag_Formats,
) {
	after.id3v2 = versions.id3v2
	if v, ok := versions.id3v1.?; ok {
		after.id3v1 = id3v1_track(tags, v) != nil ? Id3v1_Version.V1_1 : Id3v1_Version.V1_0
	}
	after.ape = formats.ape
	return
}

// The track number an ID3v1 tag of version holds: one up to 255, in ID3v1.1 only.
@(private)
id3v1_track :: proc(tags: ^Tags, version: Id3v1_Version) -> Maybe(int) {
	if version == .V1_0 do return nil
	track, ok := tags.track.?
	if !ok || track < 1 || track > 255 do return nil
	return track
}
