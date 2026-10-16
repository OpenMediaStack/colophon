package main

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"

// A command of the system's file manager that runs on a worker thread, which waits for it
// so that no finished process is left behind; the UI thread never waits.
@(private = "file")
Reveal_Run :: struct {
	command:   []string,
	allocator: runtime.Allocator,
}

// Opens the system's file manager on a file: selected in it where the system can do that
// (the Finder and the Explorer), else the folder that holds it. Where there is no command
// for it, SDL opens the folder.
@(private)
reveal_in_file_manager :: proc(app: ^App, data: rawptr, path: string) {
	command, found := reveal_command(path)
	started := false
	if found {
		run := new(Reveal_Run)
		run.command, run.allocator = command, context.allocator
		started = thread.create_and_start_with_data(run, run_reveal, self_cleanup = true) != nil
		if !started do delete_reveal(run)
	}
	if !started do open_url_in_browser(app, data, file_url(filepath.dir(path)))
}

@(private = "file")
run_reveal :: proc(data: rawptr) {
	run := (^Reveal_Run)(data)
	defer delete_reveal(run)
	run_command(run.command)
}

// Runs a command with nothing to read or write, and waits for it to end: the file
// managers answer by showing a window, not on a pipe, so there is none to drain.
@(private)
run_command :: proc(command: []string) {
	process, err := os.process_start({command = command})
	if err != nil do return
	_, _ = os.process_wait(process)
}

@(private = "file")
delete_reveal :: proc(run: ^Reveal_Run) {
	delete_command(run.command, run.allocator)
	free(run)
}

// Makes a command of copies of the arguments, for reveal_command.
@(private)
owned_command :: proc(allocator: runtime.Allocator, arguments: ..string) -> []string {
	command := make([]string, len(arguments), allocator)
	for argument, i in arguments do command[i] = strings.clone(argument, allocator)
	return command
}

// Frees a command made by owned_command.
@(private)
delete_command :: proc(command: []string, allocator := context.allocator) {
	for argument in command do delete(argument, allocator)
	delete(command, allocator)
}
