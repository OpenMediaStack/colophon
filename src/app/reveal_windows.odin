#+build windows
package main

import "core:strings"

// The Explorer shows a file selected with `explorer /select,<path>`, one argument. Free
// the command with delete_command.
@(private)
reveal_command :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	command: []string,
	found: bool,
) {
	select := strings.concatenate({"/select,", path}, context.temp_allocator)
	return owned_command(allocator, "explorer", select), true
}
