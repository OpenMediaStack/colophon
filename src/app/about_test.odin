package main

import "core:strings"
import "core:testing"

import ui "../ui"

// A window in English with nothing open, as 1.0.0's about tests.
@(private = "file")
screen_with_nothing_open :: proc(s: ^Screen, kind := ui.Theme_Kind.Dark) {
	screen_init(s, {1440, 900}, kind)
}

@(test)
about_tells_the_version_and_closes_with_escape :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	show_about(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.about.open)
	testing.expect(t, shows(&s, "Version 1.0.0"))
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.about.open)
}

@(test)
the_palette_opens_about :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	open_palette(&s.app)
	ui.run_frame(&s.h)
	ui.type_text(&s.h, "about")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	testing.expect(t, s.app.about.open)
}

@(test)
about_waits_for_another_dialog :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	open_settings(&s.app)
	show_about(&s.app)
	testing.expect(t, !s.app.about.open)
	s.app.settings_open = false
	s.app.removal = Removal {
		tag = .Id3v1,
	}
	show_about(&s.app)
	testing.expect(t, !s.app.about.open)
	forget_removal(&s.app)
	s.app.departure = .Asking
	show_about(&s.app)
	testing.expect(t, !s.app.about.open)
}

@(private = "file")
notice_index :: proc(t: ^testing.T, name: string) -> int {
	for notice, i in THIRD_PARTY do if notice.name == name do return i
	testing.expectf(t, false, "%s is not in the list", name)
	return 0
}

@(private = "file")
open_licenses :: proc(t: ^testing.T, s: ^Screen) {
	show_about(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "Third-party licenses"))
	ui.run_frame(&s.h)
}

@(test)
the_link_opens_the_source :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	show_about(&s.app)
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "github.com/OpenMediaStack/colophon"))
	testing.expect_value(t, s.answers.opened, "https://github.com/OpenMediaStack/colophon")
}

@(test)
the_licenses_list_what_colophon_ships :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	open_licenses(t, &s)
	testing.expect(t, s.app.about.licenses)
	for notice in THIRD_PARTY {
		_, listed := ui.find_widget(&s.h.ui, notice.name)
		testing.expectf(t, listed, "%s is not listed", notice.name)
		testing.expectf(t, len(notice.text) > 0, "%s has no license text", notice.name)
		testing.expectf(t, notice.source != "", "%s has no source", notice.name)
	}
	testing.expect(t, shows(&s, "Components"))
	// The heading is the first one's: the list is sorted by name.
	testing.expect(t, shows(&s, "Fontstash"))
	testing.expect(t, ui.click(&s.h, "SDL"))
	ui.run_frame(&s.h)
	testing.expect(t, shows(&s, "SDL 3.4"))
	testing.expect_value(t, s.app.about.selected, notice_index(t, "SDL"))
	testing.expect(t, ui.click(&s.h, "Back"))
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.about.licenses)
	testing.expect(t, shows(&s, "Colophon"))
}

@(test)
the_list_is_sorted_by_name_and_every_license_is_known :: proc(t: ^testing.T) {
	for notice, i in THIRD_PARTY[1:] {
		before := THIRD_PARTY[i].name
		testing.expectf(
			t,
			strings.compare(
				strings.to_lower(before, context.temp_allocator),
				strings.to_lower(notice.name, context.temp_allocator),
			) <
			0,
			"%s comes before %s",
			before,
			notice.name,
		)
	}
	odin := THIRD_PARTY[notice_index(t, "Odin")]
	testing.expect_value(t, odin.license, "zlib License")
	testing.expect(t, strings.contains(odin.text, "Ginger Bill"))
	testing.expect(t, strings.contains(odin.text, "3. This notice may not be removed"))
}

@(test)
a_component_s_source_link_opens_its_repository :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	open_licenses(t, &s)
	testing.expect(t, ui.click(&s.h, "Inter"))
	ui.run_frame(&s.h)
	testing.expect(t, ui.click(&s.h, "github.com/rsms/inter"))
	testing.expect_value(t, s.answers.opened, "https://github.com/rsms/inter")
}

@(test)
escape_and_return_close_the_licenses :: proc(t: ^testing.T) {
	for key in ([?]ui.Key{.Escape, .Enter}) {
		s: Screen
		screen_with_nothing_open(&s)
		defer screen_destroy(&s)
		open_licenses(t, &s)
		ui.press_key(&s.h, key)
		ui.run_frame(&s.h)
		testing.expectf(t, !s.app.about.open, "%v did not close the licenses", key)
	}
}

@(test)
the_text_scrolls_and_a_new_component_starts_at_its_top :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	open_licenses(t, &s)
	testing.expect(t, ui.click(&s.h, "Inter"))
	ui.run_frame(&s.h)
	text, found := ui.find_widget(&s.h.ui, THIRD_PARTY[notice_index(t, "Inter")].text)
	if !testing.expect(t, found) do return
	ui.move_mouse(&s.h, ui.rect_center(text.rect))
	s.h.ui.input.wheel = {0, 120}
	ui.run_frame(&s.h)
	testing.expect(t, s.app.about.scroll.offset.y > 0)
	testing.expect(t, ui.click(&s.h, "Lucide"))
	ui.run_frame(&s.h)
	testing.expect_value(t, s.app.about.scroll.offset.y, 0)
	// Back and forth starts at the top too.
	s.app.about.scroll.offset.y = 50
	testing.expect(t, ui.click(&s.h, "Back"))
	ui.run_frame(&s.h)
	testing.expect_value(t, s.app.about.scroll.offset.y, 0)
}

@(test)
reopening_about_shows_the_credits_again :: proc(t: ^testing.T) {
	s: Screen
	screen_with_nothing_open(&s)
	defer screen_destroy(&s)
	open_licenses(t, &s)
	testing.expect(t, ui.click(&s.h, "Inter"))
	ui.press_key(&s.h, .Escape)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.about.open)
	show_about(&s.app)
	ui.run_frame(&s.h)
	testing.expect(t, !s.app.about.licenses)
	testing.expect_value(t, s.app.about.selected, 0)
	testing.expect(t, shows(&s, "Version 1.0.0"))
}

// The credits and the licenses of one component, in both themes.
@(test)
about_matches_its_references :: proc(t: ^testing.T) {
	for kind in ui.Theme_Kind {
		s: Screen
		screen_with_nothing_open(&s, kind)
		defer screen_destroy(&s)
		show_about(&s.app)
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "about-dark.png" : "about-light.png")
		testing.expect(t, ui.click(&s.h, "Third-party licenses"))
		ui.run_frame(&s.h)
		testing.expect(t, ui.click(&s.h, "SDL"))
		ui.move_mouse(&s.h, {0, 0})
		ui.run_frame(&s.h)
		expect_screen(t, &s, kind == .Dark ? "licenses-dark.png" : "licenses-light.png")
	}
}
