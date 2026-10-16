package main

import "core:math"
import "core:path/filepath"
import "core:time"

import "../engine"
import ui "../ui"

// The bar under the table: its height, without the line above it.
PLAYER_HEIGHT :: 56
@(private = "file")
PADDING :: 16
@(private = "file")
SPACING :: 12
// Between the previous, play and next buttons.
@(private = "file")
CONTROLS_GAP :: 6
// What plays: its title and artist, in this width.
@(private = "file")
TITLE_WIDTH :: 140
@(private = "file")
WAVEFORM_HEIGHT :: 36
// A bar of 2 points every 3: a bar for every second or two of a song.
@(private = "file")
BAR_STRIDE :: 3
@(private = "file")
BAR_WIDTH :: 2
// How often a frame is drawn for the playhead while a track plays, in seconds.
@(private = "file")
REPAINT :: 0.1
// The volume goes first when the bar narrows.
@(private = "file")
WITH_VOLUME_FROM :: 800
@(private = "file")
VOLUME_WIDTH :: 100

// Whether the player shows: a track plays, or is paused, through an output.
player_shown :: proc(app: ^App) -> bool {
	return engine.can_play(&app.engine) && app.engine.playback.track != nil
}

// The room where a seek never goes, from the end: a position the decoder does not reach
// ends the track, as the last of its frames would.
@(private)
SEEK_MARGIN :: 250 * time.Millisecond

// Where the parts of the bar go, from its width and what its times need.
@(private = "file")
Player_Layout :: struct {
	previous, play, next:         ui.Rect,
	title:                        ui.Rect,
	position_text, duration_text: ui.Rect,
	// Where the position is, the waveform of the next slice, and the volume.
	position:                     ui.Rect,
	volume_icon, volume:          ui.Rect,
	with_volume:                  bool,
}

@(private = "file")
player_layout :: proc(rect: ui.Rect, time_width: f32) -> (l: Player_Layout) {
	middle := rect.y + rect.h / 2
	x := rect.x + PADDING
	l.previous = {x, middle - 14, 28, 28}
	x += 28 + CONTROLS_GAP
	l.play = {x, middle - 18, 36, 36}
	x += 36 + CONTROLS_GAP
	l.next = {x, middle - 14, 28, 28}
	x += 28 + SPACING
	l.title = {x, middle - 18, TITLE_WIDTH, 34}
	x += TITLE_WIDTH + SPACING
	l.position_text = {x, middle - 8, time_width, 16}
	x += time_width + SPACING
	right := rect.x + rect.w - PADDING
	l.with_volume = rect.w >= WITH_VOLUME_FROM
	if l.with_volume {
		l.volume = {
			right - VOLUME_WIDTH,
			middle - ui.SLIDER_HEIGHT / 2,
			VOLUME_WIDTH,
			ui.SLIDER_HEIGHT,
		}
		right -= VOLUME_WIDTH + SPACING
		l.volume_icon = {right - 16, middle - 8, 16, 16}
		right -= 16 + SPACING
	}
	l.duration_text = {right - time_width, middle - 8, time_width, 16}
	right -= time_width + SPACING
	l.position = {x, middle - ui.SLIDER_HEIGHT / 2, max(right - x, 0), ui.SLIDER_HEIGHT}
	return
}

