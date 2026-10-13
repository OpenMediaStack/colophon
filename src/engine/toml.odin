package engine

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

// A value of a TOML file as preferences.toml reads it: booleans, integers, strings and
// arrays of strings, which its keys hold, tables, and any other value TOML allows,
// which only an unknown key may hold.
@(private)
Toml_Value :: union {
	bool,
	i64,
	string,
	[]string,
	Toml_Table,
	Toml_Other,
}

// Marks a table's name: its keys are its name, a dot and theirs. Inline tables and
// dotted keys are kept the same way.
@(private)
Toml_Table :: struct {}

// A float, a date or a time, an inline table or an array of other values: valid
// TOML that no key of preferences.toml holds.
@(private)
Toml_Other :: struct {}

// The values of a TOML text by key, "table.key" for those of a table. false when the
// text is not TOML, multi-line strings aside, which this reader does not take.
// Allocated with the temp allocator.
@(private)
parse_toml :: proc(text: string) -> (values: map[string]Toml_Value, ok: bool) {
	values = make(map[string]Toml_Value, context.temp_allocator)
	p := Toml_Parser{strings.trim_prefix(text, "\xEF\xBB\xBF"), 0}
	table := ""
	arrays := 0
	// The tables a header named, which another header may not name again.
	headers := make(map[string]struct{}, context.temp_allocator)
	for {
		skip_blank(&p, lines = true)
		if p.at >= len(p.text) do return values, true
		if strings.has_prefix(p.text[p.at:], "[[") {
			// An array of tables, which preferences.toml never holds: its keys go under
			// a name no key of Colophon's has.
			p.at += 2
			skip_blank(&p)
			name := parse_key(&p) or_return
			skip_blank(&p)
			expect(&p, ']') or_return
			expect(&p, ']') or_return
			arrays += 1
			table = fmt.tprintf("[[%s]]%d", name, arrays)
			values[table] = Toml_Table{}
		} else if p.text[p.at] == '[' {
			p.at += 1
			skip_blank(&p)
			table = parse_key(&p) or_return
			skip_blank(&p)
			expect(&p, ']') or_return
			if table in headers do return
			headers[table] = {}
			define_table(&values, table) or_return
		} else {
			parse_entry(&p, table, &values) or_return
		}
		skip_blank(&p)
		if p.at < len(p.text) && p.text[p.at] != '\n' && p.text[p.at] != '\r' do return
	}
}

@(private = "file")
Toml_Parser :: struct {
	text: string,
	at:   int,
}

// Marks key and the tables above it as tables. false when one already holds a value.
@(private = "file")
define_table :: proc(values: ^map[string]Toml_Value, key: string) -> bool {
	for i := 0; i <= len(key); i += 1 {
		if i < len(key) && key[i] != '.' do continue
		if existing, found := values[key[:i]]; found {
			if _, is_table := existing.(Toml_Table); !is_table do return false
		} else {
			values[key[:i]] = Toml_Table{}
		}
	}
	return true
}

// key = value, under table; an inline table's keys go under the key.
@(private = "file")
parse_entry :: proc(p: ^Toml_Parser, table: string, values: ^map[string]Toml_Value) -> bool {
	key := parse_key(p) or_return
	skip_blank(p)
	expect(p, '=') or_return
	skip_blank(p)
	full := key if table == "" else strings.concatenate({table, ".", key}, context.temp_allocator)
	if dot := strings.last_index_byte(full, '.'); dot >= 0 do define_table(values, full[:dot]) or_return
	if full in values do return false
	if p.at < len(p.text) && p.text[p.at] == '{' {
		p.at += 1
		values[full] = Toml_Table{}
		skip_blank(p)
		if expect(p, '}') do return true
		for {
			skip_blank(p)
			parse_entry(p, full, values) or_return
			skip_blank(p)
			if expect(p, '}') do return true
			expect(p, ',') or_return
		}
	}
	values[full] = parse_value(p) or_return
	return true
}

// Skips spaces, tabs and comments, and line ends when lines.
@(private = "file")
skip_blank :: proc(p: ^Toml_Parser, lines := false) {
	for p.at < len(p.text) {
		switch p.text[p.at] {
		case ' ', '\t':
			p.at += 1
		case '\r', '\n':
			if !lines do return
			p.at += 1
		case '#':
			for p.at < len(p.text) && p.text[p.at] != '\n' do p.at += 1
		case:
			return
		}
	}
}

