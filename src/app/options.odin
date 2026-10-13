package main

import "core:strconv"
import "core:strings"

DEFAULT_WINDOW_SIZE :: [2]i32{1440, 900}
MINIMUM_WINDOW_SIZE :: [2]i32{960, 600}

// What the command line asks for.
Options :: struct {
	// Renders one frame offscreen, saves it as a PNG at this path, and quits.
	screenshot:  string,
	window_size: [2]i32,
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
		name, has_value, value := strings.partition(arg, "=")
		switch name {
		case "--screenshot":
			if len(has_value) == 0 || len(value) == 0 do return options, .Missing_Value
			options.screenshot = value
		case "--size":
			if len(has_value) == 0 do return options, .Missing_Value
			options.window_size = parse_size(value) or_return
		case:
			return options, .Unknown_Option
		}
	}
	return options, .None
}

// Reads a size such as "1280x720", no smaller than the window's minimum.
@(private = "file")
parse_size :: proc(text: string) -> (size: [2]i32, err: Option_Error) {
	width_text, separator, height_text := strings.partition(text, "x")
	if len(separator) == 0 do return {}, .Bad_Size
	width, width_ok := strconv.parse_int(width_text, 10)
	height, height_ok := strconv.parse_int(height_text, 10)
	if !width_ok || !height_ok do return {}, .Bad_Size
	if width < int(MINIMUM_WINDOW_SIZE.x) || height < int(MINIMUM_WINDOW_SIZE.y) do return {}, .Bad_Size
	if width > 16384 || height > 16384 do return {}, .Bad_Size
	return {i32(width), i32(height)}, .None
}
