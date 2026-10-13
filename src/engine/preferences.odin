package engine

import "core:fmt"
import "core:math"
import "core:strings"

import lib "../library"

// What Colophon remembers between launches, in preferences.toml.
Preferences :: struct {
	view:    View_State,
	// From 0, silent, to 100, as loud as the file.
	volume:  int,
	writing: lib.Write_Policy,
}

DEFAULT_PREFERENCES :: Preferences {
	view    = DEFAULT_VIEW,
	volume  = 80,
	writing = lib.DEFAULT_WRITE_POLICY,
}

// What to remember until the next launch.
preferences :: proc(e: ^Engine) -> Preferences {
	return {
		view = e.view,
		volume = int(math.round_f32(e.playback.volume * 100)),
		writing = e.edits.policy,
	}
}

// Starts from the preferences of the last launch.
restore :: proc(e: ^Engine, p: Preferences) {
	e.view = p.view
	e.edits.policy = p.writing
	execute(e, Set_Volume{p.volume})
}

// Reads preferences written by preferences_to_toml, or by 1.0.0. What the text lacks
// keeps its default, and text that is not such a file, a value of the wrong type
// among others, gives the defaults.
preferences_from_toml :: proc(text: string) -> Preferences {
	p, ok := read_preferences(text)
	return p if ok else DEFAULT_PREFERENCES
}

// The text of preferences.toml, as 1.0.0 wrote it. Allocated with allocator.
preferences_to_toml :: proc(p: Preferences, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	view := p.view
	fmt.sbprintfln(&b, "sidebar = %v", view.sidebar_visible)
	fmt.sbprintfln(&b, "inspector = %v", view.inspector_visible)
	shown := make([dynamic]string, context.temp_allocator)
	for column in Column do if column in view.columns do append(&shown, COLUMN_NAMES[table_column(column)])
	write_names(&b, "columns", shown[:])
	fmt.sbprintfln(&b, "volume = %d", p.volume)
	fmt.sbprintfln(&b, "id3v2 = \"%s\"", p.writing.id3v2 == .V2_3 ? "2.3" : "2.4")
	fmt.sbprintfln(&b, "id3v1 = \"%s\"", ID3V1_POLICY_NAMES[p.writing.id3v1])
	fmt.sbprintfln(&b, "developer_mode = %v", view.developer_mode)
	order: [len(Table_Column)]string
	for column, i in view.column_order do order[i] = COLUMN_NAMES[column]
	write_names(&b, "column_order", order[:])
	if size, ok := view.window_size.?; ok {
		fmt.sbprintfln(&b, "\n[window]\nwidth = %d\nheight = %d", size.width, size.height)
	}
	if widths, ok := view.column_widths.?; ok {
		strings.write_string(&b, "\n[column_widths]\n")
		for width, column in widths do fmt.sbprintfln(&b, "%s = %d", COLUMN_NAMES[column], width)
	}
	return strings.to_string(b)

	write_names :: proc(b: ^strings.Builder, key: string, names: []string) {
		fmt.sbprintf(b, "%s = [", key)
		for name, i in names do fmt.sbprintf(b, "%s\"%s\"", i > 0 ? ", " : "", name)
		strings.write_string(b, "]\n")
	}
}

// A column's name in the file.
@(private = "file", rodata)
COLUMN_NAMES := [Table_Column]string {
	.Title   = "title",
	.Artist  = "artist",
	.Album   = "album",
	.Year    = "year",
	.Genre   = "genre",
	.Time    = "time",
	.Bitrate = "bitrate",
	.Tags    = "tags",
	.File    = "file",
	.Folder  = "folder",
}

@(private = "file", rodata)
ID3V1_POLICY_NAMES := [lib.Id3v1_Policy]string {
	.Keep   = "keep",
	.Always = "always",
	.Never  = "never",
}

@(private = "file")
column_named :: proc(name: string) -> (column: Table_Column, ok: bool) {
	for n, c in COLUMN_NAMES do if n == name do return c, true
	return
}

// Every key is optional, so that an older or a hand-edited file still reads; a key
// Colophon does not know is left alone.
@(private = "file")
read_preferences :: proc(text: string) -> (p: Preferences, ok: bool) {
	p = DEFAULT_PREFERENCES
	values := parse_toml(text) or_return
	view := &p.view
	read(values, "sidebar", &view.sidebar_visible) or_return
	read(values, "inspector", &view.inspector_visible) or_return
	read(values, "developer_mode", &view.developer_mode) or_return
	if names, found := read_strings(values, "columns") or_return; found {
		view.columns = {}
		for name in names {
			column := column_named(name) or_continue
			if column != .Title do view.columns += {Column(int(column) - 1)}
		}
	}
	if names, found := read_strings(values, "column_order") or_return; found {
		columns := make([dynamic]Table_Column, context.temp_allocator)
		for name in names do if column, known := column_named(name); known do append(&columns, column)
		view.column_order = order_starting_with(columns[:])
	}
	if volume, found := read_number(values, "volume", max(u8)) or_return; found {
		p.volume = min(volume, 100)
	}
	if version, found := read_text(values, "id3v2") or_return; found && version == "2.3" {
		p.writing.id3v2 = .V2_3
	}
	if policy, found := read_text(values, "id3v1") or_return; found {
		for name, kind in ID3V1_POLICY_NAMES do if name == policy && kind != .Keep do p.writing.id3v1 = kind
	}
	if found := read_table(values, "window") or_return; found {
		// Both are needed, as 1.0.0 read them.
		width, has_width := read_number(values, "window.width", max(u32)) or_return
		height, has_height := read_number(values, "window.height", max(u32)) or_return
		if !has_width || !has_height do return
		view.window_size = Window_Size{width, height}
	}
	if found := read_table(values, "column_widths") or_return; found {
		widths: Column_Widths
		for name, column in COLUMN_NAMES {
			key := strings.concatenate({"column_widths.", name}, context.temp_allocator)
			widths[column], _ = read_number(values, key, max(u32)) or_return
		}
		view.column_widths = widths
	}
	return p, true
}

// Each reader gives found false for a missing key, and ok false for a value of
// another type.
@(private = "file")
read :: proc(values: map[string]Toml_Value, key: string, into: ^bool) -> (ok: bool) {
	value, found := values[key]
	if !found do return true
	into^ = value.(bool) or_return
	return true
}

@(private = "file")
read_number :: proc(
	values: map[string]Toml_Value,
	key: string,
	limit: $T,
) -> (
	n: int,
	found, ok: bool,
) {
	value, has := values[key]
	if !has do return 0, false, true
	number := value.(i64) or_return
	if number < 0 || number > i64(limit) do return
	return int(number), true, true
}

@(private = "file")
read_text :: proc(values: map[string]Toml_Value, key: string) -> (s: string, found, ok: bool) {
	value, has := values[key]
	if !has do return "", false, true
	s = value.(string) or_return
	return s, true, true
}

@(private = "file")
read_strings :: proc(
	values: map[string]Toml_Value,
	key: string,
) -> (
	array: []string,
	found, ok: bool,
) {
	value, has := values[key]
	if !has do return nil, false, true
	array = value.([]string) or_return
	return array, true, true
}

@(private = "file")
read_table :: proc(values: map[string]Toml_Value, key: string) -> (found, ok: bool) {
	value, has := values[key]
	if !has do return false, true
	_ = value.(Toml_Table) or_return
	return true, true
}
