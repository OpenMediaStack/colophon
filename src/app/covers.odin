package main

import "core:os"
import "core:path/filepath"

import "../engine"
import lib "../library"
import ui "../ui"

// Makes an image file the cover of the selected tracks: a JPEG or a PNG, told by its
// first bytes as 1.0.0 told them. Another file, or one that cannot be read, is told
// in a toast, shown from now (the frame's time).
take_image :: proc(app: ^App, path: string, now: f64) {
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	mime, is_image := image_mime(data)
	if read_err != nil || !is_image {
		message := ui.fill(ui.tr("“{}” is not a JPEG or PNG image"), filepath.base(path))
		notify(app, .Error, message, nil, now)
		return
	}
	execute(app, engine.Apply_Edit{{.Cover, lib.Cover{mime, data}}})
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
