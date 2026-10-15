package main

import "core:strconv"
import "core:strings"

// The size Colophon 1.0.0 opened at, its smallest, and the largest --size takes.
DEFAULT_WINDOW_SIZE :: [2]i32{1280, 800}
MINIMUM_WINDOW_SIZE :: [2]i32{960, 600}
MAXIMUM_WINDOW_SIZE :: [2]i32{16384, 16384}

// What the command line asks for.
Options :: struct {
	// Renders one frame without a window, saves it as a PNG at this path, and quits.
	screenshot:  string,
	window_size: [2]i32,
	// --size was given: it wins over the size the window had.
	size_asked:  bool,
}

Option_Error :: enum {
	None,
	Unknown_Option,
	Missing_Value,
	Bad_Size,
}

// Reads the command line arguments, without the program name. The strings
// of the result are slices of args.
parse_options :: proc(args: []string) -> (options: Options, err: Option_Error) {
	options.window_size = DEFAULT_WINDOW_SIZE
	for arg in args {
		// macOS may hand an app opened from the Finder its process serial number.
		if strings.has_prefix(arg, "-psn_") do continue
		name, has_value, value := strings.partition(arg, "=")
		switch name {
		case "--screenshot":
			if len(has_value) == 0 || len(value) == 0 do return options, .Missing_Value
			options.screenshot = value
		case "--size":
			if len(has_value) == 0 do return options, .Missing_Value
			options.window_size = parse_size(value) or_return
			options.size_asked = true
		case:
			return options, .Unknown_Option
		}
	}
	return options, .None
}

// What to tell the user about err.
option_error_message :: proc(err: Option_Error) -> string {
	switch err {
	case .None:
		return ""
	case .Unknown_Option:
		return "unknown option"
	case .Missing_Value:
		return "an option is missing its value"
	case .Bad_Size:
		return "the size must be WIDTHxHEIGHT, from 960x600 to 16384x16384"
	}
	return ""
}

// Reads a size such as "1280x720", between the window's minimum and maximum.
@(private = "file")
parse_size :: proc(text: string) -> (size: [2]i32, err: Option_Error) {
	width_text, separator, height_text := strings.partition(text, "x")
	if len(separator) == 0 do return {}, .Bad_Size
	width, width_ok := strconv.parse_int(width_text, 10)
	height, height_ok := strconv.parse_int(height_text, 10)
	if !width_ok || !height_ok do return {}, .Bad_Size
	size = {i32(clamp(width, 0, int(max(i32)))), i32(clamp(height, 0, int(max(i32))))}
	minimum, maximum := MINIMUM_WINDOW_SIZE, MAXIMUM_WINDOW_SIZE
	if size.x < minimum.x || size.y < minimum.y || size.x > maximum.x || size.y > maximum.y {
		return {}, .Bad_Size
	}
	return size, .None
}
