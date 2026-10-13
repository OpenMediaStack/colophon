package engine

import "core:testing"

@(test)
trailing_separators_go_but_a_volume_root_keeps_its_own :: proc(t: ^testing.T) {
	testing.expect_value(t, trim_separators("/music/albums/"), "/music/albums")
	testing.expect_value(t, trim_separators("/music//"), "/music")
	testing.expect_value(t, trim_separators("/music"), "/music")
	testing.expect_value(t, trim_separators("/"), "/")
	when ODIN_OS == .Windows {
		testing.expect_value(t, trim_separators(`D:\`), `D:\`)
		testing.expect_value(t, trim_separators(`D:\Music\`), `D:\Music`)
	}
}

@(test)
within_compares_whole_components :: proc(t: ^testing.T) {
	testing.expect(t, within("/m/a/x.mp3", "/m/a"))
	testing.expect(t, within("/m/a", "/m/a"))
	testing.expect(t, !within("/m/ab/x.mp3", "/m/a"))
	testing.expect(t, within("/x.mp3", "/"))
}

@(test)
paths_are_ordered_component_by_component :: proc(t: ^testing.T) {
	testing.expect(t, path_less("/m/A/x", "/m/A B"))
	testing.expect(t, !path_less("/m/A B", "/m/A/x"))
	testing.expect(t, path_less("/m/A", "/m/A/x"))
	testing.expect(t, path_less("/m/a", "/m/b"))
}
