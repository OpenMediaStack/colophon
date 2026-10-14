package main

import "core:fmt"
import "core:path/filepath"
import "core:strings"

import "../engine"
import ui "../ui"

// What the window does about quitting while changes wait to be saved.
Departure :: enum u8 {
	// The dialog asks what to do with them.
	Asking,
	// The save chosen runs: the window closes once it ends, unless a file could not be
	// written.
	Saving,
	// A save was running when the user chose: once it ends, the files are saved again
	// and the window closes, or it closes at once.
	Saving_Then_Save,
	Saving_Then_Quit,
}

// Asks the window to close, as its close button does, and says whether it closes: it
// stays open to ask what to do with changes that are not saved.
request_close :: proc(app: ^App) -> (closes: bool) {
	if len(app.engine.edits.pending) > 0 {
		app.departure = .Asking
		return false
	}
	app.quit = true
	return true
}

// Tells how the save that just ended went, and goes on with a departure that waited
// for it: a file it could not write keeps the user where they are, with the failure in
// the status bar and the toast.
follow_save :: proc(app: ^App, now: f64) {
	e := &app.engine
	if e.saves_ended == app.shown_saves do return
	app.shown_saves = e.saves_ended
	report := e.last_save
	if report.failed > 0 {
		message := ui.tr_n(
			"{n} file could not be saved",
			"{n} files could not be saved",
			report.failed,
		)
		notify(app, .Error, message, .Retry_Save, now)
	} else {
		message := ui.tr_n("Saved {n} file", "Saved {n} files", report.written)
		notify(app, .Success, message, nil, now)
	}
	departure, leaving := app.departure.?
	if !leaving do return
	switch departure {
	case .Asking:
	case .Saving:
		if report.failed == 0 {
			app.quit = true
		} else {
			app.departure = nil
		}
	case .Saving_Then_Save:
		save_then_quit(app)
	case .Saving_Then_Quit:
		app.quit = true
	}
}

// Saves then quits, unless a file could not be written. Quitting asks nothing more:
// the files the write policy would strip of their ID3v1 tag keep it, as 1.0.0.
@(private = "file")
save_then_quit :: proc(app: ^App) {
	e := &app.engine
	execute(app, engine.Save_Keeping_Id3v1{})
	switch {
	case engine.saving(e) != nil:
		app.departure = .Saving
	case len(e.save_failures) == 0:
		app.quit = true
	case:
		app.departure = nil
	}
}

// The dialog that asks what to do with the changes before quitting, while the window
// asks.
unsaved_changes :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	if app.departure != .Asking do return
	e := &app.engine
	pending := len(e.edits.pending)
	options := ui.Dialog_Options {
		title    = ui.tr_n(
			"Save changes to {n} file before quitting?",
			"Save changes to {n} files before quitting?",
			pending,
		),
		message  = changed_files_text(e),
		primary  = ui.tr_n("Save {n} file", "Save {n} files", pending),
		discard  = ui.tr("Don’t Save"),
		cancel   = ui.tr("Cancel"),
		platform = app.platform,
	}
	d := ui.begin_dialog(ctx, ui.widget_id("Unsaved changes"), window, options)
	choice := ui.end_dialog(ctx, d)
	saving := engine.saving(e) != nil
	switch choice {
	case .None:
	case .Cancel:
		app.departure = nil
	case .Primary:
		if saving {
			app.departure = .Saving_Then_Save
		} else {
			save_then_quit(app)
		}
	case .Discard:
		if saving {
			app.departure = .Saving_Then_Quit
		} else {
			app.quit = true
		}
	}
}

// What the dialog says of the changed files: the first three by name, the rest
// counted, as 1.0.0. Allocated with the temporary allocator.
@(private = "file")
changed_files_text :: proc(e: ^engine.Engine) -> string {
	tracks := engine.pending_tracks(e, context.temp_allocator)
	names: [3]string
	for track, i in tracks[:min(len(tracks), 3)] do names[i] = track_name(e, track)
	files: string
	switch len(tracks) {
	case 1:
		files = ui.fill(ui.tr("{} has changes that are not saved yet."), names[0])
	case 2:
		files = ui.fill(
			ui.tr("{} and {} have changes that are not saved yet."),
			names[0],
			names[1],
		)
	case 3:
		files = ui.fill(
			ui.tr("{}, {} and {} have changes that are not saved yet."),
			names[0],
			names[1],
			names[2],
		)
	case:
		files = ui.fill(
			ui.tr("{}, {} and {} other files have changes that are not saved yet."),
			names[0],
			names[1],
			fmt.tprint(len(tracks) - 2),
		)
	}
	return strings.concatenate(
		{files, " ", ui.tr("Quitting without saving discards them.")},
		context.temp_allocator,
	)
}

// A track by its title as shown, or by its file's name without one.
@(private = "file")
track_name :: proc(e: ^engine.Engine, track: engine.Track_Id) -> string {
	if tags, readable := engine.shown_tags(e, track); readable {
		if title, has := tags.title.?; has do return title
	}
	return filepath.stem(e.library.tracks[track].path)
}
