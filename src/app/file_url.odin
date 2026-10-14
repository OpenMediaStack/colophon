package main

import "core:fmt"
import "core:strings"

// The URL of a local file or folder, for the system to open: "file:///" then the path,
// each byte a URL cannot hold percent-encoded, since a space, an accent or a hash in a
// path is not a URL. A Windows path keeps its drive letter after the three slashes
// (RFC 8089), its backslashes turned into slashes. Allocated with the temporary
// allocator.
file_url :: proc(path: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "file://")
	if len(path) == 0 || !is_separator(path[0]) do strings.write_byte(&b, '/')
	for c in transmute([]u8)path {
		switch {
		case is_separator(c):
			strings.write_byte(&b, '/')
		case unreserved(c) || c == ':':
			strings.write_byte(&b, c)
		case:
			fmt.sbprintf(&b, "%%%02X", c)
		}
	}
	return strings.to_string(b)
}

@(private = "file")
is_separator :: proc(c: u8) -> bool {
	return c == '/' || c == '\\'
}

// The characters a URL holds as they are (RFC 3986).
@(private = "file")
unreserved :: proc(c: u8) -> bool {
	switch c {
	case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '-', '_', '.', '~':
		return true
	}
	return false
}
