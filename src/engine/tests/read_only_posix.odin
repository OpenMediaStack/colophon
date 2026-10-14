#+build !windows
package engine_tests

import "core:os"

// Makes a file read-only, or writable again, for the tests of a save that cannot
// write. True when done.
set_read_only :: proc(path: string, read_only: bool) -> bool {
	mode :=
		read_only ? os.Permissions{.Read_User, .Read_Group, .Read_Other} : os.Permissions_Default
	return os.change_mode(path, mode) == nil
}
