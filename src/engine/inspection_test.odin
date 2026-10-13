package engine

import "core:testing"

@(private = "file")
shared_of :: proc(values: []Maybe(int)) -> (s: Shared(int)) {
	for value, i in values do share(&s, value, i == 0)
	return
}

@(test)
values_shared_by_every_track_show_once :: proc(t: ^testing.T) {
	testing.expect_value(t, shared_of({1, 1}), Shared(int)(1))
}

@(test)
different_values_are_mixed :: proc(t: ^testing.T) {
	testing.expect_value(t, shared_of({1, 2}), Shared(int)(Mixed{}))
}

@(test)
a_value_some_tracks_lack_is_mixed :: proc(t: ^testing.T) {
	testing.expect_value(t, shared_of({1, nil}), Shared(int)(Mixed{}))
	testing.expect_value(t, shared_of({nil, 1}), Shared(int)(Mixed{}))
}

@(test)
a_value_no_track_has_is_empty :: proc(t: ^testing.T) {
	testing.expect_value(t, shared_of({nil, nil}), nil)
	testing.expect_value(t, shared_of({}), nil)
}
