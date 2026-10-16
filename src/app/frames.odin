package main

import "core:fmt"
import "core:strings"
import "core:time"

import "../engine"
import lib "../library"
import ui "../ui"

@(private = "file")
FRAME_LINE :: 16
@(private = "file")
DETAIL_LINE :: 14
@(private = "file")
BLOCK_GAP :: 8
// Where the value and the details of a frame start, past its name.
@(private = "file")
VALUE_INDENT :: 48

// The most frames the section lists: a hostile file can hold tens of thousands, and
// every row costs a frame's time.
@(private = "file")
MAX_FRAMES :: 200

// The layout of the tags of the track the inspector shows, with the file it was read
// from: a track is read again when its file changes, by its size and time, not when
// the library does for other tracks.
Shown_Layout :: struct {
	track:    engine.Track_Id,
	size:     i64,
	modified: time.Time,
	// False when the file could not be read: tried once, not at every frame.
	found:    bool,
	layout:   lib.Tag_Layout,
}

// In developer mode, with a single readable track selected, how its tags are laid out.
// It is read from the file, on the UI thread (see the plan's decision on it), when the
// track changes or its file does, a save included. nil in any other case.
shown_layout :: proc(app: ^App, s: engine.Summary) -> ^lib.Tag_Layout {
	e := &app.engine
	alone := e.view.developer_mode && s.count == 1 && s.unreadable == 0
	if !alone || len(e.selection.tracks) != 1 {
		forget_layout(app)
		return nil
	}
	track := e.selection.tracks[0]
	file := &e.library.tracks[track]
	if shown, has := &app.inspector.layout.?; has {
		if shown.track != track || shown.size != file.size || shown.modified != file.modified {
			forget_layout(app)
		}
	}
	if app.inspector.layout == nil {
		layout, found := lib.read_layout(file.path, e.allocator)
		app.inspector.layout = Shown_Layout{track, file.size, file.modified, found, layout}
	}
	shown := &app.inspector.layout.?
	return shown.found ? &shown.layout : nil
}

// Frees the layout shown.
forget_layout :: proc(app: ^App) {
	if shown, has := &app.inspector.layout.?; has {
		lib.destroy_layout(&shown.layout, app.engine.allocator)
	}
	app.inspector.layout = nil
}

// The Frames section: where the tag and each of its frames are, then where the ID3v1
// tag starts. Gives the height it takes under its header; with measure_only, it
// draws nothing.
frames_section :: proc(
	ctx: ^ui.Ui,
	layout: ^lib.Tag_Layout,
	x, top, width: f32,
	measure_only := false,
) -> (
	height: f32,
) {
	r := ctx.renderer
	th := ctx.theme
	y := top
	block :: proc(
		ctx: ^ui.Ui,
		text: string,
		id: ui.Widget_Id,
		x: f32,
		y: ^f32,
		width: f32,
		measure_only: bool,
	) {
		lines := ui.wrap_text(ctx.renderer, text, .Small, width, context.temp_allocator)
		if !measure_only {
			for line, i in lines {
				ui.draw_text(
					ctx.renderer,
					line,
					x,
					y^ + f32(i) * FRAME_LINE + FRAME_LINE / 2,
					.Small,
					ctx.theme.text_secondary,
				)
			}
			rect := ui.Rect{x, y^, width, f32(len(lines)) * FRAME_LINE}
			ui.declare(ctx, {id = id, role = .Label, label = text, rect = rect})
		}
		y^ += f32(len(lines)) * FRAME_LINE + BLOCK_GAP
	}
	block(ctx, layout_summary(layout), ui.widget_id("Tag size"), x, &y, width, measure_only)
	if flags := tag_flags(layout); flags != "" {
		block(ctx, flags, ui.widget_id("Tag flags"), x, &y, width, measure_only)
	}
	shown := layout.frames[:min(len(layout.frames), MAX_FRAMES)]
	for frame, i in shown {
		value := single_line(frame_value(frame))
		details := frame_details(frame, layout.unsynchronisation && layout.version != .V2_4)
		lines := ui.wrap_text(r, details, .Hint, width - VALUE_INDENT, context.temp_allocator)
		if !measure_only {
			ui.draw_text(r, frame.id, x, y + FRAME_LINE / 2, .Numeric, th.text_primary)
			ui.draw_text_fit(
				r,
				value,
				x + VALUE_INDENT,
				y + FRAME_LINE / 2,
				width - VALUE_INDENT,
				.Small,
				frame.kind == .Text ? th.text_primary : th.text_secondary,
			)
			ui.declare(
				ctx,
				{
					id = ui.widget_id("Frame", i),
					role = .Row,
					label = fmt.tprintf("%s %s", frame.id, value),
					rect = {x, y, width, FRAME_LINE},
					actions = {.Scroll_Into_View},
				},
			)
		}
		y += FRAME_LINE + 1
		if !measure_only {
			for line, j in lines {
				ui.draw_text(
					r,
					line,
					x + VALUE_INDENT,
					y + f32(j) * DETAIL_LINE + DETAIL_LINE / 2,
					.Hint,
					th.text_tertiary,
				)
			}
			ui.declare(
				ctx,
				{
					id = ui.widget_id("Frame details", i),
					role = .Label,
					label = details,
					rect = {
						x + VALUE_INDENT,
						y,
						width - VALUE_INDENT,
						f32(len(lines)) * DETAIL_LINE,
					},
				},
			)
		}
		y += f32(len(lines)) * DETAIL_LINE + BLOCK_GAP
	}
	if more := len(layout.frames) - len(shown); more > 0 {
		text := ui.tr_n("{n} more frame", "{n} more frames", more)
		block(ctx, text, ui.widget_id("More frames"), x, &y, width, measure_only)
	}
	if offset, has := layout.id3v1_offset.?; has {
		text := ui.fill(ui.tr("ID3v1 at {}, 128 bytes"), fmt.tprint(offset))
		block(ctx, text, ui.widget_id("ID3v1 offset"), x, &y, width, measure_only)
	}
	return y - top
}