// The bar under the table, while a track plays or is paused: what plays, its controls,
// where it is and how loud. Its widgets are declared from left to right, which is the
// order the Tab key goes through them.
player_bar :: proc(ctx: ^ui.Ui, app: ^App, rect: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	e := &app.engine
	track_id, has_track := e.playback.track.?
	if !has_track || int(track_id) >= len(e.library.tracks) do return
	ui.fill_rect(r, rect, th.surface_2)
	id := ui.widget_id("Player")
	ui.declare(ctx, {id = id, role = .Group, label = ui.tr("Player"), rect = rect})
	ui.push_parent(ctx, id)
	defer ui.pop_parent(ctx)

	duration := e.library.tracks[track_id].metadata.audio.duration
	// A position past the duration, where the tags are short, shows as the duration.
	position := engine.position(e)
	if duration > 0 do position = min(position, duration)
	position_text, duration_text_value := duration_text(position), duration_text(duration)
	time_width := max(
		ui.text_width(r, "00:00", .Numeric),
		ui.text_width(r, position_text, .Numeric),
		ui.text_width(r, duration_text_value, .Numeric),
	)
	l := player_layout(rect, time_width)

	controls(ctx, app, id, l)
	title, artist := playing_names(e, track_id)
	ui.draw_text_fit(r, title, l.title.x, l.title.y + 10, l.title.w, .Body_Strong, th.text_primary)
	ui.draw_text_fit(r, artist, l.title.x, l.title.y + 27, l.title.w, .Small, th.text_secondary)
	ui.declare(
		ctx,
		{
			id = ui.child_id(id, "title"),
			role = .Label,
			label = title,
			rect = {l.title.x, l.title.y, l.title.w, 18},
		},
	)
	if artist != "" {
		ui.declare(
			ctx,
			{
				id = ui.child_id(id, "artist"),
				role = .Label,
				label = artist,
				rect = {l.title.x, l.title.y + 18, l.title.w, 16},
			},
		)
	}
	time_label(ctx, id, "position text", position_text, l.position_text, .Left)
	progress: f32 = 0
	if duration > 0 do progress = f32(f64(position) / f64(duration))
	seeker(ctx, app, id, l.position, progress, duration)
	time_label(ctx, id, "duration text", duration_text_value, l.duration_text, .Right)
	if l.with_volume do volume(ctx, app, id, l)
	// The playhead moves while the track plays: a frame now and then.
	if engine.playing(e.playback) do ui.wake_at(ctx, ctx.input.time + REPAINT)
}

// Previous, play or pause, next.
@(private = "file")
controls :: proc(ctx: ^ui.Ui, app: ^App, id: ui.Widget_Id, l: Player_Layout) {
	if ui.toolbar_button(
		ctx,
		ui.child_id(id, "previous"),
		l.previous,
		.Skip_Back,
		ui.tr("Previous track"),
	) {
		execute(app, engine.Play_Previous{})
	}
	playing := engine.playing(app.engine.playback)
	// The same words as the palette's: the catalogue tells them apart from a menu's.
	label := playing ? ui.tr("Pause") : ui.tr("Play", "Player")
	icon: ui.Icon = playing ? .Pause : .Play
	if ui.disc_button(ctx, ui.child_id(id, "play"), l.play, icon, label, playing ? 0 : 1) {
		execute(app, engine.Play_Pause{})
	}
	if ui.toolbar_button(
		ctx,
		ui.child_id(id, "next"),
		l.next,
		.Skip_Forward,
		ui.tr("Next track"),
	) {
		execute(app, engine.Play_Next{})
	}
}

@(private = "file")
time_label :: proc(
	ctx: ^ui.Ui,
	parent: ui.Widget_Id,
	name, text: string,
	rect: ui.Rect,
	align: ui.Align,
) {
	x := align == .Right ? rect.x + rect.w : rect.x
	ui.draw_text(
		ctx.renderer,
		text,
		x,
		rect.y + rect.h / 2,
		.Numeric,
		ctx.theme.text_secondary,
		align,
	)
	ui.declare(ctx, {id = ui.child_id(parent, name), role = .Label, label = text, rect = rect})
}

