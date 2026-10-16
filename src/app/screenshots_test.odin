package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import sdl "vendor:sdl3"
import stbiw "vendor:stb/image"

import "../audio"
import "../engine"
import lib "../library"
import ui "../ui"

// The screenshots of the README, written to docs/assets by
//
//   WRITE_SCREENSHOTS=1 odin test src/app -define:ODIN_TEST_NAMES=main.the_readme_screenshots
//
// as 1.0.0's `cargo test -p colophon-ui --test screenshots -- --ignored` did. Without the
// variable the test does nothing, so that the suite never writes into the documentation.
// The window is 1440 by 900 points drawn at twice that, over a library of three albums.

@(private = "file")
DEMO_AUDIO :: #directory + "/../../testdata/cbr_stereo.mp3"

@(private = "file")
DOCS_ASSETS :: #directory + "/../../docs/assets"

@(private = "file")
Demo_Album :: struct {
	artist:  string,
	title:   string,
	year:    int,
	genre:   string,
	colours: [3][3]u8,
	tracks:  []Demo_Track,
}

@(private = "file")
Demo_Track :: struct {
	title:   string,
	seconds: int,
}

@(private = "file", rodata)
DEMO_ALBUMS := [?]Demo_Album {
	{
		"Cassette Bloom",
		"Analog Hearts",
		2021,
		"Synthpop",
		{{0x2E, 0x10, 0x4F}, {0xD9, 0x46, 0x8A}, {0xF8, 0xC8, 0x6B}},
		{
			{"Neon Weather", 216},
			{"Rewind", 192},
			{"Analog Hearts", 254},
			{"Static Bloom", 229},
			{"Night Drive", 292},
			{"Afterglow", 238},
		},
	},
	{
		"Juniper Vale",
		"Field Notes",
		2016,
		"Folk",
		{{0x16, 0x3B, 0x2E}, {0x6F, 0xA2, 0x7C}, {0xEE, 0xE6, 0xCF}},
		{
			{"Morning Chorus", 178},
			{"Riverstones", 224},
			{"Field Notes", 250},
			{"Hollow Oak", 207},
			{"Wintering", 312},
		},
	},
	{
		"Marlowe Kite",
		"Small Hours",
		2019,
		"Indie Pop",
		{{0x10, 0x1A, 0x33}, {0x2F, 0x5D, 0x8C}, {0xEA, 0xB3, 0x08}},
		{
			{"Lanterns at Noon", 222},
			{"Paper Satellites", 245},
			{"The Long Way Down", 198},
			{"Small Hours", 301},
			{"Glasshouse", 235},
			{"Last Ferry Home", 267},
		},
	},
}

// The JPEG of an album's cover: a gradient between its first two colours, with rings of
// the third around a point that each album moves. Free it with delete.
@(private = "file")
demo_cover :: proc(album: Demo_Album, seed: int) -> []u8 {
	SIDE :: 600
	pixels := make([]u8, SIDE * SIDE * 3)
	defer delete(pixels)
	dark, light, accent := album.colours[0], album.colours[1], album.colours[2]
	centre := [2]f32{SIDE * (0.3 + 0.2 * f32(seed % 3)), SIDE * 0.62}
	for y in 0 ..< SIDE {
		for x in 0 ..< SIDE {
			along := f32(x + y) / f32(2 * SIDE)
			pixel: [3]f32
			for k in 0 ..< 3 do pixel[k] = f32(dark[k]) + (f32(light[k]) - f32(dark[k])) * along
			distance := math.sqrt(math.pow(f32(x) - centre.x, 2) + math.pow(f32(y) - centre.y, 2))
			ring := math.mod(distance / 26, 1)
			if distance < 230 && ring < 0.18 {
				fade := 1 - distance / 230
				for k in 0 ..< 3 do pixel[k] += (f32(accent[k]) - pixel[k]) * fade
			}
			if distance < 46 do for k in 0 ..< 3 do pixel[k] = f32(accent[k])
			for k in 0 ..< 3 do pixels[(y * SIDE + x) * 3 + k] = u8(clamp(math.round(pixel[k]), 0, 255))
		}
	}
	Output :: struct {
		data:      [dynamic]u8,
		allocator: runtime.Allocator,
	}
	jpeg := Output {
		allocator = context.allocator,
	}
	jpeg.data.allocator = context.allocator
	stbiw.write_jpg_to_func(proc "c" (written: rawptr, data: rawptr, size: c.int) {
			out := (^Output)(written)
			context = runtime.default_context()
			context.allocator = out.allocator
			append(&out.data, ..([^]u8)(data)[:size])
		}, &jpeg, SIDE, SIDE, 3, raw_data(pixels), 90)
	return jpeg.data[:]
}

