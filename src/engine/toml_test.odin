package engine

import "core:testing"

@(test)
toml_reads_the_values_of_preferences :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	text := `# Colophon
sidebar = false   # hidden
volume = 1_000
name = "a \"b\" \u00e9"
literal = 'C:\Music'
columns = [
	"artist", # one
	'album',
]

[window]
width = 1440
`
	values, ok := parse_toml(text)
	if !testing.expect(t, ok) do return
	testing.expect_value(t, values["sidebar"].(bool), false)
	testing.expect_value(t, values["volume"].(i64), 1000)
	testing.expect_value(t, values["name"].(string), `a "b" é`)
	testing.expect_value(t, values["literal"].(string), `C:\Music`)
	columns := values["columns"].([]string)
	testing.expect(t, len(columns) == 2 && columns[0] == "artist" && columns[1] == "album")
	_, is_table := values["window"].(Toml_Table)
	testing.expect(t, is_table)
	testing.expect_value(t, values["window.width"].(i64), 1440)
}

@(test)
toml_that_is_not_toml_is_refused :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for text in ([]string{"sidebar = [", "volume = 01", "volume = 1__0", "a = 1.", "a = 12:3", "a = 1\na = 2", "a = 1\na.b = 2", "[window]\n[window]", "window = { width = 1", "a = \"\"\"long\"\"\"", "a = 1 b = 2", "a = \"open", "a = 99999999999999999999"}) {
		_, ok := parse_toml(text)
		testing.expectf(t, !ok, "%q should be refused", text)
	}
}

@(test)
toml_takes_what_1_0_took :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	text :=
		"\xEF\xBB\xBF" +
		`"sidebar" = false
ratio = 1.5
numbers = [1, 2]
when = 2024-01-01
at = 1979-05-27 07:32:00Z
nested = { a = 1 }
lists = [["a"], ["b"]]
escaped = "a\eb\x41"
volume = 0x10
window.width = 1440
window.height = 900

[[recent]]
path = "a"

[[recent]]
path = "b"

[other]
x = 1.5
`
	values, ok := parse_toml(text)
	if !testing.expect(t, ok) do return
	testing.expect_value(t, values["sidebar"].(bool), false)
	testing.expect_value(t, values["volume"].(i64), 16)
	testing.expect_value(t, values["escaped"].(string), "a\x1bbA")
	testing.expect_value(t, values["window.width"].(i64), 1440)
	testing.expect_value(t, values["nested.a"].(i64), 1)
	_, other := values["ratio"].(Toml_Other)
	testing.expect(t, other)
	_, table := values["window"].(Toml_Table)
	testing.expect(t, table)
}
