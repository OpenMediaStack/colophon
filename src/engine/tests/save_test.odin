package engine_tests

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"

import id3 "../../../libs/odid3"
import "../../engine"
import lib "../../library"

// Polls the engine as the UI does, until its save ends or PATIENCE passes.
@(private = "file")
poll_until_saved :: proc(t: ^testing.T, e: ^engine.Engine) {
	start := time.tick_now()
	for engine.saving(e) != nil {
		if time.tick_since(start) > PATIENCE do testing.fail_now(t, "the save did not finish in time")
		engine.poll(e)
		time.sleep(time.Millisecond)
	}
}

@(private = "file")
two_tracks :: proc(t: ^testing.T, e: ^engine.Engine) -> string {
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v24_unicode.mp3", "2.mp3"}})
	engine_reading(t, e, folder)
	return folder
}

// What the file holds now. Free it with lib.destroy_track.
@(private = "file")
on_disk :: proc(folder, name: string) -> lib.Track {
	return lib.read_track(fmt.tprintf("%s/%s", folder, name))
}

@(private = "file")
album_on_disk :: proc(folder, name: string) -> string {
	track := on_disk(folder, name)
	defer lib.destroy_track(&track)
	return strings.clone(track.metadata.tags.album.? or_else "", context.temp_allocator)
}

@(test)
saving_writes_every_pending_change :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})

	engine.execute(&e, engine.Save{})
	testing.expect_value(t, engine.saving(&e), engine.Save_Progress{0, 2})
	poll_until_saved(t, &e)

	for name in ([]string{"1.mp3", "2.mp3"}) {
		testing.expect_value(t, album_on_disk(folder, name), "Analog Hearts")
	}
	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect_value(t, len(e.save_failures), 0)
	testing.expect(t, engine.can_undo(&e))
}

@(test)
saving_writes_the_disc_and_the_number_of_discs :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{track_named(&e, "1.mp3")})
	engine.execute(&e, engine.Apply_Edit{{.Disc, 2}})
	engine.execute(&e, engine.Apply_Edit{{.Disc_Total, 3}})

	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	track := on_disk(folder, "1.mp3")
	defer lib.destroy_track(&track)
	testing.expect(t, track.metadata.tags.disc == 2 && track.metadata.tags.disc_total == 3)
}

@(test)
undoing_a_saved_edit_brings_the_old_value_back_to_save :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{track_named(&e, "1.mp3")})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	engine.execute(&e, engine.Undo{})
	testing.expect_value(t, len(e.edits.pending), 1)
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	testing.expect_value(t, album_on_disk(folder, "1.mp3"), "Small Hours")
	testing.expect_value(t, len(e.edits.pending), 0)
}

@(test)
a_change_made_while_saving_stays_pending :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	one := track_named(&e, "1.mp3")
	engine.execute(&e, engine.Select{one})
	engine.execute(&e, engine.Apply_Edit{{.Title, "One"}})

	engine.execute(&e, engine.Save{})
	engine.execute(&e, engine.Apply_Edit{{.Title, "Two"}})
	poll_until_saved(t, &e)

	track := on_disk(folder, "1.mp3")
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.metadata.tags.title, "One")
	tags, _ := engine.shown_tags(&e, one)
	testing.expect_value(t, tags.title, "Two")
	testing.expect_value(t, len(e.edits.pending), 1)
}

@(test)
saving_nothing_does_nothing :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Save{})

	testing.expect_value(t, engine.saving(&e), nil)
}

@(test)
saving_writes_the_versions_chosen :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})

	engine.execute(&e, engine.Choose_Version{engine.Id3v2_Choice{.V2_3}})
	engine.execute(&e, engine.Choose_Version{engine.Id3v1_Choice{.V1_0}})
	testing.expect_value(t, len(e.edits.pending), 2)
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	for name in ([]string{"1.mp3", "2.mp3"}) {
		track := on_disk(folder, name)
		defer lib.destroy_track(&track)
		testing.expect_value(
			t,
			track.metadata.formats,
			lib.Tag_Formats{id3v2 = .V2_3, id3v1 = .V1_0},
		)
	}
	testing.expect_value(t, len(e.edits.pending), 0)
}