@(private = "file")
expect :: proc(p: ^Toml_Parser, c: u8) -> bool {
	if p.at >= len(p.text) || p.text[p.at] != c do return false
	p.at += 1
	return true
}

// A key, perhaps dotted, each part bare (letters, digits, underscores and dashes) or
// quoted; the parts are joined with dots.
@(private = "file")
parse_key :: proc(p: ^Toml_Parser) -> (key: string, ok: bool) {
	b := strings.builder_make(context.temp_allocator)
	for {
		if p.at < len(p.text) && (p.text[p.at] == '"' || p.text[p.at] == '\'') {
			part := parse_string(p) or_return
			strings.write_string(&b, part)
		} else {
			start := p.at
			for p.at < len(p.text) && is_bare(p.text[p.at]) do p.at += 1
			if p.at == start do return
			strings.write_string(&b, p.text[start:p.at])
		}
		skip_blank(p)
		if !expect(p, '.') do return strings.to_string(b), true
		strings.write_byte(&b, '.')
		skip_blank(p)
	}
}

@(private = "file")
is_bare :: proc(c: u8) -> bool {
	switch c {
	case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '_', '-':
		return true
	}
	return false
}

@(private = "file")
parse_value :: proc(p: ^Toml_Parser) -> (value: Toml_Value, ok: bool) {
	if p.at >= len(p.text) do return
	switch p.text[p.at] {
	case '"', '\'':
		return parse_string(p)
	case '[':
		return parse_array(p)
	case '{':
		// An inline table inside an array.
		p.at += 1
		skip_blank(p)
		if expect(p, '}') do return Toml_Other{}, true
		scratch := make(map[string]Toml_Value, context.temp_allocator)
		for {
			skip_blank(p)
			parse_entry(p, "", &scratch) or_return
			skip_blank(p)
			if expect(p, '}') do return Toml_Other{}, true
			expect(p, ',') or_return
		}
	}
	// A bare token: a boolean, an integer, a float, a date or a time.
	start := p.at
	for p.at < len(p.text) && is_token(p.text[p.at]) do p.at += 1
	// A date and a time may be separated by a space.
	if p.at - start == 10 &&
	   p.at + 1 < len(p.text) &&
	   p.text[p.at] == ' ' &&
	   is_digit(p.text[p.at + 1]) {
		p.at += 1
		for p.at < len(p.text) && is_token(p.text[p.at]) do p.at += 1
	}
	token := p.text[start:p.at]
	switch token {
	case "":
		return
	case "true":
		return true, true
	case "false":
		return false, true
	case "inf", "+inf", "-inf", "nan", "+nan", "-nan":
		return Toml_Other{}, true
	}
	if n, is_integer := parse_integer(token); is_integer do return n, true
	if is_float(token) || is_date_or_time(token) do return Toml_Other{}, true
	return
}

// [+-]digits, then a fraction, an exponent or both, digits perhaps grouped by
// underscores.
@(private = "file")
is_float :: proc(token: string) -> bool {
	s := strings.trim_left(token, "+-")
	if len(s) < len(token) - 1 do return false
	digits :: proc(s: ^string) -> bool {
		n := 0
		for n < len(s) && (is_digit(s[n]) || (s[n] == '_' && n > 0 && is_digit(s[n - 1]))) do n += 1
		ok := n > 0 && s[n - 1] != '_'
		s^ = s[n:]
		return ok
	}
	digits(&s) or_return
	fraction, exponent := false, false
	if strings.has_prefix(s, ".") {
		s = s[1:]
		digits(&s) or_return
		fraction = true
	}
	if len(s) > 0 && (s[0] == 'e' || s[0] == 'E') {
		s = strings.trim_left(s[1:], "+-")
		digits(&s) or_return
		exponent = true
	}
	return len(s) == 0 && (fraction || exponent)
}

// A date (1979-05-27), a time (07:32:00) or both, as TOML writes them: digits, then
// what follows them is left to whoever reads the key, which no key of Colophon's is.
@(private = "file")
is_date_or_time :: proc(token: string) -> bool {
	date := len(token) >= 10 && token[4] == '-' && token[7] == '-'
	time := len(token) >= 8 && token[2] == ':' && token[5] == ':'
	return (date || time) && is_digit(token[0]) && is_digit(token[1])
}

@(private = "file")
is_token :: proc(c: u8) -> bool {
	return is_bare(c) || c == '.' || c == ':' || c == '+'
}