// The tag's version, size and padding: "ID3v2.3.0 · 226 bytes · 10 bytes of padding".
@(private)
layout_summary :: proc(layout: ^lib.Tag_Layout) -> string {
	if !layout.has_id3v2 do return ui.tr("No ID3v2 tag")
	version := fmt.tprintf("%s.%d", version_major(layout.version), layout.revision)
	return ui.fill(
		ui.tr("ID3v2.{} · {} bytes · {} bytes of padding"),
		version,
		fmt.tprint(layout.size),
		fmt.tprint(layout.padding),
	)
}

@(private = "file")
version_major :: proc(version: lib.Id3v2_Version) -> string {
	switch version {
	case .V2_2:
		return "2"
	case .V2_3:
		return "3"
	case .V2_4:
		return "4"
	}
	return ""
}

// What is set in the tag's header, apart from the version: empty when nothing is.
@(private)
tag_flags :: proc(layout: ^lib.Tag_Layout) -> string {
	return joined(
		{
			layout.unsynchronisation ? ui.tr("Unsynchronised") : "",
			layout.extended_header ? ui.tr("Extended header") : "",
			layout.experimental ? ui.tr("Experimental") : "",
			layout.footer ? ui.tr("Footer") : "",
		},
	)
}

// What a frame holds, in a few words.
@(private)
frame_value :: proc(frame: lib.Frame_Layout) -> string {
	switch frame.kind {
	case .Text:
		return frame.value
	case .Picture:
		return ui.fill(ui.tr("{}, {} bytes"), frame.value, fmt.tprint(frame.picture_size))
	case .Sealed:
		return ui.tr("Compressed or encrypted")
	case .Binary:
		return ui.tr_n("{n} byte of data", "{n} bytes of data", frame.size)
	}
	return ""
}

// Where a frame is, how big, in which encoding, and its flags: "at 10 · 18 bytes ·
// ISO-8859-1". Before ID3v2.4 a tag unsynchronised as a whole has each of its frames
// so, as 1.0.0 told it; odid3 only flags the frames of ID3v2.4.
@(private)
frame_details :: proc(frame: lib.Frame_Layout, tag_unsynchronised := false) -> string {
	place := joined(
		{
			ui.fill(ui.tr("at {}"), fmt.tprint(frame.offset)),
			ui.tr_n("{n} byte", "{n} bytes", frame.size),
		},
	)
	encoding := ""
	if found, has := frame.encoding.?; has do encoding = lib.encoding_name(found)
	return joined(
		{
			place,
			encoding,
			frame.read_only ? ui.tr("read only") : "",
			frame.grouping ? ui.tr("grouped") : "",
			frame.compression ? ui.tr("compressed") : "",
			frame.encryption ? ui.tr("encrypted") : "",
			frame.unsynchronised || tag_unsynchronised ? ui.tr("unsynchronised") : "",
			frame.data_length ? ui.tr("data length") : "",
		},
	)
}

// The parts that are not empty, with a dot between them. Allocated with the temporary
// allocator.
@(private = "file")
joined :: proc(parts: []string) -> string {
	kept := make([dynamic]string, context.temp_allocator)
	for part in parts do if part != "" do append(&kept, part)
	return strings.join(kept[:], " · ", context.temp_allocator)
}

// text on one line: its line breaks and other control characters are spaces, so that
// a frame's text never pushes the rows under it down. Allocated with the temporary
// allocator when it changes.
@(private)
single_line :: proc(text: string) -> string {
	has_control := false
	for b in transmute([]u8)text do if b < ' ' || b == 0x7f do has_control = true
	if !has_control do return text
	flat := transmute([]u8)strings.clone(text, context.temp_allocator)
	for &b in flat do if b < ' ' || b == 0x7f do b = ' '
	return string(flat)
}