// The position: the track's waveform, bars of 2 points every 3, the part played in the
// accent colour; a click or a drag along it seeks. A track without a duration has
// nothing to seek in.
@(private = "file")
seeker :: proc(
	ctx: ^ui.Ui,
	app: ^App,
	id: ui.Widget_Id,
	rect: ui.Rect,
	progress: f32,
	duration: time.Duration,
) {
	area := ui.Rect{rect.x, rect.y + (rect.h - WAVEFORM_HEIGHT) / 2, rect.w, WAVEFORM_HEIGHT}
	scrubbed := ui.scrub(
		ctx,
		ui.child_id(id, "position"),
		area,
		ui.tr("Position"),
		progress,
		disabled = duration <= 0,
	)
	played := progress
	if moved, changed := scrubbed.changed.?; changed {
		target := min(time.Duration(f64(duration) * f64(moved)), max(duration - SEEK_MARGIN, 0))
		execute(app, engine.Seek{target})
		played = moved
	}
	draw_waveform(ctx, &app.waveform, area, played)
	if scrubbed.focused && ctx.focus_by_key do ui.draw_focus_ring(ctx.renderer, ctx.theme, area, 4)
}

// The volume: its icon and a bar to click or drag along.
@(private = "file")
volume :: proc(ctx: ^ui.Ui, app: ^App, id: ui.Widget_Id, l: Player_Layout) {
	ui.draw_icon(ctx.renderer, .Volume, l.volume_icon, ctx.theme.text_secondary)
	moved, changed := ui.slider(
		ctx,
		ui.child_id(id, "volume"),
		l.volume,
		ui.tr("Volume"),
		app.engine.playback.volume,
	).?
	if changed do execute(app, engine.Set_Volume{int(moved * 100 + 0.5)})
}

// The title and the artist of the playing track, as the inspector shows them: its tags
// waiting to be saved, or its file's; the file's name for a track without a title.
// Allocated with the temporary allocator when it must be.
@(private = "file")
playing_names :: proc(e: ^engine.Engine, track: engine.Track_Id) -> (title, artist: string) {
	tags, readable := engine.shown_tags(e, track)
	if readable {
		title = tags.title.? or_else ""
		artist = tags.artist.? or_else ""
	}
	if title == "" do title = filepath.stem(e.library.tracks[track].path)
	return
}

// Tells, in a toast, a track that could not play: each failure once, the same file again
// included.
follow_play_failure :: proc(app: ^App, now: f64) {
	e := &app.engine
	if e.play_failures == app.told_failures do return
	app.told_failures = e.play_failures
	failure, failed := e.play_failure.?
	if !failed || failure.track < 0 || int(failure.track) >= len(e.library.tracks) do return
	name := filepath.base(e.library.tracks[failure.track].path)
	notify(app, .Error, ui.fill(ui.tr("Could not play “{}”"), name), nil, now)
}

// The bars of the waveform in area, as loud as each share of the track sounds, the part
// played, up to progress, in the accent colour: flat until the waveform is read.
@(private = "file")
draw_waveform :: proc(ctx: ^ui.Ui, w: ^Waveform_State, area: ui.Rect, progress: f32) {
	r := ctx.renderer
	th := ctx.theme
	count := max(1, int((area.w + BAR_STRIDE - BAR_WIDTH) / BAR_STRIDE))
	bars := waveform_bars(w, count)
	end := f32(count * BAR_STRIDE - (BAR_STRIDE - BAR_WIDTH))
	// Square bars on whole points: a radius of 1 on a 2 point bar is all fringe, which at a
	// scale of 1 left a bright pixel and two half bright ones where 1.0.0 has two and a gap.
	left := math.round(area.x)
	played := left + end * clamp(progress, 0, 1)
	middle := area.y + area.h / 2
	for loudness, i in bars {
		height := max(2, math.round(loudness * area.h))
		bar := ui.Rect {
			left + f32(i) * BAR_STRIDE,
			math.round(middle - height / 2),
			BAR_WIDTH,
			height,
		}
		if bar.x + bar.w <= played {
			ui.fill_rect(r, bar, th.accent)
			continue
		}
		ui.fill_rect(r, bar, th.border_strong)
		if bar.x < played do ui.fill_rect(r, {bar.x, bar.y, played - bar.x, bar.h}, th.accent)
	}
}
