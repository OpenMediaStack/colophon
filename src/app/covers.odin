package main

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import "../engine"
import lib "../library"
import ui "../ui"

// Makes an image file the cover of the selected tracks: a JPEG or a PNG, told by its
// first bytes as 1.0.0 told them. Another file, or one that cannot be read, is told
// in a toast, shown from now (the frame's time).
take_image :: proc(app: ^App, path: string, now: f64) {
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	mime, is_image := "", false
	if read_err == nil do mime, is_image = image_mime(data)
	if !is_image {
		message := ui.fill(ui.tr("“{}” is not a JPEG or PNG image"), filepath.base(path))
		notify(app, .Error, message, nil, now)
		return
	}
	execute(app, engine.Apply_Edit{{.Cover, lib.Cover{mime, data}}})
}

// Writes the cover the selected tracks share to path, for the user to keep; a file
// that cannot be written is told in a toast, shown from now.
extract_cover :: proc(app: ^App, path: string, now: f64) {
	bytes, found := shared_cover(app, context.temp_allocator)
	if !found do return
	if os.write_entire_file(path, bytes) != nil {
		message := ui.fill(ui.tr("Could not write the cover to “{}”"), filepath.base(path))
		notify(app, .Error, message, nil, now)
	}
}

// Asks where to write the cover the selected tracks share, named by its format.
extract_cover_to :: proc(app: ^App) {
	bytes, found := shared_cover(app, context.temp_allocator)
	if !found do return
	mime, _ := image_mime(bytes)
	pick_save(app, mime == "image/png" ? "cover.png" : "cover.jpg")
}

// The bytes of the cover the selected tracks share: those held for a cover waiting to
// be saved, else read from the first selected track's file. Allocated with allocator.
@(private = "file")
shared_cover :: proc(app: ^App, allocator := context.allocator) -> (bytes: []u8, found: bool) {
	e := &app.engine
	s, tracks := engine.inspect(e).(engine.Summary)
	if !tracks do return
	if _, shared := s.cover.(lib.Cover_Key); !shared do return
	track := s.cover_track.? or_return
	tags := engine.shown_tags(e, track) or_return
	switch cover in tags.cover {
	case lib.Cover:
		return slice.clone(cover.data, allocator), true
	case lib.Own_Cover:
		read := lib.read_cover(e.library.tracks[track].path, allocator) or_return
		return read.data, true
	case nil:
	}
	return
}

// Whether a path names an image Colophon takes as a cover, by its extension.
is_image_file :: proc(path: string) -> bool {
	extension := strings.to_lower(filepath.ext(path), context.temp_allocator)
	return extension == ".jpg" || extension == ".jpeg" || extension == ".png"
}

// The MIME type of an image by its first bytes, for the two formats covers are written
// in.
@(private = "file")
image_mime :: proc(data: []u8) -> (mime: string, ok: bool) {
	switch {
	case len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF:
		return "image/jpeg", true
	case len(data) >= 8 && string(data[:8]) == "\x89PNG\r\n\x1a\n":
		return "image/png", true
	}
	return "", false
}
