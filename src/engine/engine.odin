// Colophon's application state and the commands that change it. No UI types: the UI
// reads the state and turns buttons, menu items and shortcuts into commands.
package engine

import "base:runtime"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import lib "../library"

// A track, by its place in the library's tracks.
Track_Id :: distinct int

Scan_Status :: enum u8 {
	// Nothing has been opened.
	Idle,
	Scanning,
	Completed,
	// The user stopped the scans; the tracks found until then stay.
	Stopped,
	// The last scan could not start: the system gave no thread for it.
	Failed,
}

// The opened folders and files, and what their scans found so far.
Library :: struct {
	// The folders opened, and those of the files opened alone, none inside another,
	// in order.
	roots:      [dynamic]string,
	tracks:     [dynamic]lib.Track,
	unreadable: [dynamic]lib.Scan_Error,
	status:     Scan_Status,
}

// Colophon's state. Make it with init, free it with destroy.
Engine :: struct {
	allocator: runtime.Allocator,
	library:   Library,
	// Called by the scans' threads when they have news, to wake the UI loop.
	wake:      lib.Wake,
	scans:     [dynamic]^lib.Scan,
	// Scans asked to stop, whose threads end after the entry they are reading: poll
	// frees them then, so that the UI thread never waits for a disk.
	stopping:  [dynamic]^lib.Scan,
	// The paths of the tracks found, so that opening a file twice lists it once. The
	// keys are the paths of library.tracks.
	found:     map[string]Track_Id,
	events:    [dynamic]lib.Scan_Event,
}

// Adds a folder's audio files to the library.
Open_Folder :: struct {
	path: string,
}

// Adds audio files to the library, their folders with them.
Open_Files :: struct {
	paths: []string,
}

Stop_Scan :: struct {}

// A user action. The engine copies what it keeps of a command's strings.
Command :: union {
	Open_Folder,
	Open_Files,
	Stop_Scan,
}

// A stable identifier for each kind of command, for the command palette and the
// shortcut table.
command_id :: proc(command: Command) -> string {
	switch _ in command {
	case Open_Folder:
		return "library.open_folder"
	case Open_Files:
		return "library.open_files"
	case Stop_Scan:
		return "library.stop_scan"
	}
	return ""
}

// Makes an empty engine. Everything it keeps is allocated with allocator, which its
// scans' threads use too: it must be thread safe, as the default heap allocator is.
// wake, when set, is called from those threads.
init :: proc(e: ^Engine, wake := lib.Wake{}, allocator := context.allocator) {
	e.allocator = allocator
	e.wake = wake
	e.library.roots = make([dynamic]string, allocator)
	e.library.tracks = make([dynamic]lib.Track, allocator)
	e.library.unreadable = make([dynamic]lib.Scan_Error, allocator)
	e.scans = make([dynamic]^lib.Scan, allocator)
	e.stopping = make([dynamic]^lib.Scan, allocator)
	e.found = make(map[string]Track_Id, allocator)
	e.events = make([dynamic]lib.Scan_Event, allocator)
}

// Stops the scans and frees everything.
destroy :: proc(e: ^Engine) {
	context.allocator = e.allocator
	for scan in e.scans do lib.destroy_scan(scan)
	delete(e.scans)
	for scan in e.stopping do lib.destroy_scan(scan)
	delete(e.stopping)
	for &event in e.events do lib.destroy_scan_event(&event)
	delete(e.events)
	for root in e.library.roots do delete(root)
	delete(e.library.roots)
	for &track in e.library.tracks do lib.destroy_track(&track)
	delete(e.library.tracks)
	for failure in e.library.unreadable do delete(failure.path)
	delete(e.library.unreadable)
	delete(e.found)
	e^ = {}
}

// Carries out a user action at once. Scans go on in the background: poll takes in
// what they find.
execute :: proc(e: ^Engine, command: Command) {
	context.allocator = e.allocator
	switch c in command {
	case Open_Folder:
		folder := opened_path(c.path)
		open(e, {folder}, {folder})
	case Open_Files:
		paths := make([dynamic]string, 0, len(c.paths), context.temp_allocator)
		folders := make([dynamic]string, 0, len(c.paths), context.temp_allocator)
		for path in c.paths {
			opened := opened_path(path)
			append(&paths, opened)
			append(&folders, trim_separators(filepath.dir(opened)))
		}
		open(e, paths[:], folders[:])
	case Stop_Scan:
		stop_scans(e)
	}
}

