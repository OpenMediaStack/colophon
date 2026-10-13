# The Odin migration

Colophon 1.0.0 (Rust and Slint, on `main`) is rebuilt in Odin on the branch `odin-migration`, one pull request per slice, until it does everything 1.0.0 does. This file is the plan, the parity list, and the record of what is done and decided. How the work runs is in [`AGENTS.md`](../AGENTS.md).

Status: approved by Florent on 2026-10-13; in progress.

## Why

A prototype built in a day (Odin, SDL3, every pixel drawn by the app) matched the design mockups, felt faster than 1.0.0, and weighed 2.4 MB with its fonts. Odin keeps the native tool feel of the brief with a far smaller and simpler stack, and Open Media Stack now has its own ID3 library in Odin, [odid3](https://github.com/OpenMediaStack/odid3).

## Decisions

| Date | Decision |
| --- | --- |
| 2026-10-12 | Rewrite Colophon in Odin with SDL3, drawing its own interface (no OS widgets, no UI library), on the branch `odin-migration`; pull requests target it. Florent merges it into `main` at the end. |
| 2026-10-12 | Tags go through odid3, Open Media Stack's ID3 library, written by agents in `OpenMediaStack/odid3`. Colophon uses it as a git submodule in `libs/odid3`, pinned to `v1.0.0`. A missing feature or a bug of odid3 is fixed by a pull request on odid3 when really needed. |
| 2026-10-13 | Each pull request is reviewed by a second agent; the agent that opened it applies what it agrees with and squash-merges once the CI is green, then starts the next slice from `origin/odin-migration`. |
| 2026-10-13 | The MPEG audio properties (duration, bitrate, sample rate), which odid3 leaves out, live in Colophon's `src/mpa`, ported from the prototype. |
| 2026-10-13 | Colophon keeps reading and writing 1.0.0's `preferences.toml`, in the same folder, so users keep their settings. |
| 2026-10-13 | The French translation of 1.0.0 is kept as a gettext `.po` file, embedded and parsed by Colophon. |

The spikes of [Phase 0](#phase-0-foundations-and-spikes) add their results here.

## Parity with 1.0.0

What 1.0.0 does, from its README and its interface tests (`crates/ui-slint/tests/*.rs` on `main`), each with the slice that brings it. The migration ends when every line is ticked and Florent has checked it in the app.

- [ ] Open folders and files with the native dialog, or by dropping them on the window (29)
- [ ] Scan in the background with progress, unreadable files listed and explained (15, 29, 32)
- [ ] Sidebar: all tracks, recently changed, unreadable files, folders, albums with their covers, artists (31)
- [ ] Table: sort by any column, filter by title, artist or album, show, hide, resize and reorder columns, the Tags column off by default, smooth with 10,000 rows, horizontal scrolling (25, 30)
- [ ] Editing in the inspector or in the table, one track or many, multiple values shown as such (26, 32, 33)
- [ ] Genre suggestions (21, 32)
- [ ] Number the tracks of an album in one go, select a whole album (10, 33)
- [ ] Undo and redo every change (10, 33)
- [ ] Cover art: display, replace by file dialog or drop, extract to a file, remove (36)
- [ ] Saving: changes wait, marked track by track; toasts; write errors; quitting asks what to do (16, 34)
- [ ] Warnings: a track without a number in a numbered album, an album artist unlike the rest of its album, a value an ID3v1 tag cannot hold whole (12, 35)
- [ ] Settings: default ID3v2 version (2.4 or 2.3), ID3v1 policy (keep, always, never), developer mode; removing ID3v1 asks first (38, 39)
- [ ] Developer mode: versions chosen file by file, every frame shown, text encoding, padding and unsynchronisation of what is saved (39)
- [ ] Player: play, pause, seek in the waveform, hidden while idle (42, 43)
- [ ] Command palette with every command, and each platform's keyboard shortcuts (37)
- [ ] Panels: sidebar and inspector toggles and shortcuts, collapse rules of small windows (28, 41)
- [ ] Light and dark themes following the system (28)
- [ ] English and French, picked from the system language (27)
- [ ] About dialog with the licenses of every third-party component (40)
- [ ] Preferences kept between launches: columns and their widths, panels, volume, write policies, window size (13, 46)
- [ ] Native menus and context menus as the brief's platform adaptations say (44)
- [ ] Screen readers: VoiceOver, Narrator, Orca (45, after the accessibility spike)
- [ ] Packages: `.dmg` for Apple silicon and Intel, Windows installer, Linux AppImage, released from a tag (47)

Not in 1.0.0, so not in the migration: the spectrum, the multi-band waveform, other formats, the web build.

## Slices

Each slice is one pull request, in this order unless a slice says it can move. A slice is ticked in the pull request that completes it. Rust file names point at what to port; their tests are the spec.

### Phase 0: foundations and spikes

- [x] **1. `chore: odin skeleton, odid3 and CI`.** The `src/app` package, whose `main` opens the window at 1.0.0's size (1280 by 800, at least 960 by 600), `libs/odid3` at `v1.0.0`, `odinfmt.json` and `ols.json`, `scripts/check.sh`, `scripts/test.sh` and `scripts/build.sh`, an `--screenshot` option that renders one frame without a window (SDL's `dummy` video driver and the software renderer) and saves it. CI workflow `odin.yml` on macOS, Windows and Linux: Odin with `laytan/setup-odin`; SDL3 from Homebrew on macOS, and the same release on Windows (the official DLL, with the import library Odin ships) and Linux (built from source and cached); then check, test, a frame rendered without a window uploaded as an artifact, formatting and the dash check. Building Odin's C vendor libraries comes with the first package that needs them (slice 2). `release.yml` comes back in slice 47. The README's development section. Done when the CI is green on the three systems.
- [ ] **2. `feat(ui): renderer`.** The prototype's drawing layer, restructured: draw lists as plain data, one alpha atlas (fontstash glyphs, icons, a white texel), anti-aliased rounded rects and strokes, gradients, images, clipping, layers, and the SDL3 backend. The Lucide icons rasterized once into committed alpha masks by `scripts/icons.sh`. A reference capture of a test card (shapes, text in the five font styles, icons) on the three systems.
- [ ] **3. Spike: accessibility.** AccessKit's C API bound from Odin, fed by an immediate mode tree; VoiceOver reads and activates a button and edits a field. Narrator and Orca as far as they can be checked. Result and go or no-go in [Decisions](#decisions), for Florent to decide on if it fails.
- [ ] **4. Spike: text.** Shaping with `vendor:kb_text_shape` (Arabic, Hebrew, combining marks), fallback fonts from the system (CoreText, DirectWrite, fontconfig) for CJK and symbols, the IME composition with SDL3's text editing events. Result in [Decisions](#decisions).
- [ ] **5. Spike: menus.** The macOS menu bar with `NSMenu` through Odin's Objective-C support, the Windows menu bar on the SDL window's `HWND`, the drawn Linux menu bar, native context menus. Result in [Decisions](#decisions).

### Phase 1: engine and library, without a window

- [ ] **6. `feat(mpa): MPEG audio properties`.** Ported from the prototype: frame headers, Xing, Info and VBRI, duration with encoder delay, constant or variable bitrate, sample rate, channels, on the region odid3's `Layout.audio` gives. ffprobe parity on `testdata/`.
- [ ] **7. `feat(engine): tracks and library state`.** The generic track model, `Track_Id`, the per-format extension (`union`, ID3 for now), adding and replacing scanned tracks. Port `engine/tests/library.rs`.
- [ ] **8. `feat(engine): listing`.** Sources (all, recently changed, unreadable, folder, album, artist), filter, sort by every column with 1.0.0's tie-breaks. Port `listing.rs` and `tests/listing.rs`, `tests/view.rs`.
- [ ] **9. `feat(engine): selection`.** Single, toggle, range, all, an album, keyboard moves. Port `selection.rs` and its tests.
- [ ] **10. `feat(engine): edits, undo and redo`.** Pending edits per track and field, edits on several tracks, numbering an album, commands with stable ids, undo and redo. Port `edits.rs` and its tests.
- [ ] **11. `feat(engine): inspection`.** Values across the selection, multiple values, file information. Port `inspection.rs` and its tests.
- [ ] **12. `feat(engine): warnings`.** Port `warnings.rs` and its tests.
- [ ] **13. `feat(engine): columns and preferences`.** Visible columns, widths, order, defaults (Tags off, Title always shown), write policies, volume, panels; `preferences.toml` read and written as 1.0.0 does (a small reader and writer for the subset of TOML it uses), what is missing keeping its default. Port `columns.rs`, `preferences.rs` and their tests.
- [ ] **14. `feat(engine): playback state`.** Port `playback.rs` and its tests.
- [ ] **15. `feat(library): scan`.** Folders and files on worker threads, the extension list, progress, cancelling, the `wake` callback; odid3 reads with `skip_picture_data`, `mpa` reads the audio. Port `library/tests/scan.rs`.
- [ ] **16. `feat(library): save`.** Pending edits written through odid3 with the write policies (ID3v2 version, ID3v1 kept, always or never, through `sync_v1`), covers replaced or removed, per-file developer choices, one error per file. Round trips with an audio hash. Port `engine/tests/save.rs`.
- [ ] **17. `test(library): robustness corpus`.** Truncated and mutated fixtures scan without a panic.

### Phase 2: the UI toolkit

- [ ] **18. `feat(ui): context, input and headless tests`.** The `Ui` context, widget ids, hot, active and focus rules, layout helpers, and the harness that runs frames with scripted input and finds widgets by label.
- [ ] **19. `feat(ui): buttons`.** Toolbar buttons, icon and label, primary, secondary, ghost and destructive, every state of the brief's component sheet. Reference captures.
- [ ] **20. `feat(ui): text field`.** Caret, selection by mouse and keys, word moves as each platform does them, clipboard, undo inside the field, double click selects a word and triple click all, placeholder, the states (hover, focus, modified, multiple values, error, disabled), IME composition (after spike 4), typed text as a pending change.
- [ ] **21. `feat(ui): number pair and combo box`.** The track and disc pairs, the genre combo with suggestions.
- [ ] **22. `feat(ui): checkbox and segmented control`.**
- [ ] **23. `feat(ui): scrolling`.** Scroll areas, wheel and trackpad, scroll bars hidden when everything fits, hover and drag states.
- [ ] **24. `feat(ui): overlays`.** Context menus, tooltips, toasts, dialogs with each platform's button order, the scrim.
- [ ] **25. `feat(ui): table`.** Virtualised rows, header states, sorting, resizing and reordering columns by drag, the column chooser (right click and button), horizontal scrolling, row states (hover, selected, focused, modified, error, playing). A benchmark with 10,000 rows.
- [ ] **26. `feat(ui): editing in the table`.** In-place editing with a double click, Enter or F2, Tab across the editable cells.
- [ ] **27. `feat(ui): translations`.** The `.po` parser, `tr` and `tr_n`, the system language through `SDL_GetPreferredLocales`, `scripts/extract-strings.sh`.

### Phase 3: the screens

Each screen matches 1.0.0's reference captures (`crates/ui-slint/tests/references/` on `main`), in both themes, and ports the interface tests named.

- [ ] **28. `feat(app): window and panels`.** Toolbar, sidebar, inspector, status bar, the panel toggles and shortcuts, the collapse rules, the 960 by 600 minimum, the themes. Port `layout.rs`, `panels.rs`, `toolbar.rs`.
- [ ] **29. `feat(app): opening`.** The empty state, the folder and file dialogs, drag and drop with its drop target, the scanning state. Port `library.rs`, `drag_and_drop.rs`.
- [ ] **30. `feat(app): track table`.** Every column, the Tags column, sorting, the filter field. Port `track_table.rs`, `columns.rs`.
- [ ] **31. `feat(app): sidebar`.** Port `sidebar.rs`.
- [ ] **32. `feat(app): inspector`.** Cover, fields, multiple values, the File section, unreadable files explained, genre suggestions. Port `inspector.rs`, `unreadable.rs`, `genres.rs`.
- [ ] **33. `feat(app): editing`.** Inspector and table editing through engine commands, undo and redo, numbering an album, selecting an album. Port `editing.rs`, `table_editing.rs`, `selection.rs`.
- [ ] **34. `feat(app): saving`.** Save buttons, unsaved markers, toasts, write errors, the unsaved changes dialog. Port `saving.rs`, `toasts.rs`, `unsaved_changes.rs`.
- [ ] **35. `feat(app): warnings`.** In the table and the inspector.
- [ ] **36. `feat(app): cover art`.** Port `covers.rs`.
- [ ] **37. `feat(app): command palette and shortcuts`.** Port `palette.rs`.
- [ ] **38. `feat(app): settings`.** Port `settings.rs`, `tag_removal.rs`.
- [ ] **39. `feat(app): developer mode`.** Tag format section, frames, encoding, padding, unsynchronisation, the status bar marker. Port `developer_mode.rs`.
- [ ] **40. `feat(app): about and licenses`.** Port `about.rs`.
- [ ] **41. `feat(app): small windows`.** 1280 by 720 and 960 by 600 as the brief says.

### Phase 4: audio

- [ ] **42. `feat(audio): playback`.** Play, pause, seek, next and previous, volume, a playhead in sync over a 6 minute track, the player hidden while idle. Port `player.rs` and `engine/tests/playback.rs`.
- [ ] **43. `feat(audio): waveform`.** The min/max pyramid computed off the UI thread, drawn at any width at once, scrubbing. Port `player/src/waveform.rs` and its tests.

### Phase 5: the platform

- [ ] **44. `feat(platform): menus`.** As spike 5 decided.
- [ ] **45. `feat(platform): accessibility`.** As spike 3 decided, for every widget.
- [ ] **46. `feat(platform): preferences between launches`.** Window size and the rest of `preferences.toml`, read at start and written on change. Port `preferences.rs` (interface).

### Phase 6: release

- [ ] **47. `build: packages and release`.** The `.dmg` (one binary for Apple silicon and Intel with `lipo`), the Windows installer from `packaging/windows/colophon.iss`, the AppImage, each with SDL3; `release.yml` from a version tag.
- [ ] **48. `docs: readme and site`.** Odin badges, development section, new screenshots.
- [ ] **49. Parity check.** Every line of [Parity with 1.0.0](#parity-with-100) ticked, the app checked by Florent on the three systems, then Florent merges `odin-migration` into `main`.

## Risks

- **Accessibility** has no Odin library: AccessKit's C API is the only path found so far. Spike 3 decides early; if it fails, Florent decides whether to ship without screen readers or to keep looking.
- **SDL3 on Linux** has no package on the CI's Ubuntu image: it is built from source and cached.
- **Pixel captures across systems** can differ slightly even with the software renderer: the comparison has a tolerance, and a capture that differs only on one system is investigated, not regenerated blindly.
- **Text** beyond Latin, Greek and Cyrillic needs shaping and fallback fonts (spike 4); until then such titles may show as boxes.
