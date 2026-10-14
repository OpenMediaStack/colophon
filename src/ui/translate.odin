package ui

import "core:mem/virtual"
import "core:strconv"
import "core:strings"

// The translations of one language, read from a gettext catalogue: by context, then
// by English text, the forms of each translation, one per plural form. Its strings
// live in its arena.
Catalog :: struct {
	arena:    virtual.Arena,
	messages: map[string]map[string][]string,
	plural:   Plural_Rule,
}

// Which plural form a count takes, from the catalogue's Plural-Forms header.
Plural_Rule :: enum u8 {
	// English, German, Spanish: one, then every other count (n != 1).
	One_Other,
	// French, Brazilian Portuguese: zero and one, then the others (n > 1).
	Zero_One_Other,
	// Japanese, Chinese: one form whatever the count (0).
	Same,
}

// A catalogue the app embeds, by language: "fr", or "pt_BR" for a country's own.
Translation :: struct {
	language: string,
	po:       string,
}

// A locale the system prefers: a language, "fr", and its country, "FR", if it says.
Locale :: struct {
	language: string,
	country:  string,
}

// The catalogue tr and tr_n read, nil for English: the one piece of state the package
// keeps outside a struct, so that every text goes through tr("...") alone. The app
// sets it once at startup, before any frame.
@(private = "file")
current: ^Catalog

// Reads a catalogue from the text of a .po file into c, which catalog_destroy frees.
// Fuzzy and obsolete entries are left out, as are messages not translated. ok is
// false when the text holds no translation.
catalog_init :: proc(c: ^Catalog, po: string) -> (ok: bool) {
	if virtual.arena_init_growing(&c.arena) != nil do return false
	c.messages = make(map[string]map[string][]string, virtual.arena_allocator(&c.arena))
	e: Po_Entry
	e.ctx = strings.builder_make(context.temp_allocator)
	e.id = strings.builder_make(context.temp_allocator)
	for &f in e.forms do f = strings.builder_make(context.temp_allocator)
	// The text the quoted lines that follow continue.
	field: ^strings.Builder
	text := po
	for raw in strings.split_lines_iterator(&text) {
		line := strings.trim_space(raw)
		keyword, _, quoted := strings.partition(line, " ")
		switch {
		case len(line) == 0:
			finish_entry(c, &e)
			field = nil
		case line[0] == '#':
			// Comments and flags come before their entry: the one before is done.
			if e.form_count > 0 do finish_entry(c, &e)
			if strings.has_prefix(line, "#,") && strings.contains(line, "fuzzy") do e.fuzzy = true
			// An obsolete entry, #~, is left out.
			field = nil
		case line[0] == '"':
			if field != nil do unquote_into(field, line)
		case keyword == "msgctxt" || keyword == "msgid":
			if e.form_count > 0 do finish_entry(c, &e)
			field = keyword == "msgctxt" ? &e.ctx : &e.id
			e.started = true
			unquote_into(field, quoted)
		case keyword == "msgid_plural":
			// The plural's English text is the code's: only the translated forms count.
			field = nil
		case strings.has_prefix(keyword, "msgstr") && e.form_count < len(e.forms):
			field = &e.forms[e.form_count]
			strings.builder_reset(field)
			e.form_count += 1
			unquote_into(field, quoted)
		case:
			field = nil
		}
	}
	finish_entry(c, &e)
	return len(c.messages) > 0
}

// Frees what catalog_init made.
catalog_destroy :: proc(c: ^Catalog) {
	if current == c do current = nil
	virtual.arena_destroy(&c.arena)
	c^ = {}
}

// Makes tr and tr_n read c from now on; nil for English.
use_catalog :: proc(c: ^Catalog) {
	current = c
}

// The translation of text in the language in use, or text itself. ctx tells the same
// English words apart where they mean different things, as gettext's msgctxt.
tr :: proc(text: string, ctx := "") -> string {
	return translate(current, text, ctx)
}

// The words for a count of something in the language in use, in the form its count
// takes there, with {n} replaced by the count: tr_n("{n} track", "{n} tracks", 3).
// Allocated with allocator.
tr_n :: proc(
	singular, plural: string,
	n: int,
	ctx := "",
	allocator := context.temp_allocator,
) -> string {
	return translate_n(current, singular, plural, n, ctx, allocator)
}

// tr from a catalogue, nil for English.
@(private)
translate :: proc(c: ^Catalog, text: string, ctx: string) -> string {
	if forms, found := lookup(c, text, ctx); found do return forms[0]
	return text
}

// tr_n from a catalogue, nil for English.
@(private)
translate_n :: proc(
	c: ^Catalog,
	singular, plural: string,
	n: int,
	ctx: string,
	allocator := context.temp_allocator,
) -> string {
	template := n == 1 ? singular : plural
	if forms, found := lookup(c, singular, ctx); found {
		form := plural_form(c.plural, n)
		if form < len(forms) do template = forms[form]
	}
	digits: [24]u8
	words, _ := strings.replace_all(
		template,
		"{n}",
		strconv.write_int(digits[:], i64(n), 10),
		allocator,
	)
	return words
}

