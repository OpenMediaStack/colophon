#+build darwin
package main

import "core:testing"

@(test)
the_finder_is_asked_to_select_the_file :: proc(t: ^testing.T) {
	command, selects := reveal_command("/Users/me/Music/A song.mp3")
	defer delete_command(command)
	testing.expect(t, selects)
	testing.expect_value(t, len(command), 3)
	testing.expect_value(t, command[0], "open")
	testing.expect_value(t, command[1], "-R")
	testing.expect_value(t, command[2], "/Users/me/Music/A song.mp3")
}
