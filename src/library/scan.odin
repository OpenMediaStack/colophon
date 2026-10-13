package library

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"

// How a scan ended: after its last root, or when asked to stop.
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

// Called from the scan's thread when events wait to be taken where there were none,
// to wake the UI loop: once until the next take_scan_events.
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
// ok is false when the thread cannot be started.
start_scan :: proc(
	roots: []string,
	extensions: []string,
	wake := Wake{},
	allocator := context.allocator,
) -> (
	s: ^Scan,
	ok: bool,
) {
	s = new(Scan, allocator)
	s.allocator = allocator
	s.roots = make([]string, len(roots), allocator)
	for root, i in roots do s.roots[i] = strings.clone(root, allocator)
	s.extensions = make([]string, len(extensions), allocator)
	for extension, i in extensions do s.extensions[i] = strings.clone(extension, allocator)
	s.wake = wake
	s.events = make([dynamic]Scan_Event, allocator)
	s.thread = thread.create_and_start_with_data(s, run_scan)
	if s.thread == nil {
		destroy_scan(s)
		return nil, false
	}
	return s, true
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
	if s.thread != nil {
		thread.join(s.thread)
		thread.destroy(s.thread)
	}
	for &event in s.events do destroy_scan_event(&event, s.allocator)
	delete(s.events)
	for root in s.roots do delete(root, s.allocator)
	delete(s.roots, s.allocator)
	for extension in s.extensions do delete(extension, s.allocator)
	delete(s.extensions, s.allocator)
	free(s, s.allocator)
}

// Frees an event with the allocator its scan was started with.
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
// before the root and between entries. Strings in the events are allocated with
// allocator.
scan :: proc(
	root: string,
	extensions: []string,
	stop: ^bool,
	report: proc(event: Scan_Event, data: rawptr),
	data: rawptr,
	allocator := context.allocator,
) -> Scan_Outcome {
	if sync.atomic_load(stop) do return .Stopped
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
	entries, ok := read_folder(w, folder)
	defer {
		for entry in entries do delete(entry.name, w.allocator)
		delete(entries)
	}
	if !ok do return false
	slice.sort_by(entries[:], proc(a, b: Entry) -> bool {return a.name < b.name})
	for entry in entries {
		if sync.atomic_load(w.stop) do return true
		if strings.has_prefix(entry.name, ".") do continue
		// The path as the folder was given, not the one the system resolves, so that a
		// track stays inside its root.
		path := child_path(folder, entry.name, w.allocator)
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
Entry :: struct {
	name: string,
	type: os.File_Type,
}

// The entries of folder. An entry that cannot be read, a file removed during the scan
// say, is reported alone, under the folder as given; a folder that cannot be opened is
// reported, and false. On Linux, core:os skips an entry it cannot open and keeps only
// the last such error: that one is reported.
@(private = "file")
read_folder :: proc(w: ^Walk, folder: string) -> (entries: [dynamic]Entry, ok: bool) {
	entries = make([dynamic]Entry, w.allocator)
	f, open_err := os.open(folder)
	if open_err != nil {
		w.report(Scan_Error{strings.clone(folder, w.allocator), open_err}, w.data)
		return
	}
	defer os.close(f)
	it := os.read_directory_iterator_create(f)
	defer os.read_directory_iterator_destroy(&it)
	// The last error reported, copied: the iterator writes the next one over its own.
	last_path: string
	last_error: os.Error
	defer delete(last_path, w.allocator)
	for info in os.read_directory_iterator(&it) {
		// macOS and the BSDs give an empty entry for one they could not read.
		if info.name == "" {
			path, err := os.read_directory_iterator_error(&it)
			report_entry(w, folder, filepath.base(path), err)
			delete(last_path, w.allocator)
			last_path, last_error = strings.clone(path, w.allocator), err
			continue
		}
		append(&entries, Entry{strings.clone(info.name, w.allocator), info.type})
	}
	path, err := os.read_directory_iterator_error(&it)
	if err != nil && (path != last_path || err != last_error) {
		if strings.index_any(path, "/\\") < 0 {
			// Linux's skipped entry, by its bare name.
			report_entry(w, folder, path, err)
		} else {
			// The reading of the folder itself stopped.
			w.report(Scan_Error{strings.clone(folder, w.allocator), err}, w.data)
		}
	}
	return entries, true
}

// Reports the entry name of folder, under the folder as given rather than the path the
// system resolves, so that the error stays inside its root.
@(private = "file")
report_entry :: proc(w: ^Walk, folder, name: string, err: os.Error) {
	w.report(Scan_Error{child_path(folder, name, w.allocator), err}, w.data)
}

// The path of name in folder, with one separator between them even when folder is a
// volume's root, which ends with one.
@(private = "file")
child_path :: proc(folder, name: string, allocator: runtime.Allocator) -> string {
	if strings.has_suffix(folder, "/") || strings.has_suffix(folder, filepath.SEPARATOR_STRING) {
		return strings.concatenate({folder, name}, allocator)
	}
	return strings.concatenate({folder, filepath.SEPARATOR_STRING, name}, allocator)
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
		was_empty := len(s.events) == 0
		append(&s.events, event)
		sync.mutex_unlock(&s.mutex)
		if was_empty && s.wake.procedure != nil do s.wake.procedure(s.wake.data)
	}
	for root in s.roots {
		if scan(root, s.extensions, &s.stop, report, s, s.allocator) == .Stopped {
			report(Scan_Outcome.Stopped, s)
			return
		}
	}
	report(Scan_Outcome.Completed, s)
}
