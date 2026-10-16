package main

import "core:strings"

import "../ui"

@(private = "file")
APP_ICON :: #load("../../assets/icon/png/colophon-128.png")
@(private = "file")
SOURCE_URL :: "https://github.com/OpenMediaStack/colophon"

// A piece of software Colophon ships, under its license. The texts are embedded.
Third_Party :: struct {
	name:    string,
	// Empty for the fonts and icons, which have none of their own.
	version: string,
	license: string,
	source:  string,
	text:    string,
}

// What Colophon ships, sorted by name as the licenses list shows it.
@(rodata)
THIRD_PARTY := [?]Third_Party {
	{
		"Fontstash",
		"",
		"zlib License",
		"https://github.com/memononen/fontstash",
		#load("../../assets/licenses/zlib-fontstash.txt"),
	},
	{
		"Inter",
		"",
		"SIL Open Font License 1.1",
		"https://github.com/rsms/inter",
		#load("../../assets/fonts/OFL-Inter.txt"),
	},
	{
		"JetBrains Mono",
		"",
		"SIL Open Font License 1.1",
		"https://github.com/JetBrains/JetBrainsMono",
		#load("../../assets/fonts/OFL-JetBrainsMono.txt"),
	},
	{
		"Lucide",
		"",
		"ISC License",
		"https://github.com/lucide-icons/lucide",
		#load("../../assets/icons/LICENSE-lucide.txt"),
	},
	{
		"miniaudio",
		"",
		"Public domain or MIT No Attribution",
		"https://github.com/mackron/miniaudio",
		#load("../../assets/licenses/miniaudio.txt"),
	},
	{
		"odid3",
		"",
		"MIT License",
		"https://github.com/OpenMediaStack/odid3",
		#load("../../libs/odid3/LICENSE"),
	},
	{
		"Odin",
		"",
		"zlib License",
		"https://odin-lang.org/",
		#load("../../assets/licenses/zlib-odin.txt"),
	},
	{
		"SDL",
		"3.4",
		"zlib License",
		"https://libsdl.org/",
		#load("../../assets/licenses/zlib-sdl3.txt"),
	},
	{
		"stb",
		"",
		"MIT License or public domain",
		"https://github.com/nothings/stb",
		#load("../../assets/licenses/stb.txt"),
	},
}

// What the About dialog keeps between frames.
About :: struct {
	open:     bool,
	// The licenses of what Colophon ships show in place of the credits.
	licenses: bool,
	selected: int,
	// The licenses list's scroll, and the text's.
	list:     ui.Scroll,
	scroll:   ui.Scroll,
	// The icon, made into a texture when first shown, kept when About closes; a failure
	// is kept too, so that the image is not decoded again at every frame.
	icon:     Maybe(ui.Texture_Id),
	no_icon:  bool,
}

// Opens the About dialog, unless another dialog is up: it waits for it.
show_about :: proc(app: ^App) {
	if app.settings_open || app.removal != nil || app.departure != nil do return
	app.about = {
		open    = true,
		icon    = app.about.icon,
		no_icon = app.about.no_icon,
	}
	// The dialog shows at once, whatever asked for it: a key was taken, not a command.
	app.commands += 1
}

// Asks the system to open an address in the browser.
open_url :: proc(app: ^App, url: string) {
	if app.dialogs.open_url != nil do app.dialogs.open_url(app, app.dialogs.data, url)
}

// The About dialog, while open: Colophon's version and license, and in place of them
// the licenses of what it ships.
about_dialog :: proc(ctx: ^ui.Ui, app: ^App, window: ui.Rect) {
	a := &app.about
	if !a.open do return
	options := ui.Dialog_Options {
		label          = ui.tr("About Colophon"),
		title          = a.licenses ? ui.tr("Third-party licenses") : "",
		message        = a.licenses ? ui.tr("Colophon ships these fonts, icons and libraries, each under its own license.") : "",
		primary        = ui.tr("Close"),
		discard        = a.licenses ? ui.tr("Back") : ui.tr("Third-party licenses"),
		width          = a.licenses ? 760 : 400,
		content_height = a.licenses ? 300 : 150,
		platform       = app.platform,
	}
	d := ui.begin_dialog(ctx, ui.widget_id("About"), window, options)
	if a.licenses {
		licenses_view(ctx, app, d.content)
	} else {
		credits_view(ctx, app, d.content)
	}
	switch ui.end_dialog(ctx, d) {
	case .None:
	case .Primary, .Cancel:
		a.open = false
	case .Discard:
		a.licenses = !a.licenses
		a.scroll = {}
	}
}

