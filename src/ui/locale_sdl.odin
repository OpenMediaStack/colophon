package ui

import "core:strings"
import sdl "vendor:sdl3"

// The locales the system prefers, most preferred first, as SDL reads them: empty when
// it cannot tell. Allocated with allocator, the strings included; free it with
// delete_locales.
preferred_locales :: proc(allocator := context.allocator) -> []Locale {
	count: i32
	list := sdl.GetPreferredLocales(&count)
	if list == nil do return nil
	defer sdl.free(list)
	locales := make([]Locale, int(count), allocator)
	for i in 0 ..< int(count) {
		l := list[i]
		locales[i].language = clone_cstring(l.language, allocator)
		locales[i].country = clone_cstring(l.country, allocator)
	}
	return locales
}

// Frees what preferred_locales made.
delete_locales :: proc(locales: []Locale, allocator := context.allocator) {
	for l in locales {
		delete(l.language, allocator)
		delete(l.country, allocator)
	}
	delete(locales, allocator)
}

@(private = "file")
clone_cstring :: proc(s: cstring, allocator := context.allocator) -> string {
	if s == nil do return ""
	return strings.clone(string(s), allocator)
}
