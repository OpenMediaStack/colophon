package ui

import "core:strings"
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
	defer free_all(context.temp_allocator)
	c: Catalog
	if !sample_catalog(t, &c) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, catalog_tr(&c, "Close", ""), "Fermer")
	testing.expect_value(t, catalog_tr(&c, "Play", ""), "Lire")
	testing.expect_value(t, catalog_tr(&c, "Play", "Player"), "Lecture")
	testing.expect_value(t, catalog_tr(&c, "Two lines\n", ""), "Deux lignes\n")
	testing.expect_value(t, catalog_tr(&c, "Quote \"x\"", ""), "Guillemet « x »")
	// Missing, fuzzy, obsolete and empty translations give the English.
	testing.expect_value(t, catalog_tr(&c, "Missing", ""), "Missing")
	testing.expect_value(t, catalog_tr(&c, "Save", ""), "Save")
	testing.expect_value(t, catalog_tr(&c, "Old", ""), "Old")
	testing.expect_value(t, catalog_tr(&c, "Untranslated", ""), "Untranslated")
	testing.expect_value(t, catalog_tr(&c, "Close", "Player"), "Close")
}

@(test)
plurals_follow_the_language :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: Catalog
	if !sample_catalog(t, &c) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, c.plural, Plural_Rule.Zero_One_Other)
	testing.expect_value(t, catalog_tr_n(&c, "{n} track", "{n} tracks", 0, ""), "0 piste")
	testing.expect_value(t, catalog_tr_n(&c, "{n} track", "{n} tracks", 1, ""), "1 piste")
	testing.expect_value(t, catalog_tr_n(&c, "{n} track", "{n} tracks", 12, ""), "12 pistes")
	testing.expect_value(t, catalog_tr_n(&c, "{n} file", "{n} files", 2, ""), "2 files")
	// English, without a catalogue.
	testing.expect_value(t, catalog_tr_n(nil, "{n} track", "{n} tracks", 0, ""), "0 tracks")
	testing.expect_value(t, catalog_tr_n(nil, "{n} track", "{n} tracks", 1, ""), "1 track")
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
	// English again before the catalogue goes: the other threads read it meanwhile.
	use_catalog(nil)
	testing.expect_value(t, tr("Sentinel"), "Sentinel")
}

// What gettext's tools write, besides the plain entries: CRLF, a backslash, the
// previous text of a fuzzy entry, no blank line between entries, a form left empty,
// a tab after the keyword, a context with an empty text, an obsolete fuzzy entry.
@(private = "file")
GETTEXT_SAMPLE ::
	"msgid \"\"\r\nmsgstr \"\"\r\n\"Plural-Forms: nplurals=2; plural=(n != 1);\\n\"\r\n\r\n" +
	"msgid \"Back\\\\slash\"\r\nmsgstr \"Anti\\\\slash\"\r\n" +
	"#| msgid \"Shut\"\r\n#, fuzzy\r\nmsgid \"Close\"\r\nmsgstr \"Fermer\"\r\n" +
	"msgid \"Next\"\r\nmsgstr \"Suivant\"\r\nmsgid\t\"Tab\"\r\nmsgstr\t\"Tabulation\"\r\n" +
	"msgid \"{n} file\"\r\nmsgid_plural \"{n} files\"\r\nmsgstr[0] \"\"\r\nmsgstr[1] \"{n} fichiers\"\r\n" +
	"msgctxt \"Empty\"\r\nmsgid \"\"\r\nmsgstr \"Plural-Forms: nplurals=1; plural=0;\\n\"\r\n" +
	"#, fuzzy\r\n#~ msgid \"Old\"\r\n#~ msgstr \"Vieux\"\r\nmsgid \"Live\"\r\nmsgstr \"Vivant\"\r\n"

@(test)
the_parser_takes_what_gettext_writes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: Catalog
	if !testing.expect(t, catalog_init(&c, GETTEXT_SAMPLE)) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, c.plural, Plural_Rule.One_Other)
	testing.expect_value(t, catalog_tr(&c, "Back\\slash"), "Anti\\slash")
	testing.expect_value(t, catalog_tr(&c, "Close"), "Close")
	testing.expect_value(t, catalog_tr(&c, "Next"), "Suivant")
	testing.expect_value(t, catalog_tr(&c, "Tab"), "Tabulation")
	testing.expect_value(t, catalog_tr_n(&c, "{n} file", "{n} files", 2, ""), "2 files")
	testing.expect_value(t, catalog_tr(&c, "Live"), "Vivant")
	testing.expect_value(t, catalog_tr(&c, "Old"), "Old")
}

@(test)
plural_rules_are_read_however_they_are_spelled :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	Case :: struct {
		forms: string,
		rule:  Plural_Rule,
	}
	cases := [?]Case {
		{"nplurals=2; plural=(n > 1);", .Zero_One_Other},
		{"nplurals=2; plural=n > 1 ? 1 : 0;", .Zero_One_Other},
		{"nplurals=2; plural=(n != 1);", .One_Other},
		{"nplurals=1; plural=0;", .Same},
		{"nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : 1);", .One_Other},
	}
	for each in cases {
		c: Catalog
		po := strings.concatenate(
			{
				"msgid \"\"\nmsgstr \"\"\n\"Plural-Forms: ",
				each.forms,
				"\\n\"\n\nmsgid \"a\"\nmsgstr \"b\"\n",
			},
			context.temp_allocator,
		)
		if !testing.expect(t, catalog_init(&c, po)) do continue
		testing.expectf(t, c.plural == each.rule, "%s: %v", each.forms, c.plural)
		catalog_destroy(&c)
	}
}

@(test)
a_count_without_a_place_for_it_still_belongs_to_the_caller :: proc(t: ^testing.T) {
	words := catalog_tr_n(nil, "Track", "Tracks", 2, "", context.allocator)
	testing.expect_value(t, words, "Tracks")
	delete(words)
}

@(test)
the_french_catalogue_of_1_0_0_reads :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	c: Catalog
	if !testing.expect(t, catalog_init(&c, #load("../../translations/fr.po", string))) do return
	defer catalog_destroy(&c)
	testing.expect_value(t, c.plural, Plural_Rule.Zero_One_Other)
	// The words the code uses so far; those of 1.0.0 the code does not use yet are
	// obsolete in the file, until msgmerge brings them back.
	testing.expect_value(t, catalog_tr(&c, "Close", ""), "Fermer")
	testing.expect_value(t, catalog_tr(&c, "Choose columns", ""), "Choisir les colonnes")
	testing.expect_value(t, catalog_tr(&c, "Unreadable", ""), "Illisible")
	testing.expect_value(
		t,
		catalog_tr(&c, "Vertical scroll bar", ""),
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
