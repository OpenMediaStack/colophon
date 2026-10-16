#+build darwin
package main

import "core:strings"

import NS "core:sys/darwin/Foundation"
import sdl "vendor:sdl3"

import ui "../ui"

// What the macOS menu bar holds between frames: its items by menu and line, to bring
// their titles and their being enabled up to date with the app's menus every frame.
// Free it with destroy_native_menu.
Native_Menu :: struct {
	installed: bool,
	items:     [dynamic][dynamic]^NS.MenuItem,
}

// Frees what the native menu keeps. The menu bar and its items live as long as the
// process, which the system owns them for.
destroy_native_menu :: proc(n: ^Native_Menu) {
	for items in n.items do delete(items)
	delete(n.items)
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
	event_type, choice := menu_tag_parts((^NS.MenuItem)(sender)->tag())
	event: sdl.Event
	event.type = sdl.EventType(event_type)
	event.user.code = i32(choice)
	_ = sdl.PushEvent(&event)
}

// An NSString that reads the bytes of text without copying them: a menu item copies its
// title, so release the string once it is set, and do not keep it past the text.
@(private = "file")
string_of :: proc(text: string) -> ^NS.String {
	return NS.String.alloc()->initWithOdinString(text)
}

// The app's menus as a menu bar for macOS: the application menu with About and Settings,
// then File, Edit, Controls and View, and the system's own items beside them, Hide and
// Quit in the application menu and a Window menu. Shortcuts stay with the window for the
// app's own items: a menu that took them would take the text fields' Command Z, which the
// window gives them first. The system's items have theirs, which the system handles.
@(private)
make_native_menu :: proc(ctx: ^ui.Ui, app: ^App, event_type: u32) -> ^NS.Menu {
	n := &app.native_menu
	action := NS.MenuItem.registerActionCallback("colophonMenuAction", on_menu_action)
	bar := NS.Menu.alloc()->init()
	menus := app_menus(ctx, app)
	for menu, m in menus {
		submenu := NS.Menu.alloc()->initWithTitle(string_of(menu.title))
		// The app says what can run, not the system's validation of the action.
		submenu->setAutoenablesItems(false)
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
			submenu->addItem(NS.MenuItem.separatorItem())
			submenu->addItem(system_item(ui.fill(ui.tr("Hide {}"), APP_NAME), "hide:", "h"))
			submenu->addItem(NS.MenuItem.separatorItem())
			submenu->addItem(system_item(ui.fill(ui.tr("Quit {}"), APP_NAME), "terminate:", "q"))
		}
		holder := NS.MenuItem.alloc()->init()
		holder->setSubmenu(submenu)
		bar->addItem(holder)
		append(&n.items, items)
	}
	bar->addItem(window_menu())
	return bar
}

// An item the system runs itself, on the window or the application, with its shortcut.
@(private = "file")
system_item :: proc(title, selector, key: string) -> ^NS.MenuItem {
	item := NS.MenuItem.alloc()->initWithTitle(
		string_of(title),
		NS.sel_registerName(strings.clone_to_cstring(selector, context.temp_allocator)),
		string_of(key),
	)
	item->setKeyEquivalentModifierMask({.Command})
	return item
}

// The standard Window menu, which SDL's own bar had and the app's replaces: Minimize,
// Zoom and Close, run by the system on the key window.
@(private = "file")
window_menu :: proc() -> ^NS.MenuItem {
	submenu := NS.Menu.alloc()->initWithTitle(string_of(ui.tr("Window")))
	submenu->addItem(system_item(ui.tr("Minimize"), "performMiniaturize:", "m"))
	zoom := NS.MenuItem.alloc()->initWithTitle(
		string_of(ui.tr("Zoom")),
		NS.sel_registerName("performZoom:"),
		string_of(""),
	)
	submenu->addItem(zoom)
	submenu->addItem(NS.MenuItem.separatorItem())
	submenu->addItem(system_item(ui.tr("Close"), "performClose:", "w"))
	NS.Application.sharedApplication()->setWindowsMenu(submenu)
	holder := NS.MenuItem.alloc()->init()
	holder->setSubmenu(submenu)
	return holder
}

// Sets the app's menus as the menu bar of macOS, once SDL has made its window.
@(private = "file")
install_native_menu :: proc(ctx: ^ui.Ui, app: ^App, event_type: u32) {
	app.native_menu.installed = true
	NS.Application.sharedApplication()->setMainMenu(make_native_menu(ctx, app, event_type))
}

// Brings the macOS menu bar up to date with the app's menus: made at the first frame of
// a window that has one, then each title and whether it can run follow the app. Does
// nothing without a menu event type, which only a real window has.
sync_native_menu :: proc(ctx: ^ui.Ui, app: ^App) {
	event_type, wanted := app.menu_event_type.?
	if !wanted || app.platform != .Mac do return
	if !app.native_menu.installed do install_native_menu(ctx, app, event_type)
	// The titles AppKit hands back are autoreleased, and a frame is not run in a pool.
	NS.scoped_autoreleasepool()
	menus := app_menus(ctx, app)
	for menu, m in menus {
		if m >= len(app.native_menu.items) do break
		for line, l in menu.lines {
			if l >= len(app.native_menu.items[m]) do break
			item := app.native_menu.items[m][l]
			if NS.String_odinString(item->title()) != line.entry.label {
				title := string_of(line.entry.label)
				item->setTitle(title)
				title->release()
			}
			if item->isEnabled() != line.entry.enabled do item->setEnabled(line.entry.enabled)
		}
	}
}
