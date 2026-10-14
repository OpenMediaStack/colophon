package main

import "core:fmt"
import "core:os"

main :: proc() {
	options, err := parse_options(os.args[1:])
	if err != .None {
		fmt.eprintfln(
			"colophon: %s. Usage: colophon [--size=WIDTHxHEIGHT] [--screenshot=FILE.png]",
			option_error_message(err),
		)
		os.exit(2)
	}
	if !run(options) do os.exit(1)
}