// template with each {} replaced by the next of args, in order: tr("Could not play
// “{}”") with the name of the track. Allocated with allocator.
fill :: proc(template: string, args: ..string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	rest := template
	for arg in args {
		at := strings.index(rest, "{}")
		if at < 0 do break
		strings.write_string(&b, rest[:at])
		strings.write_string(&b, arg)
		rest = rest[at + 2:]
	}
	strings.write_string(&b, rest)
	return strings.to_string(b)
}

// The translation for the first locale the system prefers that Colophon speaks: the
// locale exactly ("pt_BR"), then its language alone ("pt"). English, which needs no
// translation, gives nil, as does a system no translation suits.
choose_translation :: proc(
	translations: []Translation,
	preferred: []Locale,
) -> Maybe(Translation) {
	for locale in preferred {
		if strings.equal_fold(locale.language, "en") do return nil
		exact := strings.concatenate(
			{locale.language, "_", locale.country},
			context.temp_allocator,
		)
		for t in translations do if locale.country != "" && strings.equal_fold(t.language, exact) do return t
		for t in translations do if strings.equal_fold(t.language, locale.language) do return t
	}
	return nil
}

// One entry of a .po file while it is read: up to four plural forms.
@(private = "file")
Po_Entry :: struct {
	ctx, id:    strings.Builder,
	forms:      [4]strings.Builder,
	form_count: int,
	started:    bool,
	fuzzy:      bool,
}

// Keeps the entry read, if it is translated, every form of it, and not fuzzy, then
// starts the next. The header, the entry of the empty msgid, gives the plural rule.
@(private = "file")
finish_entry :: proc(c: ^Catalog, e: ^Po_Entry) {
	defer {
		strings.builder_reset(&e.ctx)
		strings.builder_reset(&e.id)
		e.form_count = 0
		e.started = false
		e.fuzzy = false
	}
	if !e.started || e.form_count == 0 do return
	id := strings.to_string(e.id)
	if len(id) == 0 {
		c.plural = plural_rule(strings.to_string(e.forms[0]))
		return
	}
	if e.fuzzy do return
	for f in e.forms[:e.form_count] do if strings.builder_len(f) == 0 do return
	allocator := virtual.arena_allocator(&c.arena)
	ctx := strings.to_string(e.ctx)
	if ctx not_in c.messages do c.messages[strings.clone(ctx, allocator)] = make(map[string][]string, allocator)
	forms := make([]string, e.form_count, allocator)
	for f, i in e.forms[:e.form_count] do forms[i] = strings.clone(strings.to_string(f), allocator)
	by_id := &c.messages[ctx]
	by_id[strings.clone(id, allocator)] = forms
}

// The rule of a header's Plural-Forms: the forms of English and French, and of the
// languages with one form; English's for any other.
@(private = "file")
plural_rule :: proc(header: string) -> Plural_Rule {
	for line in strings.split_lines(header, context.temp_allocator) {
		name, _, value := strings.partition(line, ":")
		if !strings.equal_fold(strings.trim_space(name), "Plural-Forms") do continue
		_, _, expression := strings.partition(value, "plural=")
		compact := make([dynamic]u8, context.temp_allocator)
		for b in transmute([]u8)expression do if b != ' ' && b != '(' && b != ')' && b != ';' do append(&compact, b)
		switch string(compact[:]) {
		case "n>1":
			return .Zero_One_Other
		case "0":
			return .Same
		}
	}
	return .One_Other
}

@(private)
plural_form :: proc(rule: Plural_Rule, n: int) -> int {
	switch rule {
	case .One_Other:
		return n != 1 ? 1 : 0
	case .Zero_One_Other:
		return n > 1 ? 1 : 0
	case .Same:
	}
	return 0
}

@(private = "file")
lookup :: proc(c: ^Catalog, text, ctx: string) -> (forms: []string, found: bool) {
	if c == nil do return
	by_id := c.messages[ctx] or_return
	return by_id[text]
}

// Adds a quoted .po string to b, its escapes undone.
@(private = "file")
unquote_into :: proc(b: ^strings.Builder, quoted: string) {
	s := strings.trim_space(quoted)
	if len(s) < 2 || s[0] != '"' || s[len(s) - 1] != '"' do return
	s = s[1:len(s) - 1]
	for i := 0; i < len(s); i += 1 {
		if s[i] != '\\' || i + 1 == len(s) {
			strings.write_byte(b, s[i])
			continue
		}
		i += 1
		switch s[i] {
		case 'n':
			strings.write_byte(b, '\n')
		case 't':
			strings.write_byte(b, '\t')
		case 'r':
			strings.write_byte(b, '\r')
		case:
			strings.write_byte(b, s[i])
		}
	}
}
