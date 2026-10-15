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
	allocator:        runtime.Allocator,
	library:          Library,
	// Called by the scans' threads when they have news, to wake the UI loop.
	wake:             lib.Wake,
	scans:            [dynamic]^lib.Scan,
	// Scans asked to stop, whose threads end after the entry they are reading: poll
	// frees them then, so that the UI thread never waits for a disk.
	stopping:         [dynamic]^lib.Scan,
	// The paths of the tracks found, so that opening a file twice lists it once. The
	// keys are the paths of library.tracks.
	found:            map[string]Track_Id,
	events:           [dynamic]lib.Scan_Event,
	// Counts the changes of the library and of the edits, so that what the UI derives
	// from them (the sidebar's groups, the inspection of the selection) is made again
	// only when it must. library_revision counts those of the library alone, a scan's
	// or a save's news, for what derives from the files' tags, such as the genres.
	revision:         u64,
	library_revision: u64,
	// The source of the table's tracks, its filter and its order.
	source:           Source,
	filter:           string,
	sort:             Maybe(Sort),
	// The tracks the table lists, in its order.
	listed:           [dynamic]Track_Id,
	// The tracks saved since Colophon started.
	saved:            map[Track_Id]struct{},
	selection:        Selection,
	edits:            Edits,
	view:             View_State,
	// How saving encodes the ID3v2 tag, in developer mode.
	details:          lib.Write_Details,
	// Set by the app to play tracks; nil without a sound device, and in tests that do
	// not need sound.
	output:           Maybe(Output),
	playback:         Playback,
	// The track that last failed to play, until another plays.
	play_failure:     Maybe(Play_Failure),
	saving:           Maybe(Saving),
	// The files the last save could not write.
	save_failures:    [dynamic]Save_Failure,
	// How the last save ended, and how many saves ended, so that the UI tells each
	// once.
	last_save:        Save_Report,
	saves_ended:      int,
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
	Toggle_Sidebar,
	Toggle_Inspector,
	Toggle_Developer_Mode,
	Open_Folder,
	Open_Files,
	Stop_Scan,
	Toggle_Column,
	Resize_Columns,
	Reset_Columns,
	Move_Column,
	Show_Source,
	Filter,
	Sort_By,
	Select,
	Toggle_Selected,
	Select_Range,
	Select_All,
	Move_Selection,
	Extend_Selection,
	Apply_Edit,
	Continue_Edit,
	Edit_Tracks,
	Undo,
	Redo,
	Revert,
	Number_Tracks,
	Select_Album,
	Choose_Version,
	Save,
	Save_Keeping_Id3v1,
	Set_Write_Policy,
	Set_Write_Details,
	Rewrite,
	Play,
	Play_Pause,
	Play_Next,
	Play_Previous,
	Seek,
	Set_Volume,
	Resize_Window,
}

