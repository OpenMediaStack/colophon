#+build !darwin
#+build !windows
package main

import "core:testing"

@(test)
other_systems_open_the_folder_with_xdg_open :: proc(t: ^testing.T) {
	command, found := reveal_command("/home/me/Music/A song.mp3")
	defer delete_command(command)
	testing.expect(t, found)
	testing.expect_value(t, len(command), 2)
	testing.expect_value(t, command[0], "xdg-open")
	testing.expect_value(t, command[1], "/home/me/Music")
}
