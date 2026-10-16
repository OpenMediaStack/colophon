#+build !darwin
#+build !windows
package main

// Other systems have no common way to select a file in their file manager: the folder
// opens instead.
@(private)
reveal_command :: proc(path: string) -> (command: []string, selects: bool) {
	return nil, false
}
