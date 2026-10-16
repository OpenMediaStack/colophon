#+build !windows
package main

import "core:testing"

// The worker's command ends and is waited for, without a pipe to drain, and a command that
// does not exist ends at once.
@(test)
a_command_runs_to_its_end_and_a_missing_one_does_not_hang :: proc(t: ^testing.T) {
	run_command({"true"})
	run_command({"colophon-no-such-command"})
}
