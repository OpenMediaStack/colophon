package library

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"

Scan_Outcome :: enum u8 {
	Completed,
	Stopped,
}

// A folder or a file the scan could not read. The scan skips it and goes on.
Scan_Error :: struct {
	path:  string,
	error: os.Error,
}

// What a scan reports, in order: the files it finds, the entries it cannot read,
// then how it ended.
Scan_Event :: union {
	Track,
	Scan_Error,
	Scan_Outcome,
}

// Called from the scan's thread when it has events to take, to wake the UI loop.
Wake :: struct {
	procedure: proc "contextless" (data: rawptr),
	data:      rawptr,
}

// A scan running on its own thread. Take its events with take_scan_events; free it
// with destroy_scan, which stops it first.
Scan :: struct {
	allocator:  runtime.Allocator,
	roots:      []string,
	extensions: []string,
	wake:       Wake,
	stop:       bool,
	mutex:      sync.Mutex,
	events:     [dynamic]Scan_Event,
	thread:     ^thread.Thread,
}

// Starts scanning roots, folders or files, one after the other on a new thread, so
// that the caller, the UI thread above all, never waits for the disk. The scan
// finishes once, after the last root. Tracks are allocated with allocator, which
// the scan's thread uses: it must be thread safe, as the default heap allocator is.
start_scan :: proc(
	roots: []string,
	extensions: []string,
	wake := Wake{},
	allocator := context.allocator,
) -> ^Scan {
	s := new(Scan, allocator)
	s.allocator = allocator
	s.roots = make([]string, len(roots), allocator)
	for root, i in roots do s.roots[i] = strings.clone(root, allocator)
	s.extensions = make([]string, len(extensions), allocator)
	for extension, i in extensions do s.extensions[i] = strings.clone(extension, allocator)
	s.wake = wake
	s.events = make([dynamic]Scan_Event, allocator)
	s.thread = thread.create_and_start_with_data(s, run_scan)
	return s
}

// Moves the events reported since the last call to the end of into. The caller owns
// them: free them with destroy_scan_event.
take_scan_events :: proc(s: ^Scan, into: ^[dynamic]Scan_Event) {
	sync.mutex_lock(&s.mutex)
	defer sync.mutex_unlock(&s.mutex)
	append(into, ..s.events[:])
	clear(&s.events)
}

// Asks the scan to stop. It ends with .Stopped after the entry it is reading.
stop_scan :: proc(s: ^Scan) {
	sync.atomic_store(&s.stop, true)
}

// Stops the scan, waits for its thread, and frees it with the events no one took.
destroy_scan :: proc(s: ^Scan) {
	stop_scan(s)
	thread.join(s.thread)
	thread.destroy(s.thread)
	for &event in s.events do destroy_scan_event(&event, s.allocator)
	delete(s.events)
	for root in s.roots do delete(root, s.allocator)
	delete(s.roots, s.allocator)
	for extension in s.extensions do delete(extension, s.allocator)
	delete(s.extensions, s.allocator)
	free(s, s.allocator)
}

destroy_scan_event :: proc(event: ^Scan_Event, allocator := context.allocator) {
	switch &e in event {
	case Track:
		destroy_track(&e, allocator)
	case Scan_Error:
		delete(e.path, allocator)
	case Scan_Outcome:
	}
	event^ = nil
}

// Walks root and its subfolders, depth first, sorted by name, and reports every file
// whose extension is in extensions, ignoring case, read with read_track. A root that
// is a file is reported alone. Hidden entries, whose name starts with a dot, are
// skipped, among them the `._` files macOS leaves on external drives. Checks stop
// between entries. Strings in the events are allocated with allocator.
scan :: proc(
	root: string,
	extensions: []string,
	stop: ^bool,
	report: proc(event: Scan_Event, data: rawptr),
	data: rawptr,
	allocator := context.allocator,
) -> Scan_Outcome {
	w := Walk{extensions, stop, report, data, allocator}
	info, err := os.stat(root, allocator)
	defer os.file_info_delete(info, allocator)
	if err != nil {
		report(Scan_Error{strings.clone(root, allocator), err}, data)
		return .Completed
	}
	if info.type != .Directory {
		if info.type == .Regular && has_extension(root, extensions) do report(read_track(root, allocator), data)
		return .Completed
	}
	return walk(&w, root) ? .Stopped : .Completed
}

@(private = "file")
Walk :: struct {
	extensions: []string,
	stop:       ^bool,
	report:     proc(event: Scan_Event, data: rawptr),
	data:       rawptr,
	allocator:  runtime.Allocator,
}

// Reports the files of folder and its subfolders; true when asked to stop.
@(private = "file")
walk :: proc(w: ^Walk, folder: string) -> (stopped: bool) {
	entries, err := os.read_all_directory_by_path(folder, w.allocator)
	defer os.file_info_slice_delete(entries, w.allocator)
	if err != nil {
		w.report(Scan_Error{strings.clone(folder, w.allocator), err}, w.data)
		return false
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for entry in entries {
		if sync.atomic_load(w.stop) do return true
		if strings.has_prefix(entry.name, ".") do continue
		// The path as the folder was given, not the one the system resolves, so that a
		// track stays inside its root.
		path := strings.concatenate({folder, filepath.SEPARATOR_STRING, entry.name}, w.allocator)
		defer delete(path, w.allocator)
		#partial switch entry.type {
		case .Directory:
			if walk(w, path) do return true
		case .Regular:
			if has_extension(entry.name, w.extensions) do w.report(read_track(path, w.allocator), w.data)
		}
	}
	return sync.atomic_load(w.stop)
}

@(private = "file")
has_extension :: proc(path: string, extensions: []string) -> bool {
	extension := strings.trim_prefix(filepath.ext(path), ".")
	for wanted in extensions {
		if strings.equal_fold(extension, wanted) do return true
	}
	return false
}

@(private = "file")
run_scan :: proc(data: rawptr) {
	s := (^Scan)(data)
	report :: proc(event: Scan_Event, data: rawptr) {
		s := (^Scan)(data)
		sync.mutex_lock(&s.mutex)
		append(&s.events, event)
		sync.mutex_unlock(&s.mutex)
		if s.wake.procedure != nil do s.wake.procedure(s.wake.data)
	}
	for root in s.roots {
		if scan(root, s.extensions, &s.stop, report, s, s.allocator) == .Stopped {
			report(Scan_Outcome.Stopped, s)
			return
		}
	}
	report(Scan_Outcome.Completed, s)
}
