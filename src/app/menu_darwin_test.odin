#+build darwin
package main

import "core:testing"

import NS "core:sys/darwin/Foundation"

import ui "../ui"

// A choice's tag holds the event type and the number of the choice, and gives them
// back: the macOS menu's action, which receives nothing else, reads them.
@(test)
a_menu_tag_holds_the_event_type_and_the_choice :: proc(t: ^testing.T) {
	for event_type in ([]u32{32768, 32770, 40000}) {
		for choice in ([]int{0, 1, 99, 301, 599}) {
			menu, line := choice / MENU_CODE, choice % MENU_CODE
			got_type, got_choice := menu_tag_parts(menu_tag(event_type, menu, line))
			testing.expect_value(t, got_type, event_type)
			testing.expect_value(t, got_choice, choice)
		}
	}
}

// The native menu has one submenu per menu of the model, with the model's lines in
// order, each item carrying its choice, and the system's Window menu after them.
@(test)
the_native_menu_follows_the_model :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	NS.scoped_autoreleasepool()
	s: Screen
	screen_init(&s, {1440, 900})
	defer screen_destroy(&s)
	s.app.platform = .Mac
	ui.run_frame(&s.h)
	bar := make_native_menu(&s.h.ui, &s.app, 32770)
	menus := app_menus(&s.h.ui, &s.app)
	testing.expect_value(t, int(bar->numberOfItems()), len(menus) + 1)
	testing.expect_value(t, len(s.app.native_menu.items), len(menus))
	for menu, m in menus {
		testing.expect_value(t, len(s.app.native_menu.items[m]), len(menu.lines))
		for line, l in menu.lines {
			item := s.app.native_menu.items[m][l]
			testing.expect_value(t, NS.String_odinString(item->title()), line.entry.label)
			event_type, choice := menu_tag_parts(item->tag())
			testing.expect_value(t, event_type, 32770)
			testing.expect_value(t, choice, m * MENU_CODE + l)
		}
	}
	window := bar->itemAtIndex(NS.Integer(len(menus)))->submenu()
	testing.expect_value(t, NS.String_odinString(window->title()), "Window")
	testing.expect_value(t, int(window->numberOfItems()), 4)
}
