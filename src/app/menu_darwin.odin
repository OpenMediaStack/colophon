#+build darwin
package main

import "base:intrinsics"

import NS "core:sys/darwin/Foundation"
import sdl "vendor:sdl3"

import ui "../ui"

// What the macOS menu bar holds between frames: its items by menu and line, to bring
// their titles and their being enabled up to date with the app's menus every frame.
Native_Menu :: struct {
	installed: bool,
	items:     [dynamic][dynamic]^NS.MenuItem,
}

// A choice travels as an SDL user event: its type is the tag's high part and the choice
// itself, the number of the menu times MENU_CODE plus the number of the line, is its
// code. The tag of the item holds both, so that the callback, which receives nothing
// else, needs no state of its own.
@(private)
menu_tag :: proc(event_type: u32, menu, line: int) -> NS.Integer {
	return NS.Integer(event_type) << 16 | NS.Integer(menu * MENU_CODE + line)
}

@(private)
menu_tag_parts :: proc "contextless" (tag: NS.Integer) -> (event_type: u32, choice: int) {
	return u32(tag >> 16), int(tag & 0xffff)
}

// Every item sends this action: it posts its choice to the loop, as a key would arrive.
@(private = "file")
on_menu_action :: proc "c" (unused: rawptr, name: NS.SEL, sender: ^NS.Object) {
	event_type, choice := menu_tag_parts(intrinsics.objc_send(NS.Integer, sender, "tag"))
	event: sdl.Event
	event.type = sdl.EventType(event_type)
	event.user.code = i32(choice)
	_ = sdl.PushEvent(&event)
}

@(private = "file")
string_of :: proc(text: string) -> ^NS.String {
	return NS.String.alloc()->initWithOdinString(text)
}

// Sets the app's menus as the menu bar of macOS, once SDL has made its window: the
// application menu with About and Settings, then File, Edit, Controls and View, and in
// the application menu the standard Hide and Quit, which the system does itself.
// Shortcuts stay with the window: a menu that took them would take the text fields'
// Command Z, which the window gives them first.
@(private = "file")
install_native_menu :: proc(ctx: ^ui.Ui, app: ^App, event_type: u32) {
	n := &app.native_menu
	n.installed = true
	action := NS.MenuItem.registerActionCallback("colophonMenuAction", on_menu_action)
	bar := NS.Menu.alloc()->init()
	menus := app_menus(ctx, app)
	for menu, m in menus {
		submenu := NS.Menu.alloc()->initWithTitle(string_of(menu.title))
		// The app says what can run, not the system's validation of the action.
		no := NS.BOOL(false)
		intrinsics.objc_send(nil, submenu, "setAutoenablesItems:", no)
		items := make([dynamic]^NS.MenuItem)
		for line, l in menu.lines {
			if line.separator do submenu->addItem(NS.MenuItem.separatorItem())
			item := NS.MenuItem.alloc()->initWithTitle(
				string_of(line.entry.label),
				action,
				string_of(""),
			)
			item->setTag(menu_tag(event_type, m, l))
			submenu->addItem(item)
			append(&items, item)
		}
		if m == 0 {
			// The standard items of the application menu: the system hides and quits.
			submenu->addItem(NS.MenuItem.separatorItem())
			hide := NS.MenuItem.alloc()->initWithTitle(
				string_of(ui.fill(ui.tr("Hide {}"), "Colophon")),
				NS.sel_registerName("hide:"),
				string_of("h"),
			)
			hide->setKeyEquivalentModifierMask({.Command})
			submenu->addItem(hide)
			submenu->addItem(NS.MenuItem.separatorItem())
			quit := NS.MenuItem.alloc()->initWithTitle(
				string_of(ui.fill(ui.tr("Quit {}"), "Colophon")),
				NS.sel_registerName("terminate:"),
				string_of("q"),
			)
			quit->setKeyEquivalentModifierMask({.Command})
			submenu->addItem(quit)
		}
		holder := NS.MenuItem.alloc()->init()
		holder->setSubmenu(submenu)
		bar->addItem(holder)
		append(&n.items, items)
	}
	NS.Application.sharedApplication()->setMainMenu(bar)
}

// Brings the macOS menu bar up to date with the app's menus: made at the first frame of
// a window that has one, then each title and whether it can run follow the app. Does
// nothing without a menu event type, which only a real window has.
sync_native_menu :: proc(ctx: ^ui.Ui, app: ^App) {
	event_type, wanted := app.menu_event.?
	if !wanted || app.platform != .Mac do return
	if !app.native_menu.installed do install_native_menu(ctx, app, event_type)
	menus := app_menus(ctx, app)
	for menu, m in menus {
		if m >= len(app.native_menu.items) do break
		for line, l in menu.lines {
			if l >= len(app.native_menu.items[m]) do break
			item := app.native_menu.items[m][l]
			if title := string_of(line.entry.label);
			   NS.String_odinString(item->title()) != line.entry.label {
				item->setTitle(title)
			}
			item->setEnabled(line.entry.enabled)
		}
	}
}
