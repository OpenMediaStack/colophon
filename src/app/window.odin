package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

import "../engine"
import lib "../library"
import ui "../ui"

APP_NAME :: "Colophon"
// The identifier of Colophon 1.0.0, which SDL hands to the system (the Wayland app id).
APP_ID :: "io.github.openmediastack.colophon"
VERSION :: "1.0.0"

// How many frames follow one another at once while the hover or the focus settle,
// before the loop waits for input again.
@(private = "file")
SETTLING_FRAMES :: 3

// The window, what draws into it, and the Ui the screens draw with.
Window :: struct {
	window:      ^sdl.Window,
	renderer:    ^sdl.Renderer,
	backend:     ui.Sdl_Backend,
	lists:       ui.Renderer,
	ctx:         ui.Ui,
	cursors:     [ui.Cursor]^sdl.Cursor,
	cursor:      ui.Cursor,
	text_input:  bool,
	// The window's title, as last set.
	title:       string,
	// The event the engine's threads push to wake the loop, and the one a dialog
	// pushes with what the user chose.
	wake_type:   u32,
	chosen_type: u32,
	// The files dialog's filter, which must last until the dialog answers.
	filters:     [1]sdl.DialogFileFilter,
	// An event kept for the next frame, so that each frame sees one change of a
	// button, and the hover has settled where a click is.
	pending:     Maybe(sdl.Event),
}

// Opens the window and runs until it closes, or renders one frame for --screenshot.
run :: proc(options: Options) -> bool {
	headless := len(options.screenshot) > 0
	if headless {
		// The dummy video driver with the software renderer: no window shows, and the
		// pixels do not depend on the GPU, so screenshots can be compared across
		// machines. Overriding, so the SDL_VIDEO_DRIVER and SDL_RENDER_DRIVER variables
		// cannot change it.
		if !sdl.SetHintWithPriority(sdl.HINT_VIDEO_DRIVER, "dummy", .OVERRIDE) do return sdl_failed("SDL_SetHintWithPriority")
		if !sdl.SetHintWithPriority(sdl.HINT_RENDER_DRIVER, "software", .OVERRIDE) do return sdl_failed("SDL_SetHintWithPriority")
	}
	if !sdl.SetAppMetadata(APP_NAME, VERSION, APP_ID) do sdl_failed("SDL_SetAppMetadata")
	if !sdl.Init({.VIDEO, .EVENTS}) do return sdl_failed("SDL_Init")
	defer sdl.Quit()
	// Destroying a catalogue that holds no translation is harmless.
	catalog: ui.Catalog
	init_translations(&catalog)
	defer ui.catalog_destroy(&catalog)

	w: Window
	w.wake_type = sdl.RegisterEvents(2)
	w.chosen_type = w.wake_type + 1
	w.filters = {{"MP3 files", "mp3"}}
	app: App
	app_init(&app, lib.Wake{wake_loop, &w.wake_type})
	defer app_destroy(&app)
	app.dialogs = {
		data        = &w,
		open_folder = show_folder_dialog,
		open_files  = show_files_dialog,
		reveal      = reveal_in_file_manager,
	}
	open_window(&w, options) or_return
	defer close_window(&w)

	if headless {
		update(&w, &app)
		draw(&w) or_return
		return save_screenshot(w.renderer, options.screenshot)
	}
	return event_loop(&w, &app)
}

// Opens the window at the size asked, with its renderer, the draw lists and the Ui.
@(private = "file")
open_window :: proc(w: ^Window, options: Options) -> bool {
	size := options.window_size
	w.window = sdl.CreateWindow(APP_NAME, size.x, size.y, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if w.window == nil do return sdl_failed("SDL_CreateWindow")
	// SDL sizes windows in points on macOS and Wayland but in pixels on Windows and
	// X11: the sizes asked are in points, so they grow by the display's scale there.
	density := sdl.GetWindowPixelDensity(w.window)
	scale := sdl.GetWindowDisplayScale(w.window)
	units: f32 = density > 0 && scale > 0 ? scale / density : 1
	if units != 1 {
		if !sdl.SetWindowSize(w.window, c.int(f32(size.x) * units), c.int(f32(size.y) * units)) {
			sdl_failed("SDL_SetWindowSize")
		}
	}
	least := [2]c.int {
		c.int(f32(MINIMUM_WINDOW_SIZE.x) * units),
		c.int(f32(MINIMUM_WINDOW_SIZE.y) * units),
	}
	if !sdl.SetWindowMinimumSize(w.window, least.x, least.y) do sdl_failed("SDL_SetWindowMinimumSize")
	w.renderer = sdl.CreateRenderer(w.window, nil)
	if w.renderer == nil do return sdl_failed("SDL_CreateRenderer")
	if !sdl.SetRenderVSync(w.renderer, 1) do sdl_failed("SDL_SetRenderVSync")
	ui.renderer_init(&w.lists)
	ui.ui_init(&w.ctx, &w.lists, ui.theme(system_theme()))
	w.ctx.clipboard = {
		get = proc(data: rawptr, allocator: runtime.Allocator) -> string {
			text := sdl.GetClipboardText()
			defer sdl.free(text)
			return strings.clone(string(cstring(text)), allocator)
		},
		set = proc(data: rawptr, text: string) {
			if !sdl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator)) {
				sdl_failed("SDL_SetClipboardText")
			}
		},
	}
	ui.sdl_backend_init(&w.backend, w.renderer)
	return true
}

