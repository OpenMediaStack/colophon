package main

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:thread"

import "../engine"
import lib "../library"
import ui "../ui"

// The side of a thumbnail, in pixels: the sidebar's swatch at twice the scale.
THUMBNAIL_PIXELS :: 36

// The album covers drawn small in the sidebar, made on a thread of their own: the UI
// thread asks for a track's cover, the thread reads the file, decodes the picture and
// shrinks it, then hands the pixels back through a mutex-guarded queue and wakes the
// loop, where the UI thread makes the texture. Make it with init_thumbnails, free it
// with destroy_thumbnails.
Thumbnails :: struct {
	allocator: runtime.Allocator,
	wake:      lib.Wake,
	mutex:     sync.Mutex,
	// Work for the thread, and what it made, waiting for the UI thread.
	asked:     [dynamic]Thumbnail_Request,
	made:      [dynamic]Thumbnail_Result,
	work:      sync.Sema,
	stop:      bool,
	thread:    ^thread.Thread,
	// What the UI thread holds, by track: the texture once made, or that it is asked
	// for or missing, with the key of the cover it is of.
	by_track:  map[engine.Track_Id]Thumbnail,
}

Thumbnail :: struct {
	state:   Thumbnail_State,
	texture: ui.Texture_Id,
	// The cover it is of: a track whose cover changed, a save having written another,
	// is asked for again.
	key:     Maybe(lib.Cover_Key),
}

Thumbnail_State :: enum u8 {
	Asked,
	Made,
	// The file has no cover that can be read and decoded.
	Missing,
}

@(private = "file")
Thumbnail_Request :: struct {
	track: engine.Track_Id,
	path:  string,
	key:   Maybe(lib.Cover_Key),
}

@(private = "file")
Thumbnail_Result :: struct {
	track: engine.Track_Id,
	key:   Maybe(lib.Cover_Key),
	// Empty when the cover could not be read or decoded.
	rgba:  []u8,
	w, h:  int,
}

// Makes the thumbnails ready; the thread starts with the first request. The allocator
// is used by that thread too, so it must be thread safe.
init_thumbnails :: proc(t: ^Thumbnails, wake: lib.Wake, allocator := context.allocator) {
	t.allocator = allocator
	t.wake = wake
	t.asked = make([dynamic]Thumbnail_Request, allocator)
	t.made = make([dynamic]Thumbnail_Result, allocator)
	t.by_track = make(map[engine.Track_Id]Thumbnail, allocator)
}

// Stops the thread, waits for it, and frees what it made that no one took. The
// textures belong to the Ui's images: the window's backend or the harness frees them.
destroy_thumbnails :: proc(t: ^Thumbnails) {
	if t.thread != nil {
		sync.atomic_store(&t.stop, true)
		sync.sema_post(&t.work)
		thread.join(t.thread)
		thread.destroy(t.thread)
	}
	for request in t.asked do delete(request.path, t.allocator)
	for result in t.made do delete(result.rgba, t.allocator)
	delete(t.asked)
	delete(t.made)
	delete(t.by_track)
	t^ = {}
}

// The thumbnail of a track's cover, once made; asks the thread for it the first time,
// and again when the track's cover is no longer the one it was made of. The UI thread
// only: the texture is valid until the cover changes.
thumbnail :: proc(ctx: ^ui.Ui, app: ^App, track: engine.Track_Id) -> Maybe(ui.Texture_Id) {
	t := &app.thumbnails
	key := lib.cover_key(app.engine.library.tracks[track].metadata.tags.cover)
	if known, has := t.by_track[track]; has {
		if known.key == key {
			if known.state == .Made do return known.texture
			return nil
		}
		if known.state == .Made do ui.destroy_image(ctx, known.texture)
	}
	t.by_track[track] = {
		state = .Asked,
		key   = key,
	}
	if t.thread == nil {
		t.thread = thread.create_and_start_with_data(t, run_thumbnails)
		if t.thread == nil {
			t.by_track[track] = {
				state = .Missing,
				key   = key,
			}
			return nil
		}
	}
	path := strings.clone(app.engine.library.tracks[track].path, t.allocator)
	sync.mutex_lock(&t.mutex)
	append(&t.asked, Thumbnail_Request{track, path, key})
	sync.mutex_unlock(&t.mutex)
	sync.sema_post(&t.work)
	return nil
}

// Takes in what the thread made, making the textures, for the covers still wanted.
poll_thumbnails :: proc(ctx: ^ui.Ui, app: ^App) {
	t := &app.thumbnails
	results := make([dynamic]Thumbnail_Result, context.temp_allocator)
	sync.mutex_lock(&t.mutex)
	append(&results, ..t.made[:])
	clear(&t.made)
	sync.mutex_unlock(&t.mutex)
	for result in results {
		defer delete(result.rgba, t.allocator)
		known, has := &t.by_track[result.track]
		if !has || known.state != .Asked || known.key != result.key do continue
		if result.w == 0 {
			known.state = .Missing
			continue
		}
		texture, made := ui.create_image(ctx, result.rgba, result.w, result.h)
		if !made {
			known.state = .Missing
			continue
		}
		known.state, known.texture = .Made, texture
	}
}

// The thread: reads each cover asked for, decodes it, shrinks it, and reports.
@(private = "file")
run_thumbnails :: proc(data: rawptr) {
	t := (^Thumbnails)(data)
	context.allocator = t.allocator
	for {
		sync.sema_wait(&t.work)
		if sync.atomic_load(&t.stop) do return
		sync.mutex_lock(&t.mutex)
		if len(t.asked) == 0 {
			sync.mutex_unlock(&t.mutex)
			continue
		}
		request := pop_front(&t.asked)
		sync.mutex_unlock(&t.mutex)
		result := Thumbnail_Result {
			track = request.track,
			key   = request.key,
		}
		if small, made := make_thumbnail(request.path, t.allocator); made {
			result.rgba, result.w, result.h = small, THUMBNAIL_PIXELS, THUMBNAIL_PIXELS
		}
		delete(request.path, t.allocator)
		sync.mutex_lock(&t.mutex)
		was_empty := len(t.made) == 0
		append(&t.made, result)
		sync.mutex_unlock(&t.mutex)
		if was_empty && t.wake.procedure != nil do t.wake.procedure(t.wake.data)
	}
}

// The cover of the file at path, read, decoded and shrunk to a thumbnail's pixels: what
// the thread does for each request, without the thread. Allocated with allocator.
// False for a file without a cover that can be read and decoded.
make_thumbnail :: proc(path: string, allocator: runtime.Allocator) -> (rgba: []u8, ok: bool) {
	cover, found := lib.read_cover(path, allocator)
	if !found do return
	defer lib.destroy_cover(&cover, allocator)
	pixels, w, h, decoded := ui.decode_image(cover.data, allocator)
	if !decoded do return
	defer delete(pixels, allocator)
	return ui.shrink_image(pixels, w, h, THUMBNAIL_PIXELS, allocator)
}
