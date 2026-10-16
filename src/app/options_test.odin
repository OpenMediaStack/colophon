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
a_size_may_reach_both_limits :: proc(t: ^testing.T) {
	options, err := parse_options({"--size=960x600"})
	testing.expect_value(t, err, Option_Error.None)
	testing.expect_value(t, options.window_size, MINIMUM_WINDOW_SIZE)
	options, err = parse_options({"--size=16384x16384"})
	testing.expect_value(t, err, Option_Error.None)
	testing.expect_value(t, options.window_size, MAXIMUM_WINDOW_SIZE)
	_, err = parse_options({"--size=16385x900"})
	testing.expect_value(t, err, Option_Error.Bad_Size)
	_, err = parse_options({"--size=959x600"})
	testing.expect_value(t, err, Option_Error.Bad_Size)
}

@(test)
every_error_has_a_message :: proc(t: ^testing.T) {
	for err in Option_Error {
		if err == .None do continue
		testing.expectf(t, len(option_error_message(err)) > 0, "%v has no message", err)
	}
}

@(test)
an_unknown_argument_is_ignored :: proc(t: ^testing.T) {
	options, err := parse_options(
		{"-psn_0_123456", "--colour=amber", "/Users/me/song.mp3", "--size=1000x700"},
	)
	testing.expect_value(t, err, Option_Error.None)
	testing.expect_value(t, options.window_size, [2]i32{1000, 700})
}
