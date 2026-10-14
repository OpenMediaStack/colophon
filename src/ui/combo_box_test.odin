package ui

import "core:strings"
import "core:testing"

@(test)
genres_that_start_with_the_text_come_first :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	genres := []string{"Acid Rock", "Rock", "Rock & Roll", "Pop", "Synthwave"}
	expect_list :: proc(t: ^testing.T, got, want: []string, loc := #caller_location) {
		if !testing.expectf(t, len(got) == len(want), "got %v, want %v", got, want, loc = loc) do return
		for s, i in got do testing.expectf(t, s == want[i], "got %v, want %v", got, want, loc = loc)
	}
	expect_list(
		t,
		suggest(genres, "rock", context.temp_allocator),
		{"Rock", "Rock & Roll", "Acid Rock"},
	)
	expect_list(t, suggest(genres, " SYNTH", context.temp_allocator), {"Synthwave"})
	testing.expect_value(t, len(suggest(genres, "", context.temp_allocator)), 5)
	testing.expect_value(t, len(suggest(genres, "jazz", context.temp_allocator)), 0)
}

@(private = "file")
Genre_Form :: struct {
	genre:   strings.Builder,
	commits: int,
	behind:  int,
	track:   [2]strings.Builder,
	// The genres offered, GENRES unless set.
	choices: []string,
	// A toast drawn after the combo box, a popup of its own.
	toast:   bool,
}

@(private = "file")
GENRES := []string{"Acid Rock", "Folk", "Folk-Rock", "Rock", "Synthwave"}

@(private = "file")
genre_frame :: proc(ui: ^Ui, data: rawptr) {
	f := (^Genre_Form)(data)
	result := combo_box(
		ui,
		widget_id("Genre"),
		{10, 10, 200, 28},
		strings.to_string(f.genre),
		"Genre",
		f.choices if f.choices != nil else GENRES,
	)
	if result.committed {
		f.commits += 1
		strings.builder_reset(&f.genre)
		strings.write_string(&f.genre, result.text)
	}
	// A button drawn after the combo, under where its suggestions open.
	if button(ui, widget_id("Behind"), {10, 44, 200, 28}, "Behind") do f.behind += 1
	if f.toast do toast(ui, widget_id("Toast"), {0, 0, 1280, 800}, .Success, "Saved 3 files")
	number, total := number_pair(
		ui,
		widget_id("Track"),
		{10, 120},
		strings.to_string(f.track[0]),
		strings.to_string(f.track[1]),
		{"Track", "Track total"},
		"of",
	)
	for pair_result, i in ([2]Text_Field_Result{number, total}) {
		if !pair_result.committed do continue
		strings.builder_reset(&f.track[i])
		strings.write_string(&f.track[i], pair_result.text)
	}
}

@(private = "file")
genre_harness :: proc(h: ^Harness, f: ^Genre_Form) {
	f.genre = strings.builder_make()
	strings.write_string(&f.genre, "Folk")
	for &b, i in f.track {
		b = strings.builder_make()
		strings.write_string(&b, i == 0 ? "3" : "12")
	}
	harness_init(h, genre_frame, f)
	run_frame(h)
}

@(private = "file")
destroy_genre_form :: proc(h: ^Harness, f: ^Genre_Form) {
	harness_destroy(h)
	strings.builder_destroy(&f.genre)
	for &b in f.track do strings.builder_destroy(&b)
	free_all(context.temp_allocator)
}

@(test)
typing_opens_the_suggestions_and_enter_picks_the_highlighted_one :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .A, COMMAND)
	type_text(&h, "rock")
	testing.expect(t, h.ui.combo.open)
	_, listed := find_widget(&h.ui, "Acid Rock")
	testing.expect(t, listed)
	_, unlisted := find_widget(&h.ui, "Synthwave")
	testing.expect(t, !unlisted)
	press_key(&h, .Down)
	press_key(&h, .Down)
	press_key(&h, .Enter)
	testing.expect_value(t, strings.to_string(f.genre), "Acid Rock")
	testing.expect(t, !h.ui.combo.open)
	// Once: the field losing the focus after the pick commits nothing more.
	run_frame(&h)
	testing.expect_value(t, f.commits, 1)
}

@(test)
a_click_picks_a_suggestion_and_what_lies_under_it_gets_nothing :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Show suggestions")
	testing.expect(t, h.ui.combo.open)
	run_frame(&h)
	suggestion, _ := find_widget(&h.ui, "Acid Rock")
	testing.expect_value(t, suggestion.parent, child_id(widget_id("Genre"), "suggestions"))
	testing.expect(t, click(&h, "Acid Rock"))
	testing.expect_value(t, strings.to_string(f.genre), "Acid Rock")
	testing.expect_value(t, f.behind, 0)
	testing.expect(t, !h.ui.combo.open)
	run_frame(&h)
	testing.expect_value(t, f.commits, 1)
}

