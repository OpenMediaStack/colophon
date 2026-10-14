package main

import "../engine"
import ui "../ui"

// The shortcuts of the window, for the keys no widget took: the panels as the Finder
// (Option Command S and I on macOS, Control Alt elsewhere), the filter, undo and redo,
// save, open.
shortcuts :: proc(ctx: ^ui.Ui, app: ^App) {
	e := &app.engine
	open := folder_open(app)
	panels := ui.COMMAND + {.Alt}
	if ui.take_key(ctx, .S, panels) && open do engine.execute(e, engine.Toggle_Sidebar{})
	if ui.take_key(ctx, .I, panels) && open do engine.execute(e, engine.Toggle_Inspector{})
	if ui.take_key(ctx, .F, ui.COMMAND) && open do ui.request_focus(ctx, ui.widget_id("Filter"), by_key = true)
	if ui.take_key(ctx, .Z, ui.COMMAND) && engine.can_undo(e) do engine.execute(e, engine.Undo{})
	if ui.take_key(ctx, .Z, ui.COMMAND + {.Shift}) && engine.can_redo(e) do engine.execute(e, engine.Redo{})
	// Windows and Linux also redo with Control Y.
	if ui.PLATFORM != .Mac && ui.take_key(ctx, .Y, ui.COMMAND) && engine.can_redo(e) do engine.execute(e, engine.Redo{})
	if ui.take_key(ctx, .S, ui.COMMAND) && len(e.edits.pending) > 0 && engine.saving(e) == nil do engine.execute(e, engine.Save{})
	if ui.take_key(ctx, .O, ui.COMMAND) do open_folder(app)
}
