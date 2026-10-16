#+build darwin
package main

// The Finder shows a file selected with `open -R`. Free the command with delete_command.
@(private)
reveal_command :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	command: []string,
	found: bool,
) {
	return owned_command(allocator, "open", "-R", path), true
}
