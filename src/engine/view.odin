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

// What plays, and how loud. Playing comes with the playback slice.
Playback :: struct {
	// From 0, silent, to 1, as loud as the file.
	volume: f32,
}

// Nothing plays, at 80 percent.
DEFAULT_PLAYBACK :: Playback {
	volume = 0.8,
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

// From 0, silent, to 100, as loud as the file.
Set_Volume :: struct {
	percent: int,
}

// The window's size, to open it at the next launch.
Resize_Window :: struct {
	size: Window_Size,
}
