package main

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

APP_NAME :: "Colophon"
APP_ID :: "org.openmediastack.colophon"
VERSION :: "2.0.0-dev"

// The brief's surface_0 in the dark theme, until the theme arrives with the renderer.
WINDOW_BACKGROUND :: [4]f32{0x12 / 255.0, 0x12 / 255.0, 0x14 / 255.0, 1}

main :: proc() {
	options, err := parse_options(os.args[1:])
	if err != .None {
		fmt.eprintfln(
			"colophon: %v. Usage: colophon [--size=WIDTHxHEIGHT] [--screenshot=FILE.png]",
			err,
		)
		os.exit(2)
	}
	if !run(options) do os.exit(1)
}

// Opens the window and runs until it closes, or renders one frame for --screenshot.
run :: proc(options: Options) -> bool {
	headless := len(options.screenshot) > 0
	if headless {
		// The dummy video driver with the software renderer: no window shows, and the pixels do
		// not depend on the GPU, so screenshots can be compared across machines.
		if !sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "dummy") do return sdl_failed("SDL_SetHint")
		if !sdl.SetHint(sdl.HINT_RENDER_DRIVER, "software") do return sdl_failed("SDL_SetHint")
	}
	if !sdl.SetAppMetadata(APP_NAME, VERSION, APP_ID) do sdl_failed("SDL_SetAppMetadata")
	if !sdl.Init({.VIDEO, .EVENTS}) do return sdl_failed("SDL_Init")
	defer sdl.Quit()

	window, renderer, ok := open_window(options)
	if !ok do return false
	defer sdl.DestroyWindow(window)
	defer sdl.DestroyRenderer(renderer)

	if headless {
		if !draw_frame(renderer) do return false
		return save_screenshot(renderer, options.screenshot)
	}
	return event_loop(renderer)
}

@(private = "file")
open_window :: proc(options: Options) -> (window: ^sdl.Window, renderer: ^sdl.Renderer, ok: bool) {
	size := options.window_size
	window = sdl.CreateWindow(APP_NAME, size.x, size.y, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil do return nil, nil, sdl_failed("SDL_CreateWindow")
	if !sdl.SetWindowMinimumSize(window, MINIMUM_WINDOW_SIZE.x, MINIMUM_WINDOW_SIZE.y) {
		sdl_failed("SDL_SetWindowMinimumSize")
	}
	renderer = sdl.CreateRenderer(window, nil)
	if renderer == nil {
		sdl.DestroyWindow(window)
		return nil, nil, sdl_failed("SDL_CreateRenderer")
	}
	if !sdl.SetRenderVSync(renderer, 1) do sdl_failed("SDL_SetRenderVSync")
	return window, renderer, true
}

// Waits for events and draws a frame after each batch of them, until the window
// closes (true) or drawing fails (false).
@(private = "file")
event_loop :: proc(renderer: ^sdl.Renderer) -> bool {
	for {
		event: sdl.Event
		if !sdl.WaitEvent(&event) do return sdl_failed("SDL_WaitEvent")
		for {
			if event.type == .QUIT do return true
			if !sdl.PollEvent(&event) do break
		}
		if !draw_frame(renderer) do return false
		if !sdl.RenderPresent(renderer) do return sdl_failed("SDL_RenderPresent")
	}
}

@(private = "file")
draw_frame :: proc(renderer: ^sdl.Renderer) -> bool {
	c := WINDOW_BACKGROUND
	if !sdl.SetRenderDrawColorFloat(renderer, c.r, c.g, c.b, c.a) do return sdl_failed("SDL_SetRenderDrawColorFloat")
	if !sdl.RenderClear(renderer) do return sdl_failed("SDL_RenderClear")
	return true
}

@(private = "file")
save_screenshot :: proc(renderer: ^sdl.Renderer, path: string) -> bool {
	surface := sdl.RenderReadPixels(renderer, nil)
	if surface == nil do return sdl_failed("SDL_RenderReadPixels")
	defer sdl.DestroySurface(surface)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if !sdl.SavePNG(surface, cpath) do return sdl_failed("SDL_SavePNG")
	return true
}

// Reports the last SDL error; returns false so callers can return it.
@(private = "file")
sdl_failed :: proc(what: string) -> bool {
	fmt.eprintfln("colophon: %s failed: %s", what, sdl.GetError())
	return false
}
