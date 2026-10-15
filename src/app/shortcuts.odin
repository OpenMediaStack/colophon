package main

import "../engine"
import ui "../ui"

// The shortcuts of the window, for the keys no widget took: the panels as the Finder
// (Option Command S and I on macOS, Control Alt elsewhere), the filter, undo and redo,
// save, open a folder or files.
shortcuts :: proc(ctx: ^ui.Ui, app: ^App) {
	e := &app.engine
	open := folder_open(app)
	panels := ui.COMMAND + {.Alt}
	if ui.take_key(ctx, .S, panels) && open do execute(app, engine.Toggle_Sidebar{})
	if ui.take_key(ctx, .I, panels) && open do execute(app, engine.Toggle_Inspector{})
	if ui.take_key(ctx, .F, ui.COMMAND) && open do ui.focus_field(ctx, ui.widget_id("Filter"))
	if ui.take_key(ctx, .Z, ui.COMMAND) && engine.can_undo(e) do execute(app, engine.Undo{})
	if ui.take_key(ctx, .Z, ui.COMMAND + {.Shift}) && engine.can_redo(e) do execute(app, engine.Redo{})
	if ui.take_key(ctx, .S, ui.COMMAND) && len(e.edits.pending) > 0 && engine.saving(e) == nil do execute(app, engine.Save{})
	if ui.take_key(ctx, .K, ui.COMMAND) do open_palette(app)
	if ui.take_key(ctx, .O, ui.COMMAND) do open_folder(app)
	if ui.take_key(ctx, .O, ui.COMMAND + {.Shift}) do open_files(app)
}
