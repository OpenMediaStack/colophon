#+build darwin
package main

import "core:testing"

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