// A music folder in home, with a folder per album, its tracks tagged with its cover, as
// long as their lengths say. Returns the folder, and the path of the first track.
@(private = "file")
demo_library :: proc(t: ^testing.T, home: string) -> (music, first: string) {
	whole, read_err := os.read_entire_file(DEMO_AUDIO, context.allocator)
	if !testing.expect(t, read_err == nil) do return
	defer delete(whole)
	// At 128 kbit/s and 44.1 kHz an unpadded frame is 417 bytes: the audio starts after the
	// Info frame, whose count would give the fixture's length, not the repetitions'.
	second := whole[417:]
	music = fmt.aprintf("%s/Music", home)
	for album, seed in DEMO_ALBUMS {
		folder := fmt.tprintf("%s/%s - %s", music, album.artist, album.title)
		testing.expect(t, os.make_directory_all(folder) == nil)
		jpeg := demo_cover(album, seed)
		defer delete(jpeg)
		for track, i in album.tracks {
			path := fmt.tprintf("%s/%02d %s.mp3", folder, i + 1, track.title)
			file, open_err := os.create(path)
			if !testing.expect(t, open_err == nil) do return
			// 128 kbit/s is 16,000 bytes a second.
			repeats := (track.seconds * 16000 + len(second) / 2) / len(second)
			for _ in 0 ..< repeats do _, _ = os.write(file, second)
			os.close(file)
			tags := lib.Tags {
				title = track.title,
				artist = album.artist,
				album_artist = album.artist,
				album = album.title,
				year = album.year,
				track = i + 1,
				track_total = len(album.tracks),
				genre = album.genre,
				cover = lib.Cover{mime = "image/jpeg", data = jpeg},
			}
			written, write_err := lib.write_track(path, tags, {id3v2 = .V2_4})
			lib.destroy_track(&written)
			testing.expect_value(t, write_err, lib.Write_Error.None)
			if first == "" do first = strings.clone(path)
		}
	}
	return
}

// Fake speakers that say the track has played for a given time.
@(private = "file")
Demo_Speakers :: struct {
	position: time.Duration,
}

@(private = "file")
demo_output :: proc(s: ^Demo_Speakers) -> engine.Output {
	return {
		data = s,
		play = proc(data: rawptr, path: string) -> engine.Play_Error {return .None},
		pause = proc(data: rawptr) {},
		resume = proc(data: rawptr) {},
		stop = proc(data: rawptr) {},
		seek = proc(data: rawptr, position: time.Duration) -> engine.Play_Error {return .None},
		position = proc(data: rawptr) -> time.Duration {
			return (^Demo_Speakers)(data).position
		},
		finished = proc(data: rawptr) -> bool {return false},
		set_volume = proc(data: rawptr, volume: f32) {},
	}
}

// A waveform that rises and falls like a song, with some grain, for seconds seconds:
// samples whose loudness follows the swell of 1.0.0's bars.
@(private = "file")
demo_waveform :: proc(seconds: int) -> audio.Waveform {
	RATE :: 2000
	samples := make([]f32, seconds * RATE)
	defer delete(samples)
	grain: u32 = 7
	level: f32
	for i in 0 ..< len(samples) {
		if i % 128 == 0 {
			grain = grain * 1103515245 + 12345
			noise := f32(grain >> 16) / 65535
			place := f32(i) / f32(len(samples))
			swell := 0.55 + 0.3 * math.sin(place * 9) * math.cos(place * 2.2)
			level = clamp(swell + 0.25 * noise, 0.12, 1)
		}
		samples[i] = i % 2 == 0 ? level : -level
	}
	return audio.waveform_from_samples(samples, 1, RATE)
}

