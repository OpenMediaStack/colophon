package engine

import lib "../library"

// Which panels and columns the user wants to see. The UI may still hide the sidebar
// when the window is too narrow.
View_State :: struct {
	sidebar_visible:   bool,
	inspector_visible: bool,
	columns:           Columns,
	// nil until the user resizes a column: the table then shares its width between them.
	column_widths:     Maybe(Column_Widths),
	column_order:      Column_Order,
	// The inspector chooses the tag versions to write, ID3v2.2 included.
	developer_mode:    bool,
	// The window's size when it last closed, if it did.
	window_size:       Maybe(Window_Size),
}

// Both panels, the columns of the mockup, the table sharing its width.
DEFAULT_VIEW :: View_State {
	sidebar_visible   = true,
	inspector_visible = true,
	columns           = DEFAULT_COLUMNS,
	column_order      = DEFAULT_COLUMN_ORDER,
}

// A window's size, in logical pixels, from 0 to max(u32) as the file holds it.
Window_Size :: struct {
	width, height: int,
}

// Shows or hides the sidebar.
Toggle_Sidebar :: struct {}

// Shows or hides the inspector.
Toggle_Inspector :: struct {}

// Shows the tools for people who write ID3 readers and writers.
Toggle_Developer_Mode :: struct {}

// The versions to write the tracks the user chose none for in.
Set_Write_Policy :: struct {
	policy: lib.Write_Policy,
}

// The window's size, to open it at the next launch.
Resize_Window :: struct {
	size: Window_Size,
}