@(private = "file")
close_window :: proc(w: ^Window) {
	ui.sdl_backend_destroy(&w.backend)
	ui.ui_destroy(&w.ctx)
	ui.renderer_destroy(&w.lists)
	for cursor in w.cursors do if cursor != nil do sdl.DestroyCursor(cursor)
	delete(w.title)
	if w.renderer != nil do sdl.DestroyRenderer(w.renderer)
	if w.window != nil do sdl.DestroyWindow(w.window)
}

// Draws a frame after each batch of events, until the window closes (true) or
// drawing fails (false). The loop waits for events, or until the Ui asked for a frame.
// SDL's loop stops while the window is resized on macOS and Windows: an event watch
// draws the window at its new size from inside the resize.
@(private = "file")
event_loop :: proc(w: ^Window, app: ^App) -> bool {
	live := Live{w, app}
	if !sdl.AddEventWatch(live_resize, &live) do sdl_failed("SDL_AddEventWatch")
	defer sdl.RemoveEventWatch(live_resize, &live)
	for {
		update(w, app)
		draw(w) or_return
		if !sdl.RenderPresent(w.renderer) do return sdl_failed("SDL_RenderPresent")
		if !wait_for_events(w, app) do return true
	}
}

// What the event watch draws with.
@(private = "file")
Live :: struct {
	w:   ^Window,
	app: ^App,
}

// Called by SDL for every event as it is pushed, on the thread that pushes it: a
// resize or an exposure of the window, which come on the main thread while SDL's
// loop stops, draws a frame at once.
@(private = "file")
live_resize :: proc "c" (userdata: rawptr, event: ^sdl.Event) -> bool {
	#partial switch event.type {
	case .WINDOW_RESIZED, .WINDOW_EXPOSED:
	case:
		return true
	}
	context = runtime.default_context()
	live := (^Live)(userdata)
	update(live.w, live.app)
	if draw(live.w) do sdl.RenderPresent(live.w.renderer)
	return true
}

// Runs the frames of the screen with the input gathered: one, and a few more at once
// while the hover or the focus settle, or while a command ran, so that what it changed
// shows. Then the window follows the Ui: the text input for the focused field, the
// cursor.
@(private = "file")
update :: proc(w: ^Window, app: ^App) {
	free_all(context.temp_allocator)
	engine.poll(&app.engine)
	scale := sdl.GetWindowDisplayScale(w.window)
	if scale <= 0 do scale = 1
	width, height: c.int
	sdl.GetWindowSizeInPixels(w.window, &width, &height)
	w.ctx.viewport = {0, 0, f32(width) / scale, f32(height) / scale}
	w.ctx.input.time = f64(sdl.GetTicksNS()) / 1e9
	for _ in 0 ..< SETTLING_FRAMES {
		commands := app.commands
		ui.ui_begin_frame(&w.ctx, scale)
		main_screen(&w.ctx, app, w.ctx.viewport)
		redraw := ui.ui_end_frame(&w.ctx)
		if !redraw && app.commands == commands do break
	}
	follow_focus(w)
	follow_cursor(w)
	follow_title(w, app)
}

// The window's title says what the table lists.
@(private = "file")
follow_title :: proc(w: ^Window, app: ^App) {
	title := window_title(app)
	if title == w.title do return
	delete(w.title)
	w.title = strings.clone(title)
	if !sdl.SetWindowTitle(w.window, strings.clone_to_cstring(title, context.temp_allocator)) {
		sdl_failed("SDL_SetWindowTitle")
	}
}