// Writes the screen's frame as the PNG at path, drawn at the screen's scale.
@(private = "file")
save_screen :: proc(t: ^testing.T, s: ^Screen, path: string) {
	cap: ui.Capture
	size := [2]f32{s.h.ui.viewport.w, s.h.ui.viewport.h}
	if !testing.expectf(t, ui.capture_init(&cap, size, s.h.scale), "capture: %s", sdl.GetError()) do return
	defer ui.capture_destroy(&cap)
	ui.run_frame(&s.h)
	if !testing.expectf(t, ui.capture_textures(&cap, &s.h), "textures: %s", sdl.GetError()) do return
	if !testing.expectf(t, ui.capture_draw(&cap, &s.h.renderer), "drawing: %s", sdl.GetError()) do return
	saved := sdl.SavePNG(cap.surface, strings.clone_to_cstring(path, context.temp_allocator))
	testing.expectf(t, saved, "SDL_SavePNG %s: %s", path, sdl.GetError())
}

// The window on the demo library in a theme: the fourth track selected and its title
// edited, and the first playing at 38 per cent.
@(private = "file")
screen_on_demo :: proc(
	t: ^testing.T,
	s: ^Screen,
	speakers: ^Demo_Speakers,
	kind: ui.Theme_Kind,
) -> (
	home: string,
) {
	home_err: os.Error
	home, home_err = make_temp_folder()
	testing.expect(t, home_err == nil)
	music, first := demo_library(t, home)
	defer delete(first)
	defer delete(music)
	screen_init(s, {1440, 900}, kind)
	s.app.platform = .Windows
	// The sidebar shows the library as ~/Music.
	delete(s.app.home, s.app.engine.allocator)
	s.app.home = strings.clone(home, s.app.engine.allocator)
	s.app.engine.output = demo_output(speakers)
	open_folder_of(t, s, music)
	wait_until_shown(t, s, "17 tracks")
	testing.expect(t, ui.click(&s.h, "Static Bloom"))
	ui.run_frame(&s.h)
	retype(s, "Title", "Static Bloom (Radio Edit)")
	ui.press_key(&s.h, .Enter)
	ui.run_frame(&s.h)
	// The first of the album Analog Hearts plays.
	neon: engine.Track_Id
	for track, i in s.app.engine.library.tracks {
		if title, has := track.metadata.tags.title.?; has && title == "Neon Weather" do neon = engine.Track_Id(i)
	}
	engine.execute(&s.app.engine, engine.Play{neon})
	duration := s.app.engine.library.tracks[neon].metadata.audio.duration
	speakers.position = duration * 38 / 100
	ui.run_frame(&s.h)
	// The waveform is the song's, whatever the demo's sine, once the reading is done.
	start := time.tick_now()
	for s.app.waveform.reading != nil && time.tick_since(start) < 20 * time.Second {
		engine.poll(&s.app.engine)
		ui.run_frame(&s.h)
		time.sleep(time.Millisecond)
	}
	forget_waveform(&s.app.waveform)
	s.app.waveform.waveform = demo_waveform(int(duration / time.Second))
	ui.run_frame(&s.h)
	ui.run_frame(&s.h)
	return
}

@(test)
the_readme_screenshots :: proc(t: ^testing.T) {
	if os.get_env("WRITE_SCREENSHOTS", context.temp_allocator) == "" do return
	for kind in ui.Theme_Kind {
		s: Screen
		speakers: Demo_Speakers
		home := screen_on_demo(t, &s, &speakers, kind)
		defer remove_folder(home)
		defer screen_destroy(&s)
		s.h.scale = 2
		name := kind == .Dark ? "dark" : "light"
		save_screen(t, &s, fmt.tprintf("%s/screenshot-%s.png", DOCS_ASSETS, name))
	}
}