// A stable identifier for each kind of command, for the command palette and the
// shortcut table.
command_id :: proc(command: Command) -> string {
	switch _ in command {
	case Toggle_Sidebar:
		return "view.toggle_sidebar"
	case Toggle_Inspector:
		return "view.toggle_inspector"
	case Toggle_Developer_Mode:
		return "view.toggle_developer_mode"
	case Open_Folder:
		return "library.open_folder"
	case Open_Files:
		return "library.open_files"
	case Stop_Scan:
		return "library.stop_scan"
	case Toggle_Column:
		return "view.toggle_column"
	case Resize_Columns:
		return "view.resize_columns"
	case Reset_Columns:
		return "view.reset_columns"
	case Move_Column:
		return "view.move_column"
	case Show_Source:
		return "view.show_source"
	case Filter:
		return "view.filter"
	case Sort_By:
		return "view.sort_by"
	case Select:
		return "selection.select"
	case Toggle_Selected:
		return "selection.toggle"
	case Select_Range:
		return "selection.select_range"
	case Select_All:
		return "selection.select_all"
	case Move_Selection:
		return "selection.move"
	case Extend_Selection:
		return "selection.extend"
	case Apply_Edit:
		return "tags.edit"
	case Continue_Edit:
		return "tags.continue_edit"
	case Edit_Tracks:
		return "tags.edit_tracks"
	case Undo:
		return "edit.undo"
	case Redo:
		return "edit.redo"
	case Revert:
		return "tags.revert"
	case Number_Tracks:
		return "tags.number_tracks"
	case Select_Album:
		return "selection.select_album"
	case Choose_Version:
		return "tags.choose_version"
	case Save:
		return "tags.save"
	case Save_Keeping_Id3v1:
		return "tags.save_keeping_id3v1"
	case Set_Write_Policy:
		return "settings.write_policy"
	case Set_Write_Details:
		return "developer.write_details"
	case Rewrite:
		return "developer.rewrite"
	case Play:
		return "playback.play"
	case Play_Pause:
		return "playback.play_pause"
	case Play_Next:
		return "playback.next"
	case Play_Previous:
		return "playback.previous"
	case Seek:
		return "playback.seek"
	case Set_Volume:
		return "playback.volume"
	case Resize_Window:
		return "view.resize_window"
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
	e.listed = make([dynamic]Track_Id, allocator)
	e.saved = make(map[Track_Id]struct{}, allocator)
	e.save_failures = make([dynamic]Save_Failure, allocator)
	e.selection.tracks = make([dynamic]Track_Id, allocator)
	edits_init(&e.edits, allocator)
	e.view = DEFAULT_VIEW
	e.playback = DEFAULT_PLAYBACK
}

// Stops the scans and frees everything.
destroy :: proc(e: ^Engine) {
	context.allocator = e.allocator
	if s, running := e.saving.?; running {
		lib.destroy_save(s.save)
		delete(s.sent)
	}
	delete(e.save_failures)
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
	destroy_source(&e.source)
	delete(e.filter)
	delete(e.listed)
	delete(e.saved)
	destroy_selection(&e.selection)
	edits_destroy(&e.edits)
	e^ = {}
}

// Carries out a user action at once. Scans go on in the background: poll takes in
// what they find.
execute :: proc(e: ^Engine, command: Command) {
	context.allocator = e.allocator
	switch c in command {
	case Toggle_Sidebar:
		e.view.sidebar_visible = !e.view.sidebar_visible
	case Toggle_Inspector:
		e.view.inspector_visible = !e.view.inspector_visible
	case Toggle_Developer_Mode:
		e.view.developer_mode = !e.view.developer_mode
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
	case Toggle_Column:
		e.view.columns ~= {c.column}
	case Resize_Columns:
		// Widths the file can hold.
		widths := c.widths
		for &width in widths do width = clamp(width, 0, int(max(u32)))
		e.view.column_widths = widths
	case Reset_Columns:
		e.view.columns = DEFAULT_COLUMNS
		e.view.column_widths = nil
		e.view.column_order = DEFAULT_COLUMN_ORDER
	case Move_Column:
		move_column(&e.view.column_order, c.column, c.before)
	// Copied before the old value is freed: the command may hold the engine's own.
	case Show_Source:
		source := clone_source(c.source)
		destroy_source(&e.source)
		e.source = source
		relist(e)
	case Filter:
		text := strings.clone(c.text)
		delete(e.filter)
		e.filter = text
		relist(e)
	case Sort_By:
		descending := false
		if sort, ok := e.sort.?; ok do descending = sort.column == c.column && !sort.descending
		e.sort = Sort{c.column, descending}
		relist(e)
	case Select:
		if has_track(e, c.track) do select_one(&e.selection, c.track)
	case Toggle_Selected:
		if has_track(e, c.track) do toggle_selected(&e.selection, c.track)
	case Select_Range:
		if has_track(e, c.track) do select_range(&e.selection, c.track, e.listed[:])
	case Select_All:
		select_all(&e.selection, e.listed[:])
	case Move_Selection:
		move_selection(&e.selection, c.step, e.listed[:])
	case Extend_Selection:
		extend_selection(&e.selection, c.step, e.listed[:])
	case Apply_Edit:
		edit_tracks(e, e.selection.tracks[:], c.edit, false)
	case Continue_Edit:
		edit_tracks(e, e.selection.tracks[:], c.edit, true)
	case Edit_Tracks:
		tracks := make([dynamic]Track_Id, 0, len(c.tracks), context.temp_allocator)
		for track in c.tracks do if has_track(e, track) do append(&tracks, track)
		edit_tracks(e, tracks[:], c.edit, c.continues)
	case Undo:
		undo_step(e)
	case Redo:
		redo_step(e)
	case Revert:
		revert_tracks(e, e.selection.tracks[:])
	case Number_Tracks:
		ordered := make([dynamic]Track_Id, context.temp_allocator)
		for track in e.listed do if is_selected(&e.selection, track) do append(&ordered, track)
		number_tracks(e, ordered[:])
	case Select_Album:
		select_albums(e)
	case Choose_Version:
		choose_versions(e, e.selection.tracks[:], c.choice)
	case Save:
		save(e, false)
	case Save_Keeping_Id3v1:
		save(e, true)
	case Set_Write_Policy:
		e.edits.policy = c.policy
	case Set_Write_Details:
		e.details = c.details
	case Rewrite:
		rewrite(e, e.selection.tracks[:])
	case Play:
		play(e, c.track)
	case Play_Pause:
		play_pause(e)
	case Play_Next:
		play_next(e)
	case Play_Previous:
		play_previous(e)
	case Seek:
		seek(e, c.position)
	case Set_Volume:
		set_volume(e, c.percent)
	case Resize_Window:
		e.view.window_size = Window_Size {
			clamp(c.size.width, 0, int(max(u32))),
			clamp(c.size.height, 0, int(max(u32))),
		}
	}
	// The commands that change the library or the edits; a scan's and a save's news
	// count in poll.
	#partial switch _ in command {
	case Open_Folder,
	     Open_Files,
	     Apply_Edit,
	     Continue_Edit,
	     Edit_Tracks,
	     Undo,
	     Redo,
	     Revert,
	     Number_Tracks,
	     Choose_Version,
	     Rewrite:
		e.revision += 1
	}
}

