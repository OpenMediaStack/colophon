#+build !darwin
package main

import ui "../ui"

// What the system's menu bar holds between frames: nothing here, since only macOS has
// one that the app fills.
Native_Menu :: struct {}

// Brings the system's menu bar up to date with the menus of the app: nothing, on a
// platform whose bar is drawn in the window.
sync_native_menu :: proc(ctx: ^ui.Ui, app: ^App) {}