@(test)
a_toast_drawn_after_the_list_leaves_it_the_mouse :: proc(t: ^testing.T) {
	h: Harness
	f := Genre_Form {
		toast = true,
	}
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .A, COMMAND)
	type_text(&h, "rock")
	run_frame(&h)
	testing.expect(t, click(&h, "Acid Rock"))
	testing.expect_value(t, strings.to_string(f.genre), "Acid Rock")
}

@(test)
up_goes_back_to_the_text_typed_and_a_held_arrow_moves_on :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .A, COMMAND)
	type_text(&h, "rock")
	press_key(&h, .Down)
	append(&h.ui.input.keys, Key_Press{.Down, {}, true, 0})
	run_frame(&h)
	testing.expect_value(t, h.ui.combo.highlighted, 1)
	press_key(&h, .Up)
	press_key(&h, .Up)
	testing.expect_value(t, h.ui.combo.highlighted, -1)
	press_key(&h, .Enter)
	testing.expect_value(t, strings.to_string(f.genre), "rock")
}

@(test)
a_list_that_matches_nothing_leaves_the_keys_to_the_field :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .A, COMMAND)
	type_text(&h, "zzz")
	// Down shows every genre.
	press_key(&h, .Down)
	run_frame(&h)
	_, listed := find_widget(&h.ui, "Synthwave")
	testing.expect(t, listed)
	type_text(&h, "z")
	press_key(&h, .Escape)
	testing.expect_value(t, h.ui.focus, 0)
}

@(test)
the_button_shows_every_choice_whatever_was_typed :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .A, COMMAND)
	type_text(&h, "rock")
	click(&h, "Show suggestions")
	run_frame(&h)
	_, listed := find_widget(&h.ui, "Synthwave")
	testing.expect(t, listed && h.ui.combo.open)
}

@(test)
the_wheel_scrolls_the_list_freely :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	f.choices = {
		"Acid Jazz",
		"Acid Rock",
		"Ambient",
		"Bass",
		"Blues",
		"Classical",
		"Country",
		"Dance",
		"Disco",
		"Folk",
		"Funk",
		"Grunge",
	}
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .Down)
	press_key(&h, .Down)
	center, _ := widget_center(&h, "Acid Jazz")
	move_mouse(&h, center)
	h.ui.input.wheel = {0, 40}
	run_frame(&h)
	run_frame(&h)
	testing.expect_value(t, h.ui.combo.scroll, 40)
}

@(test)
escape_closes_the_suggestions_then_cancels :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Genre")
	press_key(&h, .Down)
	testing.expect(t, h.ui.combo.open)
	press_key(&h, .Escape)
	testing.expect(t, !h.ui.combo.open)
	testing.expect(t, has_focus(&h.ui, widget_id("Genre")))
	press_key(&h, .Escape)
	testing.expect_value(t, h.ui.focus, 0)
	testing.expect_value(t, f.commits, 0)
}

@(test)
tab_goes_from_the_number_to_its_total :: proc(t: ^testing.T) {
	h: Harness
	f: Genre_Form
	genre_harness(&h, &f)
	defer destroy_genre_form(&h, &f)
	click(&h, "Track")
	press_key(&h, .A, COMMAND)
	type_text(&h, "4")
	press_key(&h, .Tab)
	testing.expect_value(t, strings.to_string(f.track[0]), "4")
	testing.expect(t, has_focus(&h.ui, child_id(widget_id("Track"), "total")))
}

// The combo box closed, open with a suggestion highlighted, and the number pair, in
// both themes.
@(test)
the_combo_box_and_number_pair_match_their_reference :: proc(t: ^testing.T) {
	size := [2]f32{520, 300}
	cap, ok := begin_capture(t, size, 2)
	if !ok do return
	defer end_capture(&cap)
	for kind, i in Theme_Kind {
		area := Rect{f32(i) * size.x / 2, 0, size.x / 2, size.y}
		ui: Ui
		ui_init(&ui, cap.renderer, theme(kind))
		fill_rect(cap.renderer, area, ui.theme.surface_1)
		combo_box(&ui, widget_id("Closed"), {area.x + 16, 16, 220, 28}, "Folk", "Closed", GENRES)
		number_pair(
			&ui,
			widget_id("Track"),
			{area.x + 16, 56},
			"3",
			"12",
			{"Track", "Track total"},
			"of",
		)
		open := widget_id("Open")
		ui.focus = open
		ui.edit_owner = open
		edit_reset(&ui.edit, "ro", false)
		ui.combo.owner = open
		ui.combo.open = true
		ui.combo.highlighted = 1
		append(&ui.combo.filter, "ro")
		combo_box(&ui, open, {area.x + 16, 96, 220, 28}, "Folk", "Open", GENRES)
		ui_destroy(&ui)
	}
	finish_capture(t, &cap, "combo-box.png")
}