// Draws the frame's lists over the window's surface.
@(private = "file")
draw :: proc(w: ^Window) -> bool {
	bg := w.ctx.theme.surface_0
	if !sdl.SetRenderDrawColorFloat(w.renderer, bg.r, bg.g, bg.b, bg.a) do return sdl_failed("SDL_SetRenderDrawColorFloat")
	if !sdl.RenderClear(w.renderer) do return sdl_failed("SDL_RenderClear")
	if !ui.sdl_backend_draw(&w.backend, &w.lists) do return sdl_failed("drawing")
	return true
}

// Waits for the next events and adds them to the Ui's input, until a frame is due:
// the queue is empty, a button changed twice, or the time the Ui asked a frame for
// came. False when the window closes.
@(private = "file")
wait_for_events :: proc(w: ^Window, app: ^App) -> bool {
	event: sdl.Event
	got: bool
	if kept, has := w.pending.?; has {
		event = kept
		w.pending = nil
		got = true
	} else {
		got = sdl.WaitEventTimeout(&event, wake_timeout(w))
	}
	for got {
		switch handle_event(w, app, &event) {
		case .Quit:
			return false
		case .Wait:
			w.pending = event
			return true
		case .Taken, .Other:
		}
		got = sdl.PollEvent(&event)
	}
	return true
}

@(private = "file")
Event_Outcome :: enum u8 {
	Taken,
	Other,
	Wait,
	Quit,
}

@(private = "file")
handle_event :: proc(w: ^Window, app: ^App, event: ^sdl.Event) -> Event_Outcome {
	#partial switch event.type {
	case .QUIT:
		return .Quit
	case .SYSTEM_THEME_CHANGED:
		w.ctx.theme = ui.theme(system_theme())
		return .Other
	case .DROP_BEGIN:
		drop_begin(app)
		return .Other
	case .DROP_FILE:
		if event.drop.data != nil do drop_file(app, string(event.drop.data))
		return .Other
	case .DROP_COMPLETE:
		drop_end(app)
		return .Other
	case .DROP_POSITION, .DROP_TEXT:
		return .Other
	}
	if u32(event.type) == w.wake_type do return .Other
	// A drag that SDL loses on macOS, of what is neither a file nor text, ends without
	// a word: the mouse moving again means the drag is over.
	if app.drop.hovering && (event.type == .MOUSE_MOTION || event.type == .MOUSE_BUTTON_DOWN) {
		drop_end(app)
	}
	if u32(event.type) == w.chosen_type {
		take_chosen(app, (^Chosen)(event.user.data1))
		return .Other
	}
	// SDL gives mouse positions in points on macOS and Wayland but in pixels on Windows
	// and X11: the pixel density over the display scale turns them into points.
	density := sdl.GetWindowPixelDensity(w.window)
	scale := sdl.GetWindowDisplayScale(w.window)
	points_per_unit: f32 = scale > 0 && density > 0 ? density / scale : 1
	switch ui.input_from_sdl(&w.ctx.input, event, points_per_unit) {
	case .Wait:
		return .Wait
	case .Taken:
		return .Taken
	case .Other:
	}
	return .Other
}

// How long the loop may wait for events: until the Ui asked for a frame, or forever.
@(private = "file")
wake_timeout :: proc(w: ^Window) -> i32 {
	at := w.ctx.wake_at
	if at == max(f64) do return -1
	now := f64(sdl.GetTicksNS()) / 1e9
	return i32(clamp((at - now) * 1000, 0, f64(max(i32))))
}

// The system takes the keyboard's text for the focused field, and composes it for the
// languages that need it, only while a field has the focus.
@(private = "file")
follow_focus :: proc(w: ^Window) {
	wants_text := false
	for widget in w.ctx.widgets {
		if widget.id != w.ctx.focus do continue
		wants_text = widget.role == .Text_Field || widget.role == .Combo_Box
		break
	}
	if wants_text == w.text_input do return
	w.text_input = wants_text
	if wants_text {
		if !sdl.StartTextInput(w.window) do sdl_failed("SDL_StartTextInput")
	} else {
		if !sdl.StopTextInput(w.window) do sdl_failed("SDL_StopTextInput")
	}
}

@(private = "file")
follow_cursor :: proc(w: ^Window) {
	wanted := w.ctx.cursor
	if wanted == w.cursor && w.cursors[wanted] != nil do return
	w.cursor = wanted
	if w.cursors[wanted] == nil {
		w.cursors[wanted] = sdl.CreateSystemCursor(system_cursor(wanted))
		if w.cursors[wanted] == nil do return
	}
	if !sdl.SetCursor(w.cursors[wanted]) do sdl_failed("SDL_SetCursor")
}