@(private = "file")
credits_view :: proc(ctx: ^ui.Ui, app: ^App, box: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	a := &app.about
	if _, made := a.icon.?; !made && !a.no_icon {
		a.no_icon = true
		if rgba, w, h, decoded := ui.decode_image(APP_ICON, context.temp_allocator); decoded {
			if texture, ok := ui.create_image(ctx, rgba, w, h); ok {
				a.icon = texture
				a.no_icon = false
			}
		}
	}
	icon := ui.Rect{box.x, box.y, 56, 56}
	if texture, has := a.icon.?; has {
		ui.draw_image(r, texture, icon, 12)
	} else {
		ui.fill_rect(r, icon, th.surface_3, 12)
	}
	x := box.x + 56 + 14
	name_width := ui.draw_text(r, "Colophon", x, box.y + 18, .Heading, th.text_primary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("About name"),
			role = .Label,
			label = "Colophon",
			rect = {x, box.y + 4, name_width, 28},
		},
	)
	version := ui.fill(ui.tr("Version {}"), app.version)
	version_width := ui.draw_text(r, version, x, box.y + 42, .Body, th.text_secondary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("About version"),
			role = .Label,
			label = version,
			rect = {x, box.y + 34, version_width, 18},
		},
	)
	y := box.y + 56 + 16
	description := ui.tr("An MP3 tag editor.")
	ui.draw_text_fit(r, description, box.x, y + 9, box.w, .Body, th.text_secondary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("About description"),
			role = .Label,
			label = description,
			rect = {box.x, y, box.w, 18},
		},
	)
	y += 22
	license := strings.concatenate(
		{"© 2026 Florent Sorel. ", ui.tr("Released under the MIT License.")},
		context.temp_allocator,
	)
	ui.draw_text_fit(r, license, box.x, y + 8, box.w, .Small, th.text_tertiary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("About license"),
			role = .Label,
			label = license,
			rect = {box.x, y, box.w, 16},
		},
	)
	y += 22
	if link(ctx, app, ui.widget_id("About link"), SOURCE_URL, {box.x, y}) do open_url(app, SOURCE_URL)
}

// A link button, flush with the text around it, labelled with the address without its
// scheme. Gives whether it was clicked.
@(private = "file")
link :: proc(ctx: ^ui.Ui, app: ^App, id: ui.Widget_Id, url: string, at: [2]f32) -> bool {
	label := strings.trim_prefix(url, "https://")
	options := ui.Button_Options {
		kind  = .Link,
		flush = true,
	}
	rect := ui.Rect{at.x, at.y, ui.button_width(ctx.renderer, label, options), 24}
	return ui.button(ctx, id, rect, label, options)
}

// The list of what Colophon ships at the left, the selected one's license at the right.
@(private = "file")
licenses_view :: proc(ctx: ^ui.Ui, app: ^App, box: ui.Rect) {
	r := ctx.renderer
	th := ctx.theme
	a := &app.about
	LIST :: 200
	ROW :: 28
	list := ui.Rect{box.x, box.y, LIST, box.h}
	list_id := ui.widget_id("Components")
	ui.declare(ctx, {id = list_id, role = .Group, label = ui.tr("Components"), rect = list})
	ui.push_parent(ctx, list_id)
	content := [2]f32{LIST, f32(len(THIRD_PARTY)) * ROW}
	origin := ui.begin_scroll(ctx, list_id, list, content, &a.list)
	for notice, i in THIRD_PARTY {
		row := ui.Rect{box.x, origin.y + f32(i) * ROW, LIST, ROW}
		id := ui.widget_id("Notice", i)
		interaction := ui.interact(ctx, id, row)
		if .Hovered in interaction do ctx.cursor = .Pointer
		if .Clicked in interaction {
			a.selected = i
			a.scroll = {}
		}
		switch {
		case i == a.selected:
			ui.fill_rect(r, row, th.accent_selection, 4)
		case .Hovered in interaction:
			ui.fill_rect(r, row, th.surface_2, 4)
		}
		ui.draw_text_fit(
			r,
			notice.name,
			row.x + 8,
			row.y + row.h / 2,
			row.w - 16,
			.Body,
			i == a.selected ? th.text_primary : th.text_secondary,
		)
		states: ui.Widget_States = i == a.selected ? {.Selected} : {}
		ui.declare(ctx, {id = id, role = .Row, label = notice.name, rect = row, states = states})
	}
	ui.end_scroll(ctx, list_id, list, content, &a.list)
	ui.pop_parent(ctx)

	notice := THIRD_PARTY[clamp(a.selected, 0, len(THIRD_PARTY) - 1)]
	pane := ui.Rect{box.x + LIST + 16, box.y, box.w - LIST - 16, box.h}
	heading := notice.version != "" ? ui.fill("{} {}", notice.name, notice.version) : notice.name
	ui.draw_text(r, heading, pane.x, pane.y + 10, .Title, th.text_primary)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Notice heading"),
			role = .Label,
			label = heading,
			rect = {pane.x, pane.y, pane.w, 20},
		},
	)
	ui.draw_text(r, notice.license, pane.x, pane.y + 34, .Small, th.text_secondary)
	if notice.source != "" {
		if link(ctx, app, ui.widget_id("Notice source"), notice.source, {pane.x, pane.y + 46}) {
			open_url(app, notice.source)
		}
	}
	TEXT_TOP :: 76
	text_area := ui.Rect{pane.x, pane.y + TEXT_TOP, pane.w, pane.h - TEXT_TOP}
	ui.fill_rect(r, text_area, th.surface_1, 4)
	ui.stroke_rect(r, text_area, th.border_subtle, 4)
	inner := ui.rect_inset(text_area, 8, 8)
	lines := ui.wrap_text(r, notice.text, .Numeric, inner.w - 14, context.temp_allocator)
	LINE :: 16
	text_content := [2]f32{inner.w, f32(len(lines)) * LINE}
	scroll_id := ui.widget_id("Notice text")
	text_origin := ui.begin_scroll(ctx, scroll_id, inner, text_content, &a.scroll)
	first := max(int((inner.y - text_origin.y) / LINE), 0)
	last := min(len(lines), first + int(inner.h / LINE) + 2)
	for line, i in lines[first:last] {
		y := text_origin.y + f32(first + i) * LINE + LINE / 2
		ui.draw_text(r, line, inner.x, y, .Numeric, th.text_primary)
	}
	ui.end_scroll(ctx, scroll_id, inner, text_content, &a.scroll)
	ui.declare(
		ctx,
		{
			id = ui.widget_id("Notice license text"),
			role = .Label,
			label = notice.text,
			rect = inner,
		},
	)
}
