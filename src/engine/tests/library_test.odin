package engine_tests

import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:testing"
import "core:time"

import "../../engine"

@(test)
nothing_is_open_at_start :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	testing.expect_value(t, len(e.library.roots), 0)
	testing.expect_value(t, len(e.library.tracks), 0)
	testing.expect_value(t, e.library.status, engine.Scan_Status.Idle)
}

@(test)
opening_a_folder_lists_its_mp3_files :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3", "Album/b.mp3", "cover.jpg"})
	defer remove_folder(folder)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{folder})
	testing.expect_value(t, e.library.status, engine.Scan_Status.Scanning)
	poll_until_done(t, &e)
	expect_strings(t, e.library.roots[:], {folder})
	expect_strings(t, file_names(&e), {"b.mp3", "a.mp3"})
	testing.expect_value(t, e.library.status, engine.Scan_Status.Completed)
}

@(test)
opening_another_folder_adds_its_tracks :: proc(t: ^testing.T) {
	first := folder_with(t, {"first.mp3"})
	defer remove_folder(first)
	second := folder_with(t, {"second.mp3"})
	defer remove_folder(second)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{first})
	poll_until_done(t, &e)
	engine.execute(&e, engine.Open_Folder{second})
	poll_until_done(t, &e)
	expect_strings(t, file_names(&e), {"first.mp3", "second.mp3"})
	testing.expect_value(t, len(e.library.roots), 2)
}

@(test)
two_folders_opened_at_once_are_both_read :: proc(t: ^testing.T) {
	first := folder_with(t, {"first.mp3"})
	defer remove_folder(first)
	second := folder_with(t, {"second.mp3"})
	defer remove_folder(second)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{first})
	engine.execute(&e, engine.Open_Folder{second})
	poll_until_done(t, &e)
	names := file_names(&e)
	slice.sort(names)
	expect_strings(t, names, {"first.mp3", "second.mp3"})
	testing.expect_value(t, e.library.status, engine.Scan_Status.Completed)
}

@(test)
opening_a_folder_again_lists_its_tracks_once :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3", "Album/b.mp3"})
	defer remove_folder(folder)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{fmt.tprintf("%s/Album", folder)})
	poll_until_done(t, &e)
	engine.execute(&e, engine.Open_Folder{folder})
	poll_until_done(t, &e)
	expect_strings(t, file_names(&e), {"b.mp3", "a.mp3"})
	expect_strings(t, e.library.roots[:], {folder})
}

@(test)
opening_files_lists_them_and_their_folders :: proc(t: ^testing.T) {
	folder := folder_with(t, {"One/a.mp3", "One/b.mp3", "Two/c.mp3"})
	defer remove_folder(folder)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(
		&e,
		engine.Open_Files {
			{fmt.tprintf("%s/One/a.mp3", folder), fmt.tprintf("%s/Two/c.mp3", folder)},
		},
	)
	poll_until_done(t, &e)
	expect_strings(t, file_names(&e), {"a.mp3", "c.mp3"})
	expect_strings(
		t,
		e.library.roots[:],
		{
			fmt.tprintf("%s%sOne", folder, filepath.SEPARATOR_STRING),
			fmt.tprintf("%s%sTwo", folder, filepath.SEPARATOR_STRING),
		},
	)
}

@(test)
a_root_is_a_whole_path_component :: proc(t: ^testing.T) {
	folder := folder_with(t, {"Album/a.mp3", "Album 2/b.mp3"})
	defer remove_folder(folder)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{fmt.tprintf("%s/Album", folder)})
	engine.execute(&e, engine.Open_Folder{fmt.tprintf("%s/Album 2", folder)})
	poll_until_done(t, &e)
	testing.expect_value(t, len(e.library.roots), 2)
}

@(test)
stopping_the_scan_ends_it_at_once :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3"})
	defer remove_folder(folder)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{folder})
	engine.execute(&e, engine.Stop_Scan{})
	testing.expect_value(t, e.library.status, engine.Scan_Status.Stopped)
	testing.expect(t, !engine.poll(&e), "nothing arrives once the scan is stopped")
	start := time.tick_now()
	for len(e.stopping) > 0 && time.tick_since(start) < PATIENCE {
		engine.poll(&e)
		time.sleep(time.Millisecond)
	}
	testing.expect_value(t, len(e.stopping), 0)
	testing.expect_value(t, len(e.library.tracks), 0)
}

@(test)
a_folder_opened_with_a_trailing_separator_is_one_root :: proc(t: ^testing.T) {
	folder := folder_with(t, {"a.mp3"})
	defer remove_folder(folder)
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{fmt.tprintf("%s/", folder)})
	engine.execute(&e, engine.Open_Folder{folder})
	poll_until_done(t, &e)
	expect_strings(t, e.library.roots[:], {folder})
	testing.expect_value(t, len(e.library.tracks), 1)
}

@(test)
stopping_without_a_scan_changes_nothing :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Stop_Scan{})
	testing.expect_value(t, e.library.status, engine.Scan_Status.Idle)
}

@(test)
a_missing_folder_is_reported_as_unreadable :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Open_Folder{"/this/folder/does/not/exist"})
	poll_until_done(t, &e)
	testing.expect_value(t, len(e.library.tracks), 0)
	testing.expect_value(t, len(e.library.unreadable), 1)
	testing.expect_value(t, e.library.status, engine.Scan_Status.Completed)
}

@(test)
polling_without_a_scan_reports_no_change :: proc(t: ^testing.T) {
	e: engine.Engine
	engine.init(&e)
	defer engine.destroy(&e)
	testing.expect(t, !engine.poll(&e))
}

@(test)
commands_keep_the_ids_of_1_0 :: proc(t: ^testing.T) {
	testing.expect_value(t, engine.command_id(engine.Open_Folder{}), "library.open_folder")
	testing.expect_value(t, engine.command_id(engine.Open_Files{}), "library.open_files")
	testing.expect_value(t, engine.command_id(engine.Stop_Scan{}), "library.stop_scan")
}
