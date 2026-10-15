package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "../engine"
import lib "../library"
import ui "../ui"

// The main screen, tall enough for every section of the inspector in developer mode,
// with one fixture selected.
@(private = "file")
screen_with_one_track :: proc(t: ^testing.T, s: ^Screen, fixture: string) -> (folder: string) {
	screen_init(s, {1440, 1800})
	folder = folder_with_fixtures(t, {{fixture, "1.mp3"}})
	open_folder_of(t, s, folder)
	wait_until_shown(t, s, "1 track")
	execute(&s.app, engine.Select{s.app.engine.listed[0]})
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	return
}

// 1.0.0's developer_mode.rs: the frames of a track show where they are.
@(test)
the_frames_of_a_track_show_where_they_are :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_one_track(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, shows(&s, "ID3v2.3.0 · 226 bytes · 10 bytes of padding"))
	testing.expect(t, shows(&s, "TIT2 Paper Satellites"))
	testing.expect(t, shows(&s, "at 10 · 18 bytes · ISO-8859-1"))
	execute(&s.app, engine.Toggle_Developer_Mode{})
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "TIT2 Paper Satellites"))
}

// 1.0.0's test chose 2.4 on its ID3v2.3 file, which saving rewrote as 2.4. Here 2.4 is
// already what saving writes, so the file is rewritten in 2.2, a choice that changes.
@(test)
the_frames_show_again_once_saved :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_one_track(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "2.2"))
	ui.press_key(&s.h, .S, ui.COMMAND)
	wait_for_save(t, &s)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	shown := false
	for w in s.h.ui.widgets do if strings.has_prefix(w.label, "ID3v2.2.0 · ") do shown = true
	testing.expect(t, shown)
}

@(test)
a_file_with_only_an_id3v1_tag_says_where_it_starts :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_one_track(t, &s, "v1_1_ascii.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, shows(&s, "No ID3v2 tag"))
	offset := s.app.engine.library.tracks[0].size - 128
	testing.expect(t, shows(&s, fmt.tprintf("ID3v1 at %d, 128 bytes", offset)))
}

@(test)
no_frames_show_for_several_tracks :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 1800})
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v24_full.mp3", "2.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "2 tracks")
	execute(&s.app, engine.Toggle_Developer_Mode{})
	execute(&s.app, engine.Select{s.app.engine.listed[0]})
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "Frames"))
	execute(&s.app, engine.Select_Range{s.app.engine.listed[1]})
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "Frames"))
	testing.expect(t, shows(&s, "Tag format"))
}

@(test)
the_frames_fold_with_their_header :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_one_track(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	testing.expect(t, ui.click(&s.h, "Frames"))
	ui.run_frame(&s.h)
	testing.expect(t, !shows(&s, "TIT2 Paper Satellites"))
	testing.expect(t, ui.click(&s.h, "Frames"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "TIT2 Paper Satellites"))
}

@(test)
a_picture_and_the_flags_of_a_frame_are_told :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	picture := lib.Frame_Layout {
		id           = "APIC",
		offset       = 40,
		size         = 5000,
		kind         = .Picture,
		value        = "image/png",
		picture_size = 4990,
	}
	testing.expect_value(t, frame_value(picture), "image/png, 4990 bytes")
	testing.expect_value(t, frame_details(picture), "at 40 · 5000 bytes")
	sealed := lib.Frame_Layout {
		id          = "TXXX",
		offset      = 7,
		size        = 1,
		kind        = .Sealed,
		encoding    = .UTF16BE,
		read_only   = true,
		grouping    = true,
		compression = true,
		encryption  = true,
		data_length = true,
	}
	testing.expect_value(t, frame_value(sealed), "Compressed or encrypted")
	testing.expect_value(
		t,
		frame_details(sealed),
		"at 7 · 1 byte · UTF-16BE · read only · grouped · compressed · encrypted · data length",
	)
	binary := lib.Frame_Layout {
		id             = "PRIV",
		size           = 3,
		kind           = .Binary,
		unsynchronised = true,
	}
	testing.expect_value(t, frame_value(binary), "3 bytes of data")
	testing.expect_value(t, frame_details(binary), "at 0 · 3 bytes · unsynchronised")
	// A frame of a tag unsynchronised as a whole is told so too, before ID3v2.4.
	title := lib.Frame_Layout {
		id     = "TIT2",
		offset = 10,
		size   = 18,
		kind   = .Text,
	}
	testing.expect_value(t, frame_details(title), "at 10 · 18 bytes")
	testing.expect_value(t, frame_details(title, true), "at 10 · 18 bytes · unsynchronised")
}

@(test)
the_flags_of_a_tag_are_told_when_set :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	layout := lib.Tag_Layout {
		has_id3v2 = true,
	}
	testing.expect_value(t, tag_flags(&layout), "")
	layout.unsynchronisation, layout.footer = true, true
	testing.expect_value(t, tag_flags(&layout), "Unsynchronised · Footer")
	layout.extended_header, layout.experimental = true, true
	testing.expect_value(
		t,
		tag_flags(&layout),
		"Unsynchronised · Extended header · Experimental · Footer",
	)
}

