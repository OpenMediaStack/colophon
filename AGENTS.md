# Colophon

A native audio tag editor written in Odin. It reads and rewrites the tags of MP3 files (ID3v2 and ID3v1), plays tracks, draws their waveform, and edits whole albums at once. The interface is a dense, fast tool UI, dark and light, drawn entirely by Colophon on top of SDL3, in the spirit of Blick. It also aims to be a workbench for people who implement ID3 in other languages: in developer mode it writes any tag version on demand (ID3v2.2, 2.3, 2.4, ID3v1.0, 1.1) to produce test files. Open source under the MIT license.

**The migration.** Colophon 1.0.0 was written in Rust with Slint; it is on `main`. The branch `odin-migration` rebuilds it in Odin, slice by slice, until it does everything 1.0.0 does: [`docs/odin-migration.md`](docs/odin-migration.md) is the plan, the parity list and the record of what is done. Rust 1.0.0 is the reference for behaviour: when this file or the plan says nothing, do what 1.0.0 does (read its code with `git show origin/main:<path>` or in `~/Code/colophon`), and port its tests as the spec. When the migration is complete, Florent merges `odin-migration` into `main`.

**Scope.** The first versions handle MP3 only. Other formats (FLAC, Ogg, M4A, WAV, AIFF) come in later versions, so the code stays open to them from the start: see [Open to other formats](#open-to-other-formats).

## How we work

Florent decides, the agents build.

- **Florent** sets the direction, writes or approves the spec of each change, defines what "done" means, and reviews the changes after they are merged.
- **The agents** plan, implement, test and verify. They propose; they never decide product questions alone. When a choice is genuinely Florent's (a behaviour that differs from 1.0.0, a dependency, a file format trade-off, a spike that fails its go or no-go), ask, and record the answer in the plan's [Decisions](docs/odin-migration.md#decisions).
- **Small slices.** One change does one thing and can be reviewed in a few minutes. Each slice of the plan ends on something that runs and is tested. A slice that turns out bigger than planned is cut, and the plan is updated in the same pull request.
- **Plan first** for anything that adds a dependency, changes a file format or departs from the plan: a short note in the pull request description with the files involved, the approach, and how it will be verified, and a question to Florent when the departure is his to decide.
- **One branch and one pull request per change.** Branches start from an up-to-date `origin/odin-migration` and are named after the Conventional Commits type and the change, in English (`feat/engine-listing`, `fix/...`, `docs/...`, `chore/...`, `test/...`, `ci/...`), and are never renamed. Pull requests target `odin-migration`, which only takes squash merges, so the pull request title, a Conventional Commit, becomes the commit on the branch. Nothing is pushed to `odin-migration` or `main` directly.
- **The CI runs on every pull request**: checks, tests, formatting and lint on macOS, Windows and Linux (see [Definition of done](#definition-of-done)).
- **A second agent reviews every pull request.** Once a pull request is open, the agent that opened it has another agent review the diff against this file (correctness, [Rules that are never bent](#rules-that-are-never-bent), parity with 1.0.0, tests, idiomatic Odin, comments). The agent that opened it applies the review comments it agrees with, pushes them to the same pull request, and lists in the description the ones it set aside, with the reason.
- **The agent merges once the CI is green.** After the review, when every check of its pull request passes, the agent that opened it ticks the slice in [`docs/odin-migration.md`](docs/odin-migration.md) (in the same pull request), squash-merges it and deletes its branch; the next slice starts from the updated `origin/odin-migration`. A pull request waiting on a question for Florent is not merged until he answers. Florent reviews the merged changes and asks for fixes, which come as new pull requests. Merging `odin-migration` into `main` and tagging a release stay Florent's call.
- **odid3.** Tags are read and written by [odid3](https://github.com/OpenMediaStack/odid3), Open Media Stack's ID3 library, cloned in `~/Code/openmediastack/odid3`. When Colophon needs something odid3 lacks, or hits a bug in it, and only when a workaround in Colophon would be wrong or costly, open a pull request on odid3 that follows odid3's own `AGENTS.md`, then move Colophon's submodule to the commit or tag that has it. Say in Colophon's pull request which odid3 change it waits for.
- **Florent keeps learning.** When a change relies on a concept that is not obvious (an immediate mode UI's hot and active widgets, a glyph atlas, a lock-free ring buffer, an Objective-C message send from Odin, a min/max waveform pyramid), the summary explains it in two or three sentences with a link to the reference. No lectures, just enough to review with understanding.
- Talk to Florent in French. Everything written in the repository or on GitHub is in English: code, comments, docs, commit messages, pull request titles and descriptions, review comments.
- No em dashes or en dashes anywhere: code, comments, docs, commits, pull requests. Use a comma, a colon, parentheses or a new sentence.

## Code style

Idiomatic Odin, following the [overview](https://odin-lang.org/docs/overview/), the [FAQ](https://odin-lang.org/docs/faq/) and the conventions of Odin's own `core:` library.

- **Names.** Types in `Ada_Case`, procedures and variables in `snake_case`, constants in `SCREAMING_SNAKE_CASE`, enum values in `Ada_Case`, packages in short lowercase names (`engine`, `library`).
- **Public and private.** A package exposes only what other packages need. Every helper is `@(private)` (package) or `@(private = "file")`.
- **Errors are values**: an `Error` enum or union per package, propagated with `or_return`, handled with `switch` or `or_else`. No `panic`, `assert` or `unreachable` that data from a file or the user can reach.
- **Types carry the meaning.** Enums and `bit_set`s rather than boolean flags, `distinct` types for values that must not be mixed up (`Track_Id :: distinct int`, `Millis :: distinct i64`), enumerated arrays where the keys are known (`[Field]string`), `union`s for things that are one of several kinds.
- **Allocators are explicit.** A procedure that allocates takes `allocator := context.allocator`, and its doc comment says what the caller owns and how to free it (`delete` or `destroy`). Free right after acquiring with `defer` when the lifetime is local. `context.temp_allocator` holds per-frame scratch memory only, freed once per frame by the app loop; a package never keeps temp memory beyond the call that made it.
- **No global mutable state.** State lives in structs passed by pointer (`^Engine`, `^Ui`, `^App`), so every procedure can be tested without a window. Read-only tables are `@(rodata)` constants. The only exception is the `userdata` a C callback receives, which is a pointer to such a struct.
- **Small procedures** that do one thing and are easy to test, rather than long ones with flags.
- **Platform code** lives in files suffixed with the platform (`menu_darwin.odin`, `menu_windows.odin`, `menu_linux.odin`), with the same procedures in each, rather than `when ODIN_OS` blocks scattered through the code. A short `when` stays fine for a one-line difference.
- **Comments.** The code reads without comments: clear names, small procedures, types that carry the meaning. A comment, in English, only says what the code cannot (why a workaround exists, a quirk of a format or a platform with its reference), never what the next line does.
- **Doc comments** on every declaration another package uses, for `odin doc`: what the caller must know (ownership, errors, threads), not a restatement of the name.
- **Formatting.** `odinfmt` with the repository's `odinfmt.json`; the CI checks that it changes nothing.

## Odin and UI practices

- **Immediate mode UI.** The interface is redrawn from the application state on every frame that needs it: widgets are procedures that draw and return what happened (`clicked`, `changed`, `committed`), identified by a stable `Widget_Id` built from a name and an index. Hover is resolved from the previous frame, so a widget drawn later (an overlay) takes the mouse from what lies under it. Keyboard focus moves only between frames, and a widget losing the focus never cancels another one's request for it in the same frame.
- **One `Ui` context**, passed by pointer to every widget: input of the frame, hot, active and focused widgets, the draw lists, the theme. Screens are procedures `(ui: ^Ui, app: ^App, rect: Rect)`.
- **Logic in the engine, drawing in the UI.** A screen reads engine state and calls engine commands; it never decides a behaviour. The UI keeps only what is about presentation (scroll offsets, which field has the focus, the text being typed).
- **Text being typed is a pending change.** A field applies its text on Enter, Tab or a click elsewhere, but while it is typed it already counts as unsaved, and saving or quitting applies it first, to the tracks it was started on.
- **One `Theme`** struct whose fields are named like the brief's tokens (`surface_0`, `text_secondary`, `accent_selection`). Widgets read colours and sizes from it, never from a literal.
- **Rendering.** Every shape, glyph and icon samples one alpha atlas tinted by vertex colour, drawn with `SDL_RenderGeometry`; covers are the only other textures. The draw lists are plain data, so tests can inspect them without a window. Rounded rects are anti-aliased with a one pixel feather ring.
- **Frames only when needed.** The loop waits for events; it draws continuously only while something moves (playback, a scan, a caret blink, a transition under 150 ms).
- **Other threads never touch the UI.** Scanning, reading tags, saving, decoding audio and computing waveforms run on worker threads, which hand results back through a channel or a mutex-guarded queue and wake the loop with an SDL user event. Packages below the UI do not know SDL: they take a `wake` callback.
- **Accessibility from the start.** Every widget of our own declares its role, label and actions to the accessibility tree (see the plan's accessibility spike). Tests find widgets through the same labels.
- **Desktop scrolling.** A mouse drag never pans a list, it selects; the wheel, the trackpad and our own scroll bars scroll.

## Definition of done

A change is done when all of this holds, and the summary says which checks ran:

- `./scripts/check.sh` passes: `odin check` on every package with `-vet -strict-style -warnings-as-errors`, and `odinfmt` leaves every file unchanged.
- `./scripts/test.sh` passes: `odin test` on every package with `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`, with new tests for the new behaviour, and no leak or bad free reported.
- UI changes: the app was run, and the pull request shows the result, from the reference captures the change adds or updates (see [Testing](#testing)) or a screenshot taken with the app's `--screenshot` option.
- The CI passes on the pull request: checks and tests on macOS, Windows and Linux, formatting, YAML lint, and the dash check.
- The review agent ran, and its comments are applied or answered in the description.
- Anything not verified is named as such. Never claim a check that did not run.

## Rules that are never bent

- **User files are sacred.** Writing tags never touches audio bytes: it goes through odid3's `write_file`, which writes a temporary file in the same directory, flushes it, then renames it over the original. Tests never write to a real user file: they copy fixtures into a temporary directory.
- **No panic on untrusted input.** Audio files are untrusted. Truncated, corrupted or lying files give an error or a partial result, never a panic. Every length read from a file is checked before slicing, and no bounds check is turned off on data that comes from a file.
- **The UI thread never blocks.** Scanning folders, reading tags, saving, decoding audio and computing waveforms run off the UI thread.
- **Engine first.** Every user action is a command in the engine, which the UI calls. The logic lives in the engine and is tested there, without a window. A behaviour that only exists in the UI is a bug.
- **Business logic is tested.** Every change to `engine`, `library`, `mpa` or `audio` comes with tests for the behaviour it adds or fixes. The UI is tested too whenever it can be, by running frames with scripted input against a `Ui` without a window (see [Testing](#testing)); what cannot be tested is checked by running the app and named as such in the summary.
- **Dependencies point down.** `engine`, `library`, `mpa` and `audio` never import `vendor:sdl3` nor the `ui` package; `engine` imports no `vendor:` package at all.

## Architecture

One Odin package per folder under `src/`, built into one binary.

| Package | Role |
| --- | --- |
| `src/engine` | Application state: the open library, the track model, the views (sources, filter, sort), selection, pending edits, undo and redo, the commands with their stable ids, inspection of the selection, warnings, preferences. Plain data, no `vendor:` import, no I/O except through what `library` gives it. |
| `src/library` | Scanning folders on worker threads, reading tags through odid3 and audio properties through `mpa`, saving pending edits through odid3, reading and writing the preferences file. |
| `src/mpa` | MPEG audio properties: the first valid frame header, the Xing, Info and VBRI headers, duration, bitrate (constant or variable), sample rate, channels. Ported from the prototype. |
| `src/audio` | Decoding and playback with `vendor:miniaudio`, the min/max waveform pyramid. |
| `src/ui` | The toolkit: the `Ui` context, input, layout helpers, the renderer (atlas, shapes, text, icons) and its SDL3 backend, the theme, the widgets, the table, menus, dialogs, toasts, translations. |
| `src/platform` | What differs by platform: native menus, accessibility, the preferences folder, the system language, opening a file's folder. |
| `src/app` | The `main` package: the window, the event loop, the screens, and the wiring of the UI to the engine and to the workers. |
| `libs/odid3` | odid3, a git submodule pinned to a tag, imported by its relative path (`import id3 "../../libs/odid3"`). |

Add a package only when a real boundary appears, never upfront. Assets live in `assets/` (fonts, icons, the app icon) and are embedded with `#load`; translations in `translations/`.

Throwaway experiments and spikes live in `spikes/`, ignored locally through `.git/info/exclude`, never committed; what a spike teaches goes into the plan's [Decisions](docs/odin-migration.md#decisions).

## Open to other formats

Each container has its own tag system, so ID3 is not the general case:

| Format | Tags in its spec | ID3 |
| --- | --- | --- |
| MP3 | None: MPEG defines no metadata | ID3v2 at the start, ID3v1 in the last 128 bytes, sometimes APEv2 at the end. The norm. |
| FLAC, Ogg | Vorbis comments (free `KEY=value` UTF-8 pairs, repeatable keys); FLAC pictures in a `PICTURE` block, Ogg ones in base64 | A leading ID3v2 in FLAC is non-standard, read only |
| M4A | iTunes `ilst` atoms (`©nam`, `©ART`, `trkn`, `covr`…) | No |
| WAV | RIFF `INFO` chunk | De facto `id3 ` chunk |
| AIFF | Text chunks (`NAME`, `AUTH`, `ANNO`) | De facto `ID3 ` chunk |

Rules that keep the door open while v1 ships MP3 only:

- The engine and the UI speak a generic track model (title, artist, album, track and total, disc, year, genre, comment, cover). Nothing outside `library` names an ID3 frame or imports odid3.
- Format-specific details (tag versions, the developer mode's "Tag format" section, raw frames) hang off the generic model as an optional per-format extension, a `union` of per-format structs, never as fields of the generic model.
- The scanner accepts a list of extensions; v1 lists `.mp3` only.
- Fields do not map one to one (`TRCK` = `3/12` against `TRACKNUMBER` and `TRACKTOTAL`, dates, multiple artists). When a later version adds a format, a conversion that loses information is flagged in the inspector, never silent.
- Other formats will come from Open Media Stack libraries like odid3, one per tag system, and their decoding from `vendor:miniaudio` (MP3, FLAC, WAV, Vorbis) or a decoder still to choose for AAC.

## Stack

- **Odin** `dev-2026-10`, the version the CI installs with `laytan/setup-odin`. Change it in the CI and in this file together.
- **SDL3** 3.4 (`vendor:sdl3`): window, input, text input and IME, clipboard, drag and drop, file dialogs (the desktop portal on Linux), the system theme, and the 2D renderer (Metal on macOS, Direct3D on Windows, OpenGL or Vulkan on Linux). Linked dynamically and shipped next to the binary.
- **odid3** for ID3 tags, as a git submodule in `libs/odid3`.
- `vendor:miniaudio` for decoding and playback, `vendor:fontstash` with `vendor:stb/truetype` for text, `vendor:stb/image` for covers. Whatever the spikes add (text shaping, accessibility) is recorded in the plan's decisions.
- Nothing else without Florent's agreement. Say in the plan why a dependency is needed, and check its license: the About dialog lists every third-party component and its license.

## Testing

- **Where tests live.** A private detail is tested in a `<file>_test.odin` beside the code, in the same package (Odin compiles `_test.odin` files only for `odin test`). Behaviour seen from outside a package is tested in its `tests/` folder, a separate package that uses only the public API. Helpers shared by several test files go in a `helpers_test.odin`.
- **Fixtures** are generated by `testdata/make.sh` with ffmpeg plus hand-made byte files for edge cases, from generated silence or a sine, never third-party audio. The script documents what each file holds. The files are committed with ffprobe's output for each one (`testdata/ffprobe/`), so reading them needs no ffmpeg. Tag reading and writing themselves are odid3's to test; Colophon tests what it does with them.
- **Parity:** the audio properties `mpa` reads match `ffprobe -show_format -show_streams` on the fixtures, within the duration and bitrate tolerances its tests explain.
- **Round trips:** saving through the engine and the library, then reading back, gives the same fields, and a hash of the audio bytes is unchanged.
- **Robustness:** a corpus of truncated and mutated fixtures, generated in a temporary directory, scans without a single panic.
- **UI without a window.** Tests run frames of the `Ui` with scripted input (mouse moves, clicks, keys, typed text) against the real screens and engine, with the renderer recording draw lists instead of drawing. They find widgets by their accessible label and check what happened in the engine and what was drawn.
- **Reference captures** for the screens and components that matter: the app renders one frame without a window (SDL's `dummy` video driver and the software renderer, so pixels do not depend on the GPU), and the test compares it with a stored PNG in `tests/references/`, within a small tolerance. Fonts are embedded so a capture does not depend on the machine. `UPDATE_REFERENCES=1` writes them again after an intended change.

## Design

[`docs/design/brief.md`](docs/design/brief.md) is the reference, with the mockup screens in [`docs/design/`](docs/design/README.md): one visual identity on every platform, small platform adaptations (window controls, menus, shortcuts, dialog button order, file dialogs), dense pro-tool layout, tokens, components and their states. The folder is kept out of git (`.git/info/exclude`): read it in `~/Code/colophon/docs/design`, or through the symbolic link a worktree may have.

- The brief's "Implementation" column names the Rust stack. The Odin equivalents are in [Stack](#stack) and in the plan.
- Do not invent other colours, sizes or radii: add a token to the brief first, with Florent.
- The screenshots of Colophon 1.0.0 (`docs/assets/`) and its reference captures (`git show origin/main:crates/ui-slint/tests/references/<name>.png`) show what the app looks like today. The Odin version matches them.

## Translations

Colophon is translatable from the first screen. v1 ships English and French.

- Every user-facing text is written in English in the code through `tr("...")`, plurals through `tr_n("{n} track", "{n} tracks", count)`.
- Translations are the gettext `.po` files of `translations/`, the French one carried over from 1.0.0. They are embedded with `#load` and parsed at startup. `scripts/extract-strings.sh` lists the strings the code uses into `translations/colophon.pot`, and `msgmerge` updates each `.po`.
- At startup Colophon picks the system language (the exact locale, then the language alone) and falls back to English.
- The engine never returns sentences for the user: it returns typed values and errors, and the UI turns them into translated text. Numbers and dates are formatted for the user's language by Colophon.
- Layouts leave room for longer translations: a column, a button or a label sized for the English text cuts the French one.
