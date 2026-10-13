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
toml_outside_the_subset_is_refused :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for text in ([]string{"sidebar = [", "volume = 1.5", "volume = 01", "when = 2024-01-01", "a = 1\na = 2", "[window]\n[window]", "window = { width = 1 }", "a.b = 1", "a = \"\"\"long\"\"\"", "a = 1 b = 2", "a = \"open", "a = 99999999999999999999"}) {
		_, ok := parse_toml(text)
		testing.expectf(t, !ok, "%q should be refused", text)
	}
}
