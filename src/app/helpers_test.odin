package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"
import sdl "vendor:sdl3"

import "../engine"
import ui "../ui"

// How long a test waits for a thread, in real time: long enough for a busy machine.
@(private = "file")
PATIENCE :: 20 * time.Second

@(private = "file")
TESTDATA :: #directory + "/../../testdata"

// The main screen in a harness: its frames run without a window, over an app of its
// own, whose dialogs answer what the test gives them. Make it with screen_init, free
// it with screen_destroy.
Screen :: struct {
	h:       ui.Harness,
	app:     App,
	answers: Answers,
}

// What the dialogs answer: each folder in turn, then nothing; the files every time.
Answers :: struct {
	folders: [dynamic]string,
	files:   []string,
}

// A screen of size points, in the theme of kind, drawn twice so that the hover and the
// focus have settled.
screen_init :: proc(s: ^Screen, size: [2]f32, kind := ui.Theme_Kind.Dark) {
	app_init(&s.app)
	// The same captures on every system.
	s.app.platform = .Mac
	s.answers.folders = make([dynamic]string)
	s.app.dialogs = {
		data = &s.answers,
		open_folder = proc(app: ^App, data: rawptr) {
			a := (^Answers)(data)
			if len(a.folders) == 0 do return
			engine.execute(&app.engine, engine.Open_Folder{pop_front(&a.folders)})
		},
		open_files = proc(app: ^App, data: rawptr) {
			a := (^Answers)(data)
			if len(a.files) > 0 do engine.execute(&app.engine, engine.Open_Files{a.files})
		},
	}
	ui.harness_init(&s.h, app_frame, &s.app, kind)
	s.h.scale = 1
	resize(s, size)
}

screen_destroy :: proc(s: ^Screen) {
	ui.harness_destroy(&s.h)
	app_destroy(&s.app)
	delete(s.answers.folders)
	free_all(context.temp_allocator)
}

// Polls the engine as the loop does, running frames, until a widget labelled label
// shows or PATIENCE passes.
wait_until_shown :: proc(t: ^testing.T, s: ^Screen, label: string) {
	start := time.tick_now()
	for !shows(s, label) {
		if time.tick_since(start) > PATIENCE do testing.fail_now(t, fmt.tprintf("%q did not show in time", label))
		engine.poll(&s.app.engine)
		ui.run_frame(&s.h)
		time.sleep(time.Millisecond)
	}
}

// A new temporary folder holding files of a few bytes each, which only start like an
// MP3. Remove it with remove_folder.
folder_with :: proc(t: ^testing.T, files: []string) -> string {
	folder, err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, err == nil)
	for file in files {
		path := fmt.tprintf("%s/%s", folder, file)
		made := os.make_directory_all(filepath.dir(path))
		testing.expect(t, made == nil || made == .Exist)
		testing.expect(t, os.write_entire_file(path, transmute([]u8)string("ID3")) == nil)
	}
	return folder
}

// The window takes another size: the next frames lay the screen out again.
resize :: proc(s: ^Screen, size: [2]f32) {
	s.h.ui.viewport = {0, 0, size.x, size.y}
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
}

// Whether a widget labelled label was drawn in the last frame.
shows :: proc(s: ^Screen, label: string) -> bool {
	_, found := ui.find_widget(&s.h.ui, label)
	return found
}

// A new temporary folder holding copies of fixtures of testdata/, each under its new
// name. Remove it with remove_folder.
folder_with_fixtures :: proc(t: ^testing.T, copies: [][2]string) -> string {
	folder, err := os.make_directory_temp("", "colophon-*", context.allocator)
	testing.expect(t, err == nil)
	for c in copies {
		path := fmt.tprintf("%s/%s", folder, c[1])
		made := os.make_directory_all(filepath.dir(path))
		testing.expect(t, made == nil || made == .Exist)
		testing.expect(t, os.copy_file(path, fmt.tprintf("%s/%s", TESTDATA, c[0])) == nil)
	}
	return folder
}

remove_folder :: proc(folder: string) {
	_ = os.remove_all(folder)
	delete(folder)
}

// Opens a folder as the app does, and waits for the whole of it to be read.
open_folder_of :: proc(t: ^testing.T, s: ^Screen, folder: string) {
	e := &s.app.engine
	engine.execute(e, engine.Open_Folder{folder})
	start := time.tick_now()
	for e.library.status == .Scanning {
		if time.tick_since(start) > PATIENCE do testing.fail_now(t, "the scan did not finish in time")
		engine.poll(e)
		time.sleep(time.Millisecond)
	}
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
}

// Polls the engine as the loop does, until the running save ends.
wait_for_save :: proc(t: ^testing.T, s: ^Screen) {
	e := &s.app.engine
	start := time.tick_now()
	for engine.saving(e) != nil {
		if time.tick_since(start) > PATIENCE do testing.fail_now(t, "the save did not finish in time")
		engine.poll(e)
		time.sleep(time.Millisecond)
	}
	ui.run_frame(&s.h)
}

// Draws the screen's last frame and compares it with the reference name, or writes the
// reference when UPDATE_REFERENCES is set or when it does not exist yet (and fails, to
// be looked at). A capture that differs is written to build/captures.
expect_screen :: proc(t: ^testing.T, s: ^Screen, name: string) {
	cap: ui.Capture
	size := [2]f32{s.h.ui.viewport.w, s.h.ui.viewport.h}
	if !testing.expectf(t, ui.capture_init(&cap, size, s.h.scale), "capture: %s", sdl.GetError()) do return
	defer ui.capture_destroy(&cap)
	ui.run_frame(&s.h)
	if !testing.expectf(t, ui.capture_draw(&cap, &s.h.renderer), "drawing: %s", sdl.GetError()) do return
	update := ui.update_references_asked()
	result, message := ui.check_reference(cap.surface, name, update)
	testing.expectf(t, result == .Matches || (update && result == .Written), "%s", message)
}
