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

// Title, then the columns of Column in their order.
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

// The hideable column a table column is; false for the title, which always shows.
hideable_column :: proc(column: Table_Column) -> (Column, bool) {
	if column == .Title do return {}, false
	return Column(int(column) - 1), true
}

// An order that starts with these columns, each once; those they leave out follow in
// their default order.
order_starting_with :: proc(columns: []Table_Column) -> (order: Column_Order) {
	placed: bit_set[Table_Column]
	count := 0
	defaults := DEFAULT_COLUMN_ORDER
	for list in ([2][]Table_Column{columns, defaults[:]}) {
		for column in list {
			if column in placed do continue
			placed += {column}
			order[count] = column
			count += 1
		}
	}
	return
}

// Puts column just before before, or last without one.
@(private)
move_column :: proc(order: ^Column_Order, column: Table_Column, before: Maybe(Table_Column)) {
	if before == column do return
	others: [len(Table_Column) - 1]Table_Column
	count := 0
	for other in order {
		if other == column do continue
		others[count] = other
		count += 1
	}
	place := count
	if b, ok := before.?; ok {
		for other, i in others[:count] do if other == b do place = i
	}
	moved: Column_Order
	copy(moved[:place], others[:place])
	moved[place] = column
	copy(moved[place + 1:], others[place:count])
	order^ = moved
}
