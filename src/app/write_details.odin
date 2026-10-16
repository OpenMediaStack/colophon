package main

import "core:fmt"

import "../engine"
import lib "../library"
import ui "../ui"

@(private = "file")
LABEL_HEIGHT :: 20

// The height of a line of a hint: the small text's own line.
@(private = "file")
hint_line :: proc(r: ^ui.Renderer) -> f32 {
	return ui.line_height(r, .Small)
}

// How each encoding is named on its segment.
@(private = "file", rodata)
ENCODING_LABELS := [lib.Text_Encoding]string {
	.Latin1  = "Latin-1",
	.UTF16   = "UTF-16",
	.UTF16BE = "UTF-16BE",
	.UTF8    = "UTF-8",
}

// What the padding can be asked to be, after Auto, in bytes.
@(private = "file")
PADDINGS :: [?]int{0, 256, 1024, 4096}

// The part of the Tag format section where people who make test files choose how saving
// encodes an ID3v2 tag: the text encoding, the padding and the unsynchronisation, which
// apply to every file saved in developer mode, and the button that writes the selected
// files again with them. Gives the height it takes from top; with measure_only, it
// draws nothing.
write_details :: proc(
	ctx: ^ui.Ui,
	app: ^App,
	x, top, width: f32,
	measure_only := false,
) -> (
	height: f32,
) {
	r := ctx.renderer
	th := ctx.theme
	details := app.engine.details
	control_x, control_width := x + 12, width - 12
	y := top

	encoding_label := ui.tr("Text encoding")
	if !measure_only {
		field_label(ctx, encoding_label, {x, y, width, LABEL_HEIGHT}, false)
	}
	y += LABEL_HEIGHT
	if !measure_only {
		segments: [1 + len(lib.Text_Encoding)]ui.Segment
		segments[0] = {
			label = ui.tr("Auto"),
		}
		for encoding in lib.Text_Encoding do segments[int(encoding) + 1] = {
			label = ENCODING_LABELS[encoding],
		}
		selected := 0
		if encoding, chosen := details.encoding.?; chosen do selected = int(encoding) + 1
		picked, changed := ui.segmented(
			ctx,
			ui.widget_id("Text encoding"),
			{control_x, y, control_width, ui.BUTTON_HEIGHT},
			encoding_label,
			segments[:],
			selected,
			fit_labels = true,
		).?
		if changed {
			details.encoding = picked == 0 ? nil : lib.Text_Encoding(picked - 1)
			execute(app, engine.Set_Write_Details{details})
		}
	}
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	padding_label := ui.tr("Padding")
	if !measure_only {
		field_label(ctx, padding_label, {x, y, width, LABEL_HEIGHT}, false)
	}
	y += LABEL_HEIGHT
	if !measure_only {
		paddings := PADDINGS
		segments: [1 + len(paddings)]ui.Segment
		segments[0] = {
			label = ui.tr("Auto"),
		}
		for padding, i in paddings {
			segments[i + 1] = {
				label   = fmt.tprint(padding),
				numeric = true,
			}
		}
		selected: Maybe(int)
		if padding, chosen := details.padding.?; !chosen {
			selected = 0
		} else {
			for known, i in paddings do if known == padding do selected = i + 1
		}
		picked, changed := ui.segmented(
			ctx,
			ui.widget_id("Padding"),
			{control_x, y, control_width, ui.BUTTON_HEIGHT},
			padding_label,
			segments[:],
			selected,
		).?
		if changed {
			details.padding = picked == 0 ? nil : paddings[picked - 1]
			execute(app, engine.Set_Write_Details{details})
		}
	}
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	if !measure_only {
		toggled := ui.checkbox(
			ctx,
			ui.widget_id("Unsynchronisation"),
			{control_x, y, control_width, ui.BUTTON_HEIGHT},
			ui.tr("Unsynchronisation"),
			details.unsynchronisation,
		)
		if toggled {
			details.unsynchronisation = !details.unsynchronisation
			execute(app, engine.Set_Write_Details{details})
		}
	}
	y += ui.BUTTON_HEIGHT + FIELD_GAP

	hint := ui.tr(
		"These apply to every file saved in developer mode. UTF-16BE and UTF-8 need ID3v2.4; earlier versions get UTF-16.",
	)
	lines := ui.wrap_text(r, hint, .Small, control_width, context.temp_allocator)
	if !measure_only {
		for line, i in lines {
			ui.draw_text(
				r,
				line,
				control_x,
				y + f32(i) * hint_line(r) + hint_line(r) / 2,
				.Small,
				th.text_tertiary,
			)
		}
		ui.declare(
			ctx,
			{
				id = ui.widget_id("Write details hint"),
				role = .Label,
				label = hint,
				rect = {control_x, y, control_width, f32(len(lines)) * hint_line(r)},
			},
		)
	}
	y += f32(len(lines)) * hint_line(r) + FIELD_GAP

	if !measure_only {
		label := ui.tr("Rewrite Selected Files")
		options := ui.Button_Options {
			kind = .Secondary,
		}
		rect := ui.Rect{control_x, y, ui.button_width(r, label, options), ui.BUTTON_HEIGHT}
		if ui.button(ctx, ui.widget_id("Rewrite selected files"), rect, label, options) {
			execute(app, engine.Rewrite{})
		}
	}
	y += ui.BUTTON_HEIGHT
	return y - top
}
