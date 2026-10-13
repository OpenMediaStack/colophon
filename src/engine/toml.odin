package engine

import "core:strings"
import "core:unicode/utf8"

// A value of the subset of TOML that preferences.toml uses: booleans, integers,
// strings, arrays of strings, and tables of those.
@(private)
Toml_Value :: union {
	bool,
	i64,
	string,
	[]string,
	Toml_Table,
}

// Marks a table's name: its keys are its name, a dot and theirs.
@(private)
Toml_Table :: struct {}

// The values of a TOML text by key, "table.key" for those of a table. false when the
// text is not TOML, or uses what this subset leaves out: floats, dates, inline tables,
// arrays of tables, dotted or quoted keys, multi-line strings. Allocated with the temp
// allocator.
@(private)
parse_toml :: proc(text: string) -> (values: map[string]Toml_Value, ok: bool) {
	values = make(map[string]Toml_Value, context.temp_allocator)
	p := Toml_Parser{text, 0}
	table := ""
	for {
		skip_blank(&p, lines = true)
		if p.at >= len(p.text) do return values, true
		if p.text[p.at] == '[' {
			p.at += 1
			skip_blank(&p)
			table = parse_key(&p) or_return
			skip_blank(&p)
			expect(&p, ']') or_return
			if table in values do return
			values[table] = Toml_Table{}
		} else {
			key := parse_key(&p) or_return
			skip_blank(&p)
			expect(&p, '=') or_return
			skip_blank(&p)
			value := parse_value(&p) or_return
			full :=
				key if table == "" else strings.concatenate({table, ".", key}, context.temp_allocator)
			if full in values do return
			values[full] = value
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

// A bare key: letters, digits, underscores and dashes.
@(private = "file")
parse_key :: proc(p: ^Toml_Parser) -> (key: string, ok: bool) {
	start := p.at
	for p.at < len(p.text) {
		switch p.text[p.at] {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '_', '-':
			p.at += 1
			continue
		}
		break
	}
	return p.text[start:p.at], p.at > start
}

@(private = "file")
parse_value :: proc(p: ^Toml_Parser) -> (value: Toml_Value, ok: bool) {
	if p.at >= len(p.text) do return
	switch p.text[p.at] {
	case '"', '\'':
		return parse_string(p)
	case '[':
		return parse_array(p)
	case 't', 'f':
		for word, b in ([2]string{"false", "true"}) {
			if strings.has_prefix(p.text[p.at:], word) {
				p.at += len(word)
				return b == 1, true
			}
		}
		return
	}
	return parse_integer(p)
}

// A decimal integer, its digits perhaps grouped by underscores.
@(private = "file")
parse_integer :: proc(p: ^Toml_Parser) -> (n: i64, ok: bool) {
	negative := false
	if p.at < len(p.text) && (p.text[p.at] == '+' || p.text[p.at] == '-') {
		negative = p.text[p.at] == '-'
		p.at += 1
	}
	digits := 0
	previous: u8
	for p.at < len(p.text) {
		c := p.text[p.at]
		if c == '_' && previous >= '0' && previous <= '9' {
			previous = c
			p.at += 1
			continue
		}
		if c < '0' || c > '9' do break
		if digits == 1 && n == 0 do return // no leading zeros
		if n > (max(i64) - i64(c - '0')) / 10 do return
		n = n * 10 + i64(c - '0')
		digits += 1
		previous = c
		p.at += 1
	}
	if digits == 0 || previous == '_' do return
	if p.at < len(p.text) {
		switch p.text[p.at] {
		case '.', 'e', 'E', ':', '-', 'x', 'o', 'b':
			return // a float, a date or another base
		}
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
	case '"', '\\':
		strings.write_byte(b, c)
	case 'u', 'U':
		length := c == 'u' ? 4 : 8
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

// An array of strings, perhaps over several lines, perhaps with a trailing comma.
@(private = "file")
parse_array :: proc(p: ^Toml_Parser) -> (array: []string, ok: bool) {
	p.at += 1
	items := make([dynamic]string, context.temp_allocator)
	for {
		skip_blank(p, lines = true)
		if expect(p, ']') do return items[:], true
		if p.at >= len(p.text) || (p.text[p.at] != '"' && p.text[p.at] != '\'') do return
		append(&items, parse_string(p) or_return)
		skip_blank(p, lines = true)
		if expect(p, ',') do continue
		skip_blank(p, lines = true)
		expect(p, ']') or_return
		return items[:], true
	}
}
