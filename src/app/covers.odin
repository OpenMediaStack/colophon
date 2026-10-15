package main

import "core:os"
import "core:path/filepath"
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

// Asks where to write the cover the selected tracks share, read once and kept until
// the dialog answers, so that what the engine does meanwhile changes nothing of what
// is written. The dialog suggests cover.png or cover.jpg by the cover's format, beside
// the track's file: SDL's save dialog takes a path, not a name alone.
extract_cover :: proc(app: ^App) {
	cover, track, found := shared_cover(app, app.engine.allocator)
	if !found do return
	forget_cover_to_write(app)
	app.cover_to_write = cover
	mime, _ := image_mime(cover.data)
	folder := filepath.dir(app.engine.library.tracks[track].path)
	suggested, _ := filepath.join(
		{folder, mime == "image/png" ? "cover.png" : "cover.jpg"},
		context.temp_allocator,
	)
	pick_save(app, suggested)
}

// Writes the cover kept by extract_cover to path, for the user to keep; a file that
// cannot be written is told in a toast, shown from now.
extract_cover_to :: proc(app: ^App, path: string, now: f64) {
	cover, kept := app.cover_to_write.?
	if !kept do return
	defer forget_cover_to_write(app)
	if os.write_entire_file(path, cover.data) != nil {
		message := ui.fill(ui.tr("Could not write the cover to “{}”"), filepath.base(path))
		notify(app, .Error, message, nil, now)
	}
}

// Frees the cover kept for the save dialog, if one is; app_destroy calls it too.
forget_cover_to_write :: proc(app: ^App) {
	if cover, kept := &app.cover_to_write.?; kept do lib.destroy_cover(cover, app.engine.allocator)
	app.cover_to_write = nil
}

// The cover the selected tracks share, and the first track with it: the bytes held
// for a cover waiting to be saved, else read from the track's file. Allocated with
// allocator; free it with lib.destroy_cover.
@(private = "file")
shared_cover :: proc(
	app: ^App,
	allocator := context.allocator,
) -> (
	cover: lib.Cover,
	track: engine.Track_Id,
	found: bool,
) {
	e := &app.engine
	s, tracks := engine.inspect(e).(engine.Summary)
	if !tracks do return
	if _, shared := s.cover.(lib.Cover_Key); !shared do return
	track = s.cover_track.? or_return
	tags := engine.shown_tags(e, track) or_return
	switch held in tags.cover {
	case lib.Cover:
		return lib.clone_cover(held, allocator), track, true
	case lib.Own_Cover:
		cover = lib.read_cover(e.library.tracks[track].path, allocator) or_return
		return cover, track, true
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
