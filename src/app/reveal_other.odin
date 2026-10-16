#+build !darwin
#+build !windows
package main

import "core:path/filepath"

// Other systems have no common way to select a file in their file manager: as 1.0.0 did,
// the folder that holds it opens, through `xdg-open`. Free the command with delete_command.
@(private)
reveal_command :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	command: []string,
	found: bool,
) {
	return owned_command(allocator, "xdg-open", filepath.dir(path)), true
}
