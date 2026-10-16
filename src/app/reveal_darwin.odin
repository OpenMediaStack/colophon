#+build darwin
package main

// The Finder shows a file selected with `open -R`. The command is allocated with the
// default allocator, and freed by whoever runs it.
@(private)
reveal_command :: proc(path: string) -> (command: []string, selects: bool) {
	return owned_command("open", "-R", path), true
}
