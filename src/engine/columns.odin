package engine

// A column of the track table that the user may hide. Status, number and title always
// show.
Column :: enum u8 {
	Artist,
	Album,
	Year,
	Genre,
	Time,
	Bitrate,
	Tags,
	File,
	Folder,
}

// The columns the table shows.
Columns :: bit_set[Column]

// The columns of the mockup, the bitrate aside. The bitrate, the tag formats and the
// file's place are there for whoever wants them.
DEFAULT_COLUMNS :: Columns{.Artist, .Album, .Year, .Genre, .Time}

// A column of the track table that the user may move: every one but status and
// number. Title, then the columns of Column in their order.
Table_Column :: enum u8 {
	Title,
	Artist,
	Album,
	Year,
	Genre,
	Time,
	Bitrate,
	Tags,
	File,
	Folder,
}

#assert(len(Table_Column) == len(Column) + 1)
#assert(int(Table_Column.Folder) == int(Column.Folder) + 1)

// The order of the table's columns, each of them once.
Column_Order :: distinct [len(Table_Column)]Table_Column

DEFAULT_COLUMN_ORDER :: Column_Order {
	.Title,
	.Artist,
	.Album,
	.Year,
	.Genre,
	.Time,
	.Bitrate,
	.Tags,
	.File,
	.Folder,
}

// The width of every column once the user has resized one, in logical pixels. The
// status and number columns keep theirs.
Column_Widths :: [Table_Column]int

// Shows or hides a column.
Toggle_Column :: struct {
	column: Column,
}

// The widths the user gave the columns by dragging their edges.
Resize_Columns :: struct {
	widths: Column_Widths,
}

// Shows every column of the mockup and no other, at the widths and in the order it
// has them.
Reset_Columns :: struct {}

// Puts a column just before another, or last without one.
Move_Column :: struct {
	column: Table_Column,
	before: Maybe(Table_Column),
}

// The table column a hideable column is.
table_column :: proc(column: Column) -> Table_Column {
	return Table_Column(int(column) + 1)
}

// An order that starts with these columns, each once; those they leave out follow in
// their default order.
order_starting_with :: proc(columns: []Table_Column) -> (order: Column_Order) {
	placed: bit_set[Table_Column]
	count := 0
	add :: proc(
		order: ^Column_Order,
		placed: ^bit_set[Table_Column],
		count: ^int,
		column: Table_Column,
	) {
		if column in placed^ do return
		placed^ += {column}
		order[count^] = column
		count^ += 1
	}
	for column in columns do add(&order, &placed, &count, column)
	for column in DEFAULT_COLUMN_ORDER do add(&order, &placed, &count, column)
	return
}

// Puts column just before before, or last without one.
@(private)
move_column :: proc(order: ^Column_Order, column: Table_Column, before: Maybe(Table_Column)) {
	if before == column do return
	columns := make([dynamic]Table_Column, 0, len(Table_Column), context.temp_allocator)
	for other in order do if other != column do append(&columns, other)
	place := len(columns)
	if b, ok := before.?; ok {
		for other, i in columns do if other == b do place = i
	}
	inject_at(&columns, place, column)
	order^ = order_starting_with(columns[:])
}