@(test)
the_write_policy_chooses_the_versions_saved :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(t, {{"v24_unicode.mp3", "1.mp3"}})
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Set_Write_Policy{{.V2_3, .Always}})
	engine.execute(&e, engine.Select{0})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})

	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	track := on_disk(folder, "1.mp3")
	defer lib.destroy_track(&track)
	testing.expect_value(
		t,
		track.metadata.formats.id3v2,
		Maybe(lib.Id3v2_Version)(lib.Id3v2_Version.V2_3),
	)
	testing.expect(t, track.metadata.formats.id3v1 != nil)
}

// A file with an ID3v1 tag, edited while the policy never writes one.
@(private = "file")
edited_while_never_writing_id3v1 :: proc(t: ^testing.T, e: ^engine.Engine) -> string {
	folder := folder_with_fixtures(t, {{"v23_v1_long_title.mp3", "1.mp3"}})
	engine_reading(t, e, folder)
	engine.execute(e, engine.Set_Write_Policy{{.V2_4, .Never}})
	engine.execute(e, engine.Select{0})
	engine.execute(e, engine.Apply_Edit{{.Album, "Analog Hearts"}})
	return folder
}

@(test)
never_writing_id3v1_strips_it_from_the_files_saved :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := edited_while_never_writing_id3v1(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	losing := engine.losing_id3v1_to_policy(&e, context.temp_allocator)
	testing.expect(t, len(losing) == 1 && losing[0] == 0)

	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	track := on_disk(folder, "1.mp3")
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.metadata.formats, lib.Tag_Formats{id3v2 = .V2_4})
}

@(test)
a_file_can_keep_the_id3v1_tag_the_policy_would_strip :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := edited_while_never_writing_id3v1(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)

	engine.execute(&e, engine.Save_Keeping_Id3v1{})
	poll_until_saved(t, &e)

	track := on_disk(folder, "1.mp3")
	defer lib.destroy_track(&track)
	testing.expect(t, track.metadata.formats.id3v1 != nil)
}

@(test)
recently_changed_lists_pending_then_saved_tracks :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	two := track_named(&e, "2.mp3")
	engine.execute(&e, engine.Select{two})
	engine.execute(&e, engine.Apply_Edit{{.Genre, "Ambient"}})
	engine.execute(&e, engine.Show_Source{engine.Recently_Changed{}})
	testing.expect(t, len(e.listed) == 1 && e.listed[0] == two)

	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect(t, len(e.listed) == 1 && e.listed[0] == two)
}

@(test)
save_commands_keep_the_ids_of_1_0 :: proc(t: ^testing.T) {
	testing.expect_value(t, engine.command_id(engine.Save{}), "tags.save")
	testing.expect_value(
		t,
		engine.command_id(engine.Save_Keeping_Id3v1{}),
		"tags.save_keeping_id3v1",
	)
}

@(test)
a_file_that_cannot_be_written_keeps_its_change :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	locked := fmt.tprintf("%s/2.mp3", folder)
	testing.expect(t, os.change_mode(locked, {.Read_User, .Read_Group, .Read_Other}) == nil)
	defer os.change_mode(locked, os.Permissions_Default)
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})

	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	if !testing.expect_value(t, len(e.save_failures), 1) do return
	testing.expect_value(
		t,
		e.save_failures[0],
		engine.Save_Failure{track_named(&e, "2.mp3"), .Read_Only},
	)
	testing.expect_value(t, len(e.edits.pending), 1)
	testing.expect_value(t, album_on_disk(folder, "1.mp3"), "Analog Hearts")
}