@(private = "file")
system_cursor :: proc(cursor: ui.Cursor) -> sdl.SystemCursor {
	switch cursor {
	case .Default:
		return .DEFAULT
	case .Pointer:
		return .POINTER
	case .Text:
		return .TEXT
	case .Resize_Horizontal:
		return .EW_RESIZE
	case .Resize_Vertical:
		return .NS_RESIZE
	case .Grab:
		return .POINTER
	case .Grabbing:
		return .MOVE
	}
	return .DEFAULT
}

// The theme the system is in; dark when it does not say.
@(private = "file")
system_theme :: proc() -> ui.Theme_Kind {
	return sdl.GetSystemTheme() == .LIGHT ? .Light : .Dark
}

// Opens the folder holding a file in the system's file manager. Picking the file out
// among the others needs each system's own call, which comes with the platform slices.
@(private = "file")
reveal_in_file_manager :: proc(app: ^App, data: rawptr, path: string) {
	_ = app
	_ = data
	folder := filepath.dir(path)
	url := strings.concatenate({"file://", folder}, context.temp_allocator)
	if !sdl.OpenURL(strings.clone_to_cstring(url, context.temp_allocator)) do sdl_failed("SDL_OpenURL")
}

// What a dialog's user chose, on its way to the loop through an event. Made on the
// dialog's thread with the default allocator, freed on the UI thread with the same.
@(private = "file")
Chosen :: struct {
	paths: [dynamic]string,
	kind:  Dialog_Kind,
}

@(private = "file")
Dialog_Kind :: enum u8 {
	Folder,
	Files,
}

@(private = "file")
show_folder_dialog :: proc(app: ^App, data: rawptr) {
	_ = app
	w := (^Window)(data)
	sdl.ShowOpenFolderDialog(folder_chosen, data, w.window, nil, false)
}

@(private = "file")
show_files_dialog :: proc(app: ^App, data: rawptr) {
	_ = app
	w := (^Window)(data)
	sdl.ShowOpenFileDialog(files_chosen, data, w.window, &w.filters[0], len(w.filters), nil, true)
}

@(private = "file")
folder_chosen :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {
	dialog_answered(userdata, filelist, .Folder)
}

@(private = "file")
files_chosen :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {
	dialog_answered(userdata, filelist, .Files)
}

// A dialog answered, on whatever thread SDL calls from: what was chosen goes to the
// loop through an event, copied, since the list is SDL's only for the call. A nil list
// is an error, an empty one a dialog cancelled: nothing to open either way.
@(private = "file")
dialog_answered :: proc "c" (userdata: rawptr, filelist: [^]cstring, kind: Dialog_Kind) {
	context = runtime.default_context()
	if filelist == nil {
		sdl_failed("the dialog")
		return
	}
	if filelist[0] == nil do return
	w := (^Window)(userdata)
	chosen := new(Chosen)
	chosen.kind = kind
	for i := 0; filelist[i] != nil; i += 1 {
		append(&chosen.paths, strings.clone(string(filelist[i])))
	}
	event: sdl.Event
	event.type = sdl.EventType(w.chosen_type)
	event.user.data1 = chosen
	if !sdl.PushEvent(&event) do free_chosen(chosen)
}

// Opens what a dialog's user chose, on the UI thread.
@(private = "file")
take_chosen :: proc(app: ^App, chosen: ^Chosen) {
	if chosen == nil do return
	defer free_chosen(chosen)
	switch chosen.kind {
	case .Folder:
		for path in chosen.paths do execute(app, engine.Open_Folder{path})
	case .Files:
		execute(app, engine.Open_Files{chosen.paths[:]})
	}
}

@(private = "file")
free_chosen :: proc(chosen: ^Chosen) {
	allocator := runtime.default_allocator()
	for path in chosen.paths do delete(path, allocator)
	delete(chosen.paths)
	free(chosen, allocator)
}

// Called from the engine's threads: an event wakes the loop, which polls the engine.
@(private = "file")
wake_loop :: proc "contextless" (data: rawptr) {
	event: sdl.Event
	event.type = sdl.EventType((^u32)(data)^)
	_ = sdl.PushEvent(&event)
}

@(private = "file")
save_screenshot :: proc(renderer: ^sdl.Renderer, path: string) -> bool {
	surface := sdl.RenderReadPixels(renderer, nil)
	if surface == nil do return sdl_failed("SDL_RenderReadPixels")
	defer sdl.DestroySurface(surface)
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	if !sdl.SavePNG(surface, cpath) do return sdl_failed("SDL_SavePNG")
	return true
}

// Reports the last SDL error; returns false so callers can return it.
@(private = "file")
sdl_failed :: proc(what: string) -> bool {
	fmt.eprintfln("colophon: %s failed: %s", what, sdl.GetError())
	return false
}
