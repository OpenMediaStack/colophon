package library

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

import id3 "../../libs/odid3"

// How a file's tags are laid out, byte by byte, for people who write ID3 readers and
// writers: what developer mode shows. Free it with destroy_layout.
Tag_Layout :: struct {
	has_id3v2:         bool,
	version:           Id3v2_Version,
	revision:          u8,
	// The whole tag is unsynchronised. The offsets of its frames are those of the file;
	// before ID3v2.4 odid3 does not say which frames were unsynchronised, as 1.0.0 did
	// for each frame of such a tag: callers show the tag's flag for them.
	unsynchronisation: bool,
	extended_header:   bool,
	experimental:      bool,
	footer:            bool,
	// Its size, header and footer included, and the zeros after its last frame.
	size:              i64,
	padding:           int,
	frames:            []Frame_Layout,
	// Where the ID3v1 tag starts, 128 bytes before the end of the file, if there is one.
	id3v1_offset:      Maybe(i64),
}

// A frame of an ID3v2 tag.
Frame_Layout :: struct {
	id:             string,
	// Where its header starts, from the start of the file, and the size of its content,
	// its header left out.
	offset:         i64,
	size:           int,
	read_only:      bool,
	grouping:       bool,
	compression:    bool,
	encryption:     bool,
	unsynchronised: bool,
	data_length:    bool,
	// The encoding of its text, for the frames that hold some.
	encoding:       Maybe(Text_Encoding),
	kind:           Frame_Kind,
	// What it holds as text: its text, or for a picture its MIME type.
	value:          string,
	// A picture's size in bytes.
	picture_size:   int,
}

// The encoding of the text of a frame.
Text_Encoding :: enum u8 {
	Latin1,
	UTF16,
	// ID3v2.4 only.
	UTF16BE,
	// ID3v2.4 only.
	UTF8,
}

@(private = "file", rodata)
ENCODING_NAMES := [Text_Encoding]string {
	.Latin1  = "ISO-8859-1",
	.UTF16   = "UTF-16",
	.UTF16BE = "UTF-16BE",
	.UTF8    = "UTF-8",
}

// The name of a text encoding as developer mode shows it.
encoding_name :: proc(encoding: Text_Encoding) -> string {
	return ENCODING_NAMES[encoding]
}

// What a frame holds.
Frame_Kind :: enum u8 {
	Text,
	Picture,
	// Compressed or encrypted content, or damaged, which is not opened.
	Sealed,
	// Bytes Colophon does not decode.
	Binary,
}

// Frames of text or data over this size are not opened: a hostile file would make
// odid3 spread them into a value per byte. They show as bytes of data. Pictures are
// opened whatever their size, for their type and size.
@(private = "file")
MAX_OPENED :: 64 * 1024
// The longest value kept, in bytes: the interface cuts it to its width anyway.
@(private = "file")
MAX_VALUE :: 1024

// How the tags of the file at path are laid out. found is false when the file cannot
// be read. A tag odid3 cannot read is reported as far as it goes. It reads the file,
// so it blocks: call it off the UI thread when the disk may be slow; it may be called
// from any thread. The strings are allocated with allocator, and the layout is freed
// with destroy_layout and the same allocator. Nothing is kept in the temporary
// allocator.
read_layout :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	layout: Tag_Layout,
	found: bool,
) {
	tags, err := id3.read_file(path, {}, allocator)
	if err != nil do return
	defer id3.destroy(&tags)
	found = true
	if tags.layout.v1.size > 0 do layout.id3v1_offset = tags.layout.v1.offset
	version, has_version := version_of(tags.v2.version).?
	if !has_version do return
	v2 := &tags.v2
	layout.has_id3v2 = true
	layout.version = version
	layout.revision = v2.revision
	layout.unsynchronisation = .Unsynchronisation in v2.flags
	layout.extended_header = .Extended_Header in v2.flags
	layout.experimental = .Experimental in v2.flags
	layout.footer = .Footer in v2.flags
	// A tag found at the end of the file, through its footer, has its own range.
	layout.size = tags.layout.v2.size
	if layout.size == 0 do layout.size = tags.layout.v2_appended.size
	layout.padding = v2.padding
	layout.frames = make([]Frame_Layout, len(v2.frames), allocator)
	for &frame, i in v2.frames {
		layout.frames[i] = frame_layout(&frame, v2.version, allocator)
	}
	return
}