@(private = "file")
is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

// A decimal integer, its digits perhaps grouped by underscores, or a hexadecimal, octal
// or binary one after 0x, 0o or 0b.
@(private = "file")
parse_integer :: proc(token: string) -> (n: i64, ok: bool) {
	s := token
	base := 10
	negative := false
	switch {
	case strings.has_prefix(s, "0x"):
		base, s = 16, s[2:]
	case strings.has_prefix(s, "0o"):
		base, s = 8, s[2:]
	case strings.has_prefix(s, "0b"):
		base, s = 2, s[2:]
	case len(s) > 0 && (s[0] == '+' || s[0] == '-'):
		negative = s[0] == '-'
		s = s[1:]
	}
	if len(s) == 0 || s[0] == '_' || s[len(s) - 1] == '_' do return
	if base == 10 && len(s) > 1 && s[0] == '0' do return // no leading zeros
	previous: u8
	for c in transmute([]u8)s {
		if c == '_' {
			if previous == '_' do return
			previous = c
			continue
		}
		previous = c
		digit: i64
		switch c {
		case '0' ..= '9':
			digit = i64(c - '0')
		case 'a' ..= 'f':
			digit = i64(c - 'a' + 10)
		case 'A' ..= 'F':
			digit = i64(c - 'A' + 10)
		case:
			return
		}
		if digit >= i64(base) do return
		if n > (max(i64) - digit) / i64(base) do return
		n = n * i64(base) + digit
	}
	return negative ? -n : n, true
}

// A basic string, between double quotes and with escapes, or a literal one, between
// single quotes.
@(private = "file")
parse_string :: proc(p: ^Toml_Parser) -> (s: string, ok: bool) {
	quote := p.text[p.at]
	p.at += 1
	if strings.has_prefix(p.text[p.at:], quote == '"' ? "\"\"" : "''") do return // multi-line
	b := strings.builder_make(context.temp_allocator)
	for p.at < len(p.text) {
		c := p.text[p.at]
		p.at += 1
		switch {
		case c == quote:
			return strings.to_string(b), true
		case c == '\n' || c == '\r':
			return
		case c == '\\' && quote == '"':
			escape_string(p, &b) or_return
		case:
			strings.write_byte(&b, c)
		}
	}
	return
}

@(private = "file")
escape_string :: proc(p: ^Toml_Parser, b: ^strings.Builder) -> bool {
	if p.at >= len(p.text) do return false
	c := p.text[p.at]
	p.at += 1
	switch c {
	case 'b':
		strings.write_byte(b, '\b')
	case 't':
		strings.write_byte(b, '\t')
	case 'n':
		strings.write_byte(b, '\n')
	case 'f':
		strings.write_byte(b, '\f')
	case 'r':
		strings.write_byte(b, '\r')
	case 'e':
		strings.write_byte(b, 0x1B)
	case '"', '\\':
		strings.write_byte(b, c)
	case 'x', 'u', 'U':
		length := c == 'x' ? 2 : (c == 'u' ? 4 : 8)
		if p.at + length > len(p.text) do return false
		r: rune
		for h in p.text[p.at:][:length] {
			digit: rune
			switch h {
			case '0' ..= '9':
				digit = h - '0'
			case 'a' ..= 'f':
				digit = h - 'a' + 10
			case 'A' ..= 'F':
				digit = h - 'A' + 10
			case:
				return false
			}
			r = r * 16 + digit
		}
		p.at += length
		if !utf8.valid_rune(r) do return false
		strings.write_rune(b, r)
	case:
		return false
	}
	return true
}

// An array, perhaps over several lines, perhaps with a trailing comma: of strings, or
// of other values, which no key of preferences.toml holds.
@(private = "file")
parse_array :: proc(p: ^Toml_Parser) -> (value: Toml_Value, ok: bool) {
	p.at += 1
	items := make([dynamic]string, context.temp_allocator)
	only_strings := true
	for {
		skip_blank(p, lines = true)
		if expect(p, ']') do break
		item := parse_value(p) or_return
		if s, is_string := item.(string); is_string {
			append(&items, s)
		} else {
			only_strings = false
		}
		skip_blank(p, lines = true)
		if expect(p, ',') do continue
		skip_blank(p, lines = true)
		expect(p, ']') or_return
		break
	}
	if !only_strings do return Toml_Other{}, true
	return items[:], true
}
