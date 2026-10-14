package main

import ui "../ui"

// The catalogues Colophon ships, embedded; English needs none.
@(rodata)
TRANSLATIONS := []ui.Translation{{"fr", #load("../../translations/fr.po", string)}}

// Reads the translation for the language the system prefers into catalog, and makes
// tr read it: once, before the first frame. loaded says whether catalog holds one,
// to free with catalog_destroy.
init_translations :: proc(catalog: ^ui.Catalog) -> (loaded: bool) {
	locales := ui.preferred_locales()
	defer ui.delete_locales(locales)
	translation := ui.choose_translation(TRANSLATIONS, locales).? or_return
	if !ui.catalog_init(catalog, translation.po) do return false
	ui.use_catalog(catalog)
	return true
}