@(test)
a_total_without_its_number_settles_once_saved :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}})
	defer remove_folder(folder)
	path := fmt.tprintf("%s/1.mp3", folder)
	file, _ := id3.read_file(path)
	testing.expect(t, id3.set_track(&file.v2, 0, 12) == nil)
	testing.expect(t, id3.write_file(path, &file) == nil)
	id3.destroy(&file)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{0})

	engine.execute(&e, engine.Choose_Version{engine.Id3v2_Choice{.V2_4}})
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)

	testing.expect_value(t, len(e.edits.pending), 0)
	track := on_disk(folder, "1.mp3")
	defer lib.destroy_track(&track)
	testing.expect_value(t, track.metadata.tags.track_total, 12)
}

@(test)
an_undo_made_while_saving_waits_to_be_saved :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select{track_named(&e, "1.mp3")})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})

	engine.execute(&e, engine.Save{})
	engine.execute(&e, engine.Undo{})
	poll_until_saved(t, &e)

	testing.expect_value(t, album_on_disk(folder, "1.mp3"), "Analog Hearts")
	testing.expect_value(t, len(e.edits.pending), 1)
	tags, _ := engine.shown_tags(&e, track_named(&e, "1.mp3"))
	testing.expect_value(t, tags.album, "Small Hours")
}

@(test)
the_revision_moves_with_the_library_and_the_edits :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	// Reading the folder's tracks moved both already.
	testing.expect(t, e.revision > 0)
	testing.expect(t, e.library_revision > 0)
	before, library_before := e.revision, e.library_revision
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Sort_By{.Title})
	testing.expect_value(t, e.revision, before)
	// An edit changes nothing of the library until it is saved.
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})
	testing.expect(t, e.revision > before)
	testing.expect_value(t, e.library_revision, library_before)
	before = e.revision
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)
	testing.expect(t, e.revision > before)
	testing.expect(t, e.library_revision > library_before)
}

@(test)
a_save_reports_how_it_ended :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := two_tracks(t, &e)
	defer remove_folder(folder)
	defer engine.destroy(&e)
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Apply_Edit{{.Album, "Analog Hearts"}})
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)
	testing.expect_value(t, e.saves_ended, 1)
	testing.expect_value(t, e.last_save, engine.Save_Report{2, 0})

	// A file that cannot be written counts as failed, its changes still pending.
	path, _ := filepath.join({folder, "1.mp3"}, context.temp_allocator)
	testing.expect(t, set_read_only(path, true))
	defer set_read_only(path, false)
	engine.execute(&e, engine.Apply_Edit{{.Album, "Paper Hearts"}})
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)
	testing.expect_value(t, e.saves_ended, 2)
	testing.expect_value(t, e.last_save, engine.Save_Report{1, 1})
	testing.expect_value(t, len(e.edits.pending), 1)
}

@(test)
saving_a_cover_settles_the_track :: proc(t: ^testing.T) {
	e: engine.Engine
	folder := folder_with_fixtures(t, {{"v23_cover.mp3", "1.mp3"}, {"v23_full.mp3", "2.mp3"}})
	defer remove_folder(folder)
	engine_reading(t, &e, folder)
	defer engine.destroy(&e)
	cover, found := lib.read_cover(fmt.tprintf("%s/1.mp3", folder))
	defer lib.destroy_cover(&cover)
	testing.expect(t, found)
	engine.execute(&e, engine.Select_All{})
	engine.execute(&e, engine.Apply_Edit{{.Cover, cover}})
	engine.execute(&e, engine.Save{})
	poll_until_saved(t, &e)
	testing.expect_value(t, len(e.edits.pending), 0)
	testing.expect_value(t, engine.modified_fields(&e, e.selection.tracks[:]), engine.Fields{})
	for track in e.library.tracks {
		_, own := track.metadata.tags.cover.(lib.Own_Cover)
		testing.expect(t, own)
	}
	written, has := lib.read_cover(fmt.tprintf("%s/2.mp3", folder))
	defer lib.destroy_cover(&written)
	testing.expect(t, has && slice.equal(written.data, cover.data))
}
