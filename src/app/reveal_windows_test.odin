#+build windows
package main

import "core:testing"

@(test)
the_explorer_is_asked_to_select_the_file :: proc(t: ^testing.T) {
	command, found := reveal_command(`C:\Users\me\Music\A song.mp3`)
	defer delete_command(command)
	testing.expect(t, found)
	testing.expect_value(t, len(command), 2)
	testing.expect_value(t, command[0], "explorer")
	testing.expect_value(t, command[1], `/select,C:\Users\me\Music\A song.mp3`)
	free_all(context.temp_allocator)
}