@(private)
has_track :: proc(e: ^Engine, track: Track_Id) -> bool {
	return track >= 0 && int(track) < len(e.library.tracks)
}

// The tags a track shows: those waiting to be saved, or else its file's; false when
// its file could not be read. The pointer is valid until the tracks or the edits
// change.
shown_tags :: proc(e: ^Engine, id: Track_Id) -> (tags: ^lib.Tags, ok: bool) {
	if pending, found := &e.edits.pending[id]; found do return pending, true
	saved := saved_metadata(e, id) or_return
	return &saved.tags, true
}

// Whether a track has changes waiting to be saved, or was saved since Colophon started.
is_changed :: proc(e: ^Engine, id: Track_Id) -> bool {
	return id in e.edits.pending || id in e.saved
}

// Every listed track of the albums of the selected tracks joins the selection.
@(private = "file")
select_albums :: proc(e: ^Engine) {
	albums := make([dynamic]Album_Key, context.temp_allocator)
	for track in e.selection.tracks {
		tags := shown_tags(e, track) or_continue
		if key, ok := album_key(tags); ok do append(&albums, key)
	}
	// Sorted, so that each listed track finds its album by a binary search.
	slice.sort_by_cmp(albums[:], compare_album_keys)
	tracks := make([dynamic]Track_Id, context.temp_allocator)
	for track in e.listed {
		tags := shown_tags(e, track) or_continue
		key := album_key(tags) or_continue
		if _, found := slice.binary_search_by(albums[:], key, compare_album_keys); found {
			append(&tracks, track)
		}
	}
	add_to_selection(&e.selection, tracks[:])
}

@(private = "file")
compare_album_keys :: proc(a, b: Album_Key) -> slice.Ordering {
	if order := slice.Ordering(strings.compare(a.title, b.title)); order != .Equal do return order
	x, has_x := a.artist.?
	y, has_y := b.artist.?
	if has_x != has_y do return has_x ? .Greater : .Less
	return slice.Ordering(strings.compare(x, y))
}

@(private = "file")
clone_source :: proc(source: Source) -> Source {
	switch s in source {
	case All_Tracks, Recently_Changed, Unreadable:
		return source
	case Folder:
		return Folder{strings.clone(opened_path(s.path))}
	case Album_Key:
		artist: Maybe(string)
		if a, ok := s.artist.?; ok do artist = strings.clone(a)
		return Album_Key{strings.clone(s.title), artist}
	case Artist:
		return Artist{strings.clone(s.name)}
	}
	return All_Tracks{}
}

@(private = "file")
destroy_source :: proc(source: ^Source) {
	switch s in source {
	case All_Tracks, Recently_Changed, Unreadable:
	case Folder:
		delete(s.path)
	case Album_Key:
		delete(s.title)
		if a, ok := s.artist.?; ok do delete(a)
	case Artist:
		delete(s.name)
	}
	source^ = All_Tracks{}
}

// Takes in what the running scans and save reported since the last call, plays the
// next track when the playing one has ended, and says whether anything changed. The UI
// calls it when woken, and regularly while scans or a save run or a track plays; it
// never waits.
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
	if poll_save(e) do changed = true
	if changed {
		e.revision += 1
		e.library_revision += 1
		relist(e)
	}
	if advance_playback(e) do changed = true
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