// The same texts in French, from 1.0.0's catalogue: checked on the catalogue itself,
// since the one in use is shared by every test.
@(test)
the_frames_speak_french :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: ui.Catalog
	if !testing.expect(t, ui.catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer ui.catalog_destroy(&c)
	testing.expect_value(t, ui.catalog_tr(&c, "Frames"), "Trames")
	testing.expect_value(
		t,
		ui.fill(
			ui.catalog_tr(&c, "ID3v2.{} · {} bytes · {} bytes of padding"),
			"3.0",
			"226",
			"10",
		),
		"ID3v2.3.0 · 226 octets · 10 octets de remplissage",
	)
	testing.expect_value(
		t,
		ui.catalog_tr_n(&c, "{n} byte of data", "{n} bytes of data", 1, ""),
		"1 octet de données",
	)
	testing.expect_value(t, ui.catalog_tr(&c, "read only"), "lecture seule")
	testing.expect_value(
		t,
		ui.catalog_tr_n(&c, "{n} more frame", "{n} more frames", 100, ""),
		"100 autres trames",
	)
}

@(private = "file")
many_frames :: proc(count: int) -> lib.Tag_Layout {
	layout := lib.Tag_Layout {
		has_id3v2 = true,
		version   = .V2_3,
		size      = 10_000,
	}
	layout.frames = make([]lib.Frame_Layout, count, context.temp_allocator)
	for &frame, i in layout.frames {
		frame = {
			id     = "TPE1",
			offset = i64(10 + 12 * i),
			size   = 2,
			kind   = .Text,
			value  = "A",
		}
	}
	return layout
}

// A file with tens of thousands of frames lists the first 200, then says how many more
// there are, so that a frame's time does not grow with the file.
@(test)
the_frames_are_listed_up_to_a_limit :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	defer free_all(context.temp_allocator)
	exactly := many_frames(200)
	more := many_frames(300)
	huge := many_frames(50_000)
	at_limit := frames_section(&s.h.ui, &exactly, 0, 0, 300, true)
	over := frames_section(&s.h.ui, &more, 0, 0, 300, true)
	way_over := frames_section(&s.h.ui, &huge, 0, 0, 300, true)
	// One more line, "100 more frames", under the 200 listed.
	testing.expect_value(t, over, at_limit + 16 + 8)
	testing.expect_value(t, way_over, over)
}

@(test)
a_frame_s_text_shows_on_one_line :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, single_line("plain text"), "plain text")
	testing.expect_value(t, single_line("a\nb\r\nc\n\n"), "a b  c  ")
	testing.expect_value(t, single_line("tab\there\x01"), "tab here ")
	testing.expect_value(t, single_line("坂本\n龍一"), "坂本 龍一")
}

@(private = "file")
shows_prefix :: proc(s: ^Screen, prefix: string) -> bool {
	for w in s.h.ui.widgets do if strings.has_prefix(w.label, prefix) do return true
	return false
}

@(test)
selecting_another_track_shows_its_layout :: proc(t: ^testing.T) {
	s: Screen
	screen_init(&s, {1440, 1800})
	folder := folder_with_fixtures(t, {{"v23_full.mp3", "1.mp3"}, {"v24_full.mp3", "2.mp3"}})
	defer remove_folder(folder)
	defer screen_destroy(&s)
	open_folder_of(t, &s, folder)
	wait_until_shown(t, &s, "2 tracks")
	execute(&s.app, engine.Toggle_Developer_Mode{})
	e := &s.app.engine
	execute(&s.app, engine.Select{e.listed[0]})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows_prefix(&s, "ID3v2.3.0 · "))
	execute(&s.app, engine.Select{e.listed[1]})
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, shows_prefix(&s, "ID3v2.4.0 · "))
	testing.expect(t, !shows_prefix(&s, "ID3v2.3.0 · "))
}

// Scans and saves of other tracks change the library at every poll: the layout of the
// track shown is read again only when its own file changes.
@(test)
the_layout_is_not_read_again_while_the_library_changes_around_it :: proc(t: ^testing.T) {
	s: Screen
	folder := screen_with_one_track(t, &s, "v23_full.mp3")
	defer remove_folder(folder)
	defer screen_destroy(&s)
	first := s.app.inspector.layout.?.layout.frames
	testing.expect(t, len(first) > 0)
	for _ in 0 ..< 3 {
		s.app.engine.library_revision += 1
		s.app.engine.revision += 1
		ui.run_frame(&s.h)
	}
	testing.expect(t, raw_data(s.app.inspector.layout.?.layout.frames) == raw_data(first))
	// Its file changing, by its size, reads it again.
	s.app.engine.library.tracks[0].size += 1
	ui.run_frame(&s.h)
	testing.expect(t, raw_data(s.app.inspector.layout.?.layout.frames) != raw_data(first))
}
