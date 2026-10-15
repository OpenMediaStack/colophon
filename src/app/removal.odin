package main

import "core:path/filepath"
import "core:strings"

import "../engine"
import ui "../ui"

// The files listed by name in the removal dialog, as 1.0.0 listed them; the others are
// counted.
@(private = "file")
LISTED_FILES :: 8
@(private = "file")
FILE_ROW :: 18
@(private = "file")
FILES_PADDING :: 10

// A removal waiting for the user's answer: nothing else would say what the files
// lose. The names are the app's own, freed by forget_removal. A removal that came from
// choosing versions carries the choice; one that came from saving carries none.
Removal :: struct {
	tag:    engine.Removable_Tag,
	// The names of every file losing the tag.
	files:  [dynamic]string,
	choice: Maybe(engine.Version_Choice),
}

// Saves, after asking first when the write policy would strip files of their ID3v1
// tag: keeping it saves them as they are, removing saves under the policy. Nothing
// happens while a save runs.
request_save :: proc(app: ^App) {
	if engine.saving(&app.engine) != nil do return
	tracks := engine.losing_id3v1_to_policy(&app.engine, context.temp_allocator)
	if len(tracks) == 0 {
		execute(app, engine.Save{})
		return
	}
	ask_removal(app, .Id3v1, tracks, nil)
}

// Chooses a tag version for the selected tracks, after asking first when the choice
// removes a tag some of their files have and keep.
request_version :: proc(app: ^App, choice: engine.Version_Choice) {
	tag: engine.Removable_Tag
	switch c in choice {
	case engine.Id3v2_Choice:
		if c.version != nil {
			execute(app, engine.Choose_Version{choice})
			return
		}
		tag = .Id3v2
	case engine.Id3v1_Choice:
		if c.version != nil {
			execute(app, engine.Choose_Version{choice})
			return
		}
		tag = .Id3v1
	case nil:
		return
	}
	tracks := engine.losing_tag(&app.engine, tag, context.temp_allocator)
	if len(tracks) == 0 {
		execute(app, engine.Choose_Version{choice})
		return
	}
	ask_removal(app, tag, tracks, choice)
}

// Asks before a tag goes, in place of a removal that waits, if one does: the dialog
// is modal, so none can be asked meanwhile but through the palette, which closes.
@(private = "file")
ask_removal :: proc(
	app: ^App,
	tag: engine.Removable_Tag,
	tracks: []engine.Track_Id,
	choice: Maybe(engine.Version_Choice),
) {
	forget_removal(app)
	files := make([dynamic]string, 0, len(tracks), app.engine.allocator)
	for track in tracks {
		name := filepath.base(app.engine.library.tracks[track].path)
		append(&files, strings.clone(name, app.engine.allocator))
	}
	app.removal = Removal{tag, files, choice}
	// The dialog shows at once, whatever asked for it: a key was taken, not a command.
	app.commands += 1
}

// Frees the removal waiting, if one is; app_destroy calls it too.
forget_removal :: proc(app: ^App) {
	if removal, asking := &app.removal.?; asking {
		for name in removal.files do delete(name, app.engine.allocator)
		delete(removal.files)
	}
	app.removal = nil
}

// What the removal dialog says of a tag removed from count files.
@(private = "file")
Removal_Texts :: struct {
	title, message, remove, keep: string,
}

@(private = "file")
removal_texts :: proc(tag: engine.Removable_Tag, count: int) -> Removal_Texts {
	if tag == .Id3v1 {
		return {
			ui.tr_n(
				"Remove the ID3v1 tag from {n} file?",
				"Remove the ID3v1 tag from {n} files?",
				count,
			),
			ui.tr(
				"Some old players and car stereos only read ID3v1. After saving, these files will no longer have one.",
			),
			ui.tr("Remove ID3v1"),
			ui.tr("Keep ID3v1"),
		}
	}
	return {
		ui.tr_n(
			"Remove the ID3v2 tag from {n} file?",
			"Remove the ID3v2 tag from {n} files?",
			count,
		),
		ui.tr(
			"ID3v2 holds what ID3v1 cannot: the album artist, the track total, long titles and comments, the cover. After saving, these files will lose them.",
		),
		ui.tr("Remove ID3v2"),
		ui.tr("Keep ID3v2"),
	}
}

// The dialog that asks before a tag goes, while a removal waits: the files that lose
// it, the first few by name. Return does not remove, Escape keeps.
removal_dialog :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	removal, asking := &app.removal.?
	if !asking do return
	r := ctx.renderer
	th := ctx.theme
	count := len(removal.files)
	listed := min(count, LISTED_FILES)
	others := count - listed
	rows := listed + (others > 0 ? 1 : 0)
	texts := removal_texts(removal.tag, count)
	options := ui.Dialog_Options {
		title          = texts.title,
		message        = texts.message,
		primary        = texts.remove,
		cancel         = texts.keep,
		destructive    = true,
		content_height = f32(rows) * FILE_ROW + 2 * FILES_PADDING,
		platform       = app.platform,
	}
	d := ui.begin_dialog(ctx, ui.widget_id("Tag removal"), window, options)
	box := d.content
	ui.fill_rect(r, box, th.surface_1, 4)
	ui.stroke_rect(r, box, th.border_subtle, 4)
	y := box.y + FILES_PADDING
	for name, i in removal.files[:listed] {
		ui.draw_text_fit(
			r,
			name,
			box.x + FILES_PADDING,
			y + FILE_ROW / 2,
			box.w - 2 * FILES_PADDING,
			.Numeric,
			th.text_primary,
		)
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Removed file", i),
				role = .Label,
				label = name,
				rect = {box.x + FILES_PADDING, y, box.w - 2 * FILES_PADDING, FILE_ROW},
			},
		)
		y += FILE_ROW
	}
	if others > 0 {
		more := ui.tr_n("and {n} other file", "and {n} other files", others)
		ui.draw_text(r, more, box.x + FILES_PADDING, y + FILE_ROW / 2, .Small, th.text_tertiary)
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Other files"),
				role = .Label,
				label = more,
				rect = {box.x + FILES_PADDING, y, box.w - 2 * FILES_PADDING, FILE_ROW},
			},
		)
	}
	ui.declare(
		ctx,
		{id = ui.widget_id("Files"), role = .Group, label = ui.tr("Files"), rect = box},
	)
	switch ui.end_dialog(ctx, d) {
	case .None:
	case .Primary:
		choice := removal.choice
		forget_removal(app)
		if chosen, versions := choice.?; versions {
			execute(app, engine.Choose_Version{chosen})
		} else {
			execute(app, engine.Save{})
		}
	case .Cancel, .Discard:
		choice := removal.choice
		forget_removal(app)
		// Keeping the tag changes nothing of a choice, and saves a save as it is.
		if _, versions := choice.?; !versions do execute(app, engine.Save_Keeping_Id3v1{})
	}
}
