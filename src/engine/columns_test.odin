package engine

import "core:testing"

@(test)
a_column_moves_before_another_or_last :: proc(t: ^testing.T) {
	order := DEFAULT_COLUMN_ORDER
	move_column(&order, .Year, Table_Column.Title)
	testing.expect_value(t, order[0], Table_Column.Year)
	testing.expect_value(t, order[1], Table_Column.Title)
	testing.expect_value(t, order[2], Table_Column.Artist)
	move_column(&order, .Title, nil)
	testing.expect_value(t, order[len(order) - 1], Table_Column.Title)
}

@(test)
moving_a_column_before_itself_changes_nothing :: proc(t: ^testing.T) {
	order := DEFAULT_COLUMN_ORDER
	move_column(&order, .Title, Table_Column.Title)
	testing.expect_value(t, order, DEFAULT_COLUMN_ORDER)
}

@(test)
an_order_holds_every_column_once :: proc(t: ^testing.T) {
	order := order_starting_with({.Genre, .Genre})
	testing.expect_value(t, order[0], Table_Column.Genre)
	seen: bit_set[Table_Column]
	for column in order do seen += {column}
	testing.expect_value(t, seen, ~bit_set[Table_Column]{})
}