// Takes in what the running scans reported since the last call, and says whether
// the library changed. The UI calls it when woken, or regularly while scans run;
// it never waits.
poll :: proc(e: ^Engine) -> (changed: bool) {
	context.allocator = e.allocator
	drop_stopped(e)
	for i := 0; i < len(e.scans); {
		scan := e.scans[i]
		clear(&e.events)
		lib.take_scan_events(scan, &e.events)
		finished: Maybe(lib.Scan_Outcome)
		for &event in e.events {
			changed = true
			switch ev in event {
			case lib.Track:
				add_track(e, ev)
			case lib.Scan_Error:
				append(&e.library.unreadable, ev)
			case lib.Scan_Outcome:
				finished = ev
			}
			event = nil
		}
		outcome, ended := finished.?
		if !ended {
			i += 1
			continue
		}
		lib.destroy_scan(scan)
		ordered_remove(&e.scans, i)
		if len(e.scans) == 0 do e.library.status = outcome == .Stopped ? .Stopped : .Completed
	}
	return
}

// Scans paths, folders or files, for tracks the library does not have yet, and
// lists folders among its roots. Paths come without trailing separators.
@(private = "file")
open :: proc(e: ^Engine, paths: []string, folders: []string) {
	for folder in folders do add_root(e, folder)
	extensions := lib.AUDIO_EXTENSIONS
	scan, started := lib.start_scan(paths, extensions[:], e.wake, e.allocator)
	if started {
		append(&e.scans, scan)
		e.library.status = .Scanning
	} else if len(e.scans) == 0 {
		e.library.status = .Failed
	}
}

// Lists a folder among the roots, unless one holds it already; it replaces those it
// holds.
@(private = "file")
add_root :: proc(e: ^Engine, folder: string) {
	roots := &e.library.roots
	for root in roots do if within(folder, root) do return
	for i := len(roots) - 1; i >= 0; i -= 1 {
		if within(roots[i], folder) {
			delete(roots[i])
			ordered_remove(roots, i)
		}
	}
	append(roots, strings.clone(folder))
	slice.sort_by(roots[:], path_less)
}

// The characters that separate a path's components.
SEPARATORS :: "/\\" when ODIN_OS == .Windows else "/"

@(private)
is_separator :: proc(c: u8) -> bool {
	return strings.index_byte(SEPARATORS, c) >= 0
}

// A path opened, as the engine keeps it: on Windows with the backslashes the scan
// joins paths with, so that one file has one path, and without trailing separators.
// Allocated with the temp allocator.
@(private)
opened_path :: proc(path: string) -> string {
	p := path
	when ODIN_OS == .Windows {
		p, _ = strings.replace_all(path, "/", `\`, context.temp_allocator)
	}
	return trim_separators(p)
}

// The path without the separators it ends with, so that a folder opened as
// `Music/` and as `Music` is one root. A volume's root keeps its separator: `/`
// stays `/`, and `D:\` stays `D:\`, since `D:` is the current folder of drive D.
@(private)
trim_separators :: proc(path: string) -> string {
	trimmed := strings.trim_right(path, SEPARATORS)
	if len(trimmed) == len(path) do return path
	if len(trimmed) == 0 do return path[:1]
	when ODIN_OS == .Windows {
		if len(trimmed) == 2 && trimmed[1] == ':' do return path[:3]
	}
	return trimmed
}

// Whether path is folder or lies inside it, comparing whole path components.
@(private)
within :: proc(path, folder: string) -> bool {
	if !strings.has_prefix(path, folder) do return false
	if len(path) == len(folder) do return true
	return is_separator(folder[len(folder) - 1]) || is_separator(path[len(folder)])
}

// Orders paths component by component, as 1.0.0 did: `A/x` comes before `A B`,
// since `A` comes before `A B`.
@(private)
path_less :: proc(a, b: string) -> bool {
	for i in 0 ..< min(len(a), len(b)) {
		x, y := a[i], b[i]
		if is_separator(x) do x = 0
		if is_separator(y) do y = 0
		if x != y do return x < y
	}
	return len(a) < len(b)
}

@(private = "file")
add_track :: proc(e: ^Engine, track: lib.Track) {
	if track.path in e.found {
		track := track
		lib.destroy_track(&track)
		return
	}
	append(&e.library.tracks, track)
	e.found[track.path] = Track_Id(len(e.library.tracks) - 1)
}

// Stops at once: what the scans report afterwards is dropped, and poll frees them
// once their threads end.
@(private = "file")
stop_scans :: proc(e: ^Engine) {
	if len(e.scans) == 0 do return
	for scan in e.scans {
		lib.stop_scan(scan)
		append(&e.stopping, scan)
	}
	clear(&e.scans)
	e.library.status = .Stopped
}

// Drops what the stopping scans reported, and frees those that ended.
@(private = "file")
drop_stopped :: proc(e: ^Engine) {
	for i := len(e.stopping) - 1; i >= 0; i -= 1 {
		scan := e.stopping[i]
		clear(&e.events)
		lib.take_scan_events(scan, &e.events)
		ended := false
		for &event in e.events {
			if _, ok := event.(lib.Scan_Outcome); ok do ended = true
			lib.destroy_scan_event(&event)
		}
		if ended {
			lib.destroy_scan(scan)
			unordered_remove(&e.stopping, i)
		}
	}
}
