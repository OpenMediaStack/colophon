package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"

// A command of the system's file manager that runs on a worker thread, which waits for it
// so that no finished process is left behind; the UI thread never waits.
@(private = "file")
Reveal_Run :: struct {
	command: []string,
}

// Opens the system's file manager on a file: selected in it where the system can do that
// (the Finder and the Explorer), else the folder that holds it.
@(private)
reveal_in_file_manager :: proc(app: ^App, data: rawptr, path: string) {
	command, selects := reveal_command(path)
	if !selects {
		open_url_in_browser(app, data, file_url(filepath.dir(path)))
		return
	}
	run := new(Reveal_Run)
	run.command = command
	if thread.create_and_start_with_data(run, run_reveal, self_cleanup = true) == nil {
		delete_reveal(run)
	}
}

@(private = "file")
run_reveal :: proc(data: rawptr) {
	run := (^Reveal_Run)(data)
	defer delete_reveal(run)
	state, stdout, stderr, err := os.process_exec({command = run.command}, context.allocator)
	_, _ = state, err
	delete(stdout)
	delete(stderr)
}

@(private = "file")
delete_reveal :: proc(run: ^Reveal_Run) {
	delete_command(run.command)
	free(run)
}

// Frees a command made by owned_command.
@(private)
delete_command :: proc(command: []string) {
	for argument in command do delete(argument)
	delete(command)
}

// Makes a command of strings the heap owns, for reveal_command.
@(private)
owned_command :: proc(arguments: ..string) -> []string {
	command := make([]string, len(arguments))
	for argument, i in arguments do command[i] = strings.clone(argument)
	return command
}
