#+build !darwin
#+build !windows
package main

import "core:testing"

@(test)
other_systems_open_the_folder :: proc(t: ^testing.T) {
	_, selects := reveal_command("/home/me/Music/song.mp3")
	testing.expect(t, !selects)
}