@(private = "file")
version_of :: proc(version: id3.V2_Version) -> Maybe(Id3v2_Version) {
	#partial switch version {
	case .V2_2:
		return .V2_2
	case .V2_3:
		return .V2_3
	case .V2_4:
		return .V2_4
	}
	return nil
}

@(private = "file")
text_encoding_of :: proc(encoding: id3.Encoding) -> Text_Encoding {
	switch encoding {
	case .Latin1:
		return .Latin1
	case .UTF16:
		return .UTF16
	case .UTF16BE:
		return .UTF16BE
	case .UTF8:
		return .UTF8
	}
	return .Latin1
}

@(private = "file")
frame_layout :: proc(
	frame: ^id3.Frame,
	version: id3.V2_Version,
	allocator: runtime.Allocator,
) -> (
	f: Frame_Layout,
) {
	f.id = strings.clone(frame.id, allocator)
	f.offset = frame.offset
	f.size = frame.size
	f.read_only = .Read_Only in frame.status
	f.grouping = .Grouping in frame.format
	f.compression = .Compression in frame.format
	f.encryption = .Encryption in frame.format
	f.unsynchronised = .Unsynchronisation in frame.format
	f.data_length = .Data_Length_Indicator in frame.format
	f.kind = .Binary
	if f.compression || f.encryption {
		f.kind = .Sealed
		return
	}
	picture := frame.id == "APIC" || frame.id == "PIC"
	if frame.size > MAX_OPENED && !picture do return
	content, decode_err := id3.decode_frame(frame, version, allocator)
	if decode_err != nil do return
	defer id3.destroy(&content, allocator)
	switch c in content {
	case id3.Text:
		f.kind, f.encoding = .Text, text_encoding_of(c.encoding)
		values := strings.join(c.values, " / ", allocator)
		defer delete(values, allocator)
		f.value = capped(values, allocator)
	case id3.User_Text:
		f.kind, f.encoding = .Text, text_encoding_of(c.encoding)
		values := strings.join(c.values, " / ", allocator)
		defer delete(values, allocator)
		f.value = joined(c.description, values, allocator)
	case id3.Url:
		f.kind = .Text
		f.value = capped(c.url, allocator)
	case id3.User_Url:
		f.kind, f.encoding = .Text, text_encoding_of(c.encoding)
		f.value = joined(c.description, c.url, allocator)
	case id3.Comment:
		f.kind, f.encoding = .Text, text_encoding_of(c.encoding)
		f.value = joined(c.description, c.text, allocator)
	case id3.Picture:
		f.kind, f.encoding = .Picture, text_encoding_of(c.encoding)
		f.value = capped(c.mime, allocator)
		f.picture_size = len(c.data)
	case id3.Unique_File_Id,
	     id3.Popularimeter,
	     id3.Play_Counter,
	     id3.Private,
	     id3.Chapter,
	     id3.Table_Of_Contents,
	     id3.Binary:
	}
	return
}

// text, cut to MAX_VALUE bytes at a character, when it is longer. Allocated with
// allocator.
@(private = "file")
capped :: proc(text: string, allocator: runtime.Allocator) -> string {
	if len(text) <= MAX_VALUE do return strings.clone(text, allocator)
	end := MAX_VALUE
	for end > 0 && !utf8.rune_start(text[end]) do end -= 1
	return strings.concatenate({text[:end], "…"}, allocator)
}

// A description and a value joined by a colon, or the value alone without a description.
@(private = "file")
joined :: proc(description, value: string, allocator: runtime.Allocator) -> string {
	if len(description) == 0 do return capped(value, allocator)
	whole := strings.concatenate({description, ": ", value}, allocator)
	defer delete(whole, allocator)
	return capped(whole, allocator)
}

// Frees a layout read with allocator.
destroy_layout :: proc(layout: ^Tag_Layout, allocator := context.allocator) {
	for &frame in layout.frames {
		delete(frame.id, allocator)
		delete(frame.value, allocator)
	}
	delete(layout.frames, allocator)
	layout^ = {}
}
