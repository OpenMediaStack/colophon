#+build windows
package main

import "core:strings"

// The Explorer shows a file selected with `explorer /select,<path>`, one argument. The
// command is allocated with the default allocator, and freed by whoever runs it.
@(private)
reveal_command :: proc(path: string) -> (command: []string, selects: bool) {
	select := strings.concatenate({"/select,", path}, context.temp_allocator)
	return owned_command("explorer", select), true
}
