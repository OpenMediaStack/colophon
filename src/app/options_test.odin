package main

import "core:testing"

@(test)
no_argument_opens_the_default_window :: proc(t: ^testing.T) {
	options, err := parse_options({})
	testing.expect_value(t, err, Option_Error.None)
	testing.expect_value(t, options.window_size, DEFAULT_WINDOW_SIZE)
	testing.expect_value(t, options.screenshot, "")
}

@(test)
a_screenshot_takes_a_path_and_a_size :: proc(t: ^testing.T) {
	options, err := parse_options({"--screenshot=build/smoke.png", "--size=1280x720"})
	testing.expect_value(t, err, Option_Error.None)
	testing.expect_value(t, options.screenshot, "build/smoke.png")
	testing.expect_value(t, options.window_size, [2]i32{1280, 720})
}

@(test)
a_screenshot_needs_a_path :: proc(t: ^testing.T) {
	_, err := parse_options({"--screenshot"})
	testing.expect_value(t, err, Option_Error.Missing_Value)
	_, err = parse_options({"--screenshot="})
	testing.expect_value(t, err, Option_Error.Missing_Value)
}

@(test)
a_size_is_checked :: proc(t: ^testing.T) {
	sizes := []string {
		"--size=1280",
		"--size=widexhigh",
		"--size=800x600",
		"--size=99999x900",
		"--size=-1x-1",
	}
	for size in sizes {
		_, err := parse_options({size})
		testing.expectf(t, err == .Bad_Size, "%s gave %v", size, err)
	}
	_, err := parse_options({"--size"})
	testing.expect_value(t, err, Option_Error.Missing_Value)
}

@(test)
an_unknown_option_is_refused :: proc(t: ^testing.T) {
	_, err := parse_options({"--colour=amber"})
	testing.expect_value(t, err, Option_Error.Unknown_Option)
}
