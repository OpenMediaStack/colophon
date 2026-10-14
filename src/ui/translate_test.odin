package ui

import "core:testing"

@(private = "file")
SAMPLE :: `msgid ""
msgstr ""
"Language: fr\n"
"Plural-Forms: nplurals=2; plural=(n > 1);\n"

msgid "Close"
msgstr "Fermer"

msgctxt "Player"
msgid "Play"
msgstr "Lecture"

msgid "Play"
msgstr "Lire"

msgid "{n} track"
msgid_plural "{n} tracks"
msgstr[0] "{n} piste"
msgstr[1] "{n} pistes"

#, fuzzy
msgid "Save"
msgstr "Sauver"

#~ msgid "Old"
#~ msgstr "Vieux"

msgid "Untranslated"
msgstr ""

#: src/ui/overlay.odin:12
msgid "Two "
"lines\n"
msgstr "Deux "
"lignes\n"

msgid "Quote \"x\""
msgstr "Guillemet « x »"
`

@(private = "file")
sample_catalog :: proc(t: ^testing.T, c: ^Catalog) -> bool {
	return testing.expect(t, catalog_init(c, SAMPLE))
}

@(test)
a_catalogue_translates_what_it_holds_whole :: proc(t: ^testing.T) {
	c: Catalog
	if !sample_catalog(t, &c) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, translate(&c, "Close", ""), "Fermer")
	testing.expect_value(t, translate(&c, "Play", ""), "Lire")
	testing.expect_value(t, translate(&c, "Play", "Player"), "Lecture")
	testing.expect_value(t, translate(&c, "Two lines\n", ""), "Deux lignes\n")
	testing.expect_value(t, translate(&c, "Quote \"x\"", ""), "Guillemet « x »")
	// Missing, fuzzy, obsolete and empty translations give the English.
	testing.expect_value(t, translate(&c, "Missing", ""), "Missing")
	testing.expect_value(t, translate(&c, "Save", ""), "Save")
	testing.expect_value(t, translate(&c, "Old", ""), "Old")
	testing.expect_value(t, translate(&c, "Untranslated", ""), "Untranslated")
	testing.expect_value(t, translate(&c, "Close", "Player"), "Close")
	free_all(context.temp_allocator)
}

@(test)
plurals_follow_the_language :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: Catalog
	if !sample_catalog(t, &c) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, c.plural, Plural_Rule.Zero_One_Other)
	testing.expect_value(t, translate_n(&c, "{n} track", "{n} tracks", 0, ""), "0 piste")
	testing.expect_value(t, translate_n(&c, "{n} track", "{n} tracks", 1, ""), "1 piste")
	testing.expect_value(t, translate_n(&c, "{n} track", "{n} tracks", 12, ""), "12 pistes")
	testing.expect_value(t, translate_n(&c, "{n} file", "{n} files", 2, ""), "2 files")
	// English, without a catalogue.
	testing.expect_value(t, translate_n(nil, "{n} track", "{n} tracks", 0, ""), "0 tracks")
	testing.expect_value(t, translate_n(nil, "{n} track", "{n} tracks", 1, ""), "1 track")
	testing.expect_value(t, plural_form(.One_Other, 0), 1)
	testing.expect_value(t, plural_form(.Same, 5), 0)
}

@(test)
fill_replaces_each_pair_of_braces_in_order :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, fill("Could not play “{}”", "a.mp3"), "Could not play “a.mp3”")
	testing.expect_value(t, fill("{} of {}", "1", "2"), "1 of 2")
	testing.expect_value(t, fill("{} of {}", "1"), "1 of {}")
	testing.expect_value(t, fill("Plain", "x"), "Plain")
}

@(test)
the_translation_follows_the_locales_the_system_prefers :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	translations := []Translation{{"fr", "a"}, {"pt_BR", "b"}, {"pt", "c"}}
	language :: proc(found: Maybe(Translation)) -> string {
		t, has := found.?
		return has ? t.language : "none"
	}
	testing.expect_value(t, language(choose_translation(translations, {{"pt", "BR"}})), "pt_BR")
	testing.expect_value(t, language(choose_translation(translations, {{"pt", "PT"}})), "pt")
	testing.expect_value(t, language(choose_translation(translations, {{"FR", "ca"}})), "fr")
	// English first: no translation, whatever comes after.
	testing.expect_value(
		t,
		language(choose_translation(translations, {{"en", "US"}, {"fr", "FR"}})),
		"none",
	)
	testing.expect_value(
		t,
		language(choose_translation(translations, {{"de", ""}, {"fr", "FR"}})),
		"fr",
	)
	testing.expect_value(t, language(choose_translation(translations, {})), "none")
}

@(test)
the_catalogue_in_use_serves_tr :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Words no other test looks up, since the catalogue in use is shared.
	c: Catalog
	if !testing.expect(t, catalog_init(&c, "msgid \"Sentinel\"\nmsgstr \"Témoin\"\n")) do return
	defer catalog_destroy(&c)
	use_catalog(&c)
	testing.expect_value(t, tr("Sentinel"), "Témoin")
	use_catalog(nil)
	testing.expect_value(t, tr("Sentinel"), "Sentinel")
	// Destroying the catalogue in use goes back to English.
	use_catalog(&c)
	catalog_destroy(&c)
	testing.expect_value(t, tr("Sentinel"), "Sentinel")
}

@(test)
the_french_catalogue_of_1_0_0_reads_whole :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: Catalog
	if !testing.expect(t, catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, c.plural, Plural_Rule.Zero_One_Other)
	// The words the code uses so far; those of 1.0.0 the code does not use yet are
	// obsolete in the file, until msgmerge brings them back.
	testing.expect_value(t, translate(&c, "Close", ""), "Fermer")
	testing.expect_value(t, translate(&c, "Choose columns", ""), "Choisir les colonnes")
	testing.expect_value(t, translate(&c, "Unreadable", ""), "Illisible")
	testing.expect_value(
		t,
		translate(&c, "Vertical scroll bar", ""),
		"Barre de défilement verticale",
	)
	testing.expect(t, len(c.messages[""]) >= 10)
}

@(test)
a_text_without_translations_is_no_catalogue :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: Catalog
	testing.expect(t, !catalog_init(&c, "# nothing\n"))
	catalog_destroy(&c)
	testing.expect(t, !catalog_init(&c, "msgid \"\"\nmsgstr \"\"\n\"Language: fr\\n\"\n"))
	catalog_destroy(&c)
}
