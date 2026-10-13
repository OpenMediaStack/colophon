#+build !windows
package library_tests

import "core:fmt"
import "core:os"
import "core:testing"

import lib ".."

@(test)
a_read_only_file_is_left_alone :: proc(t: ^testing.T) {
	folder := folder_with(t, {})
	defer remove_folder(folder)
	path := fmt.tprintf("%s/1.mp3", folder)
	testing.expect(t, os.copy_file(path, fixture("v23_full.mp3")) == nil)
	testing.expect(t, os.change_mode(path, {.Read_User, .Read_Group, .Read_Other}) == nil)

	_, err := lib.write_track(path, {title = "New"}, {.V2_4, nil})

	testing.expect_value(t, err, lib.Write_Error.Read_Only)
	track := lib.read_track(path)
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.metadata.tags.title, "Paper Satellites")
}
