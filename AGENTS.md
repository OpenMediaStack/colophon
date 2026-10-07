# TagForge

A native audio tag editor written in Rust. It reads and rewrites the tags of MP3 files (ID3v2 and ID3v1), plays tracks, draws their waveform and spectrum, and edits whole albums at once. The interface is a dense, fast tool UI, dark and light, built with Slint, in the spirit of Blick. It also aims to be a workbench for people who implement ID3 in other languages: in developer mode it writes any tag version on demand (ID3v2.2, 2.3, 2.4, ID3v1.0, 1.1) to produce test files. Open source under the MIT license.

**Scope.** The first versions handle MP3 only. Other formats (FLAC, Ogg, M4A, WAV, AIFF) come in later versions, so the code stays open to them from the start: see [Open to other formats](#open-to-other-formats).

## How we work

Florent decides, the agents build.

- **Florent** sets the direction, writes or approves the spec of each change, defines what "done" means, and reviews every diff before it lands.
- **The agents** plan, implement, test and verify. They propose; they never decide product questions alone. When a choice is genuinely Florent's (a behaviour, a dependency, a file format trade-off), ask.
- **Small slices.** One change does one thing and can be reviewed in a few minutes. A larger feature is cut into slices first, and the plan is shown before any code.
- **Plan first** for anything that touches more than one crate, adds a dependency, or changes a file format: a short plan with the files involved, the approach, and how it will be verified.
- **Commit only when Florent approves.** Commit messages follow Conventional Commits, in English.
- **Florent keeps learning.** When a change relies on a concept that is not obvious (a wgpu bind group, how Slint re-evaluates a property binding when a value it reads changes, ID3 unsynchronisation, a lock-free ring buffer), the summary explains it in two or three sentences with a link to the reference. No lectures, just enough to review with understanding.
- Talk to Florent in French. Code, comments, docs, commit messages and pull requests (title, description, review comments) are in English.

## Code style

- Idiomatic Rust, following the [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/): errors as `Result` with `?`, iterators rather than index loops, borrowing rather than cloning, `From` and `TryFrom` for conversions, enums rather than boolean flags, newtypes for values that must not be mixed up.
- The code reads without comments: clear names, small functions, types that carry the meaning. A comment, in English, only says what the code cannot (why a workaround exists, a quirk of the ID3 spec with its reference), never what the next line does.

## Slint practices

From Slint's [best practices](https://docs.slint.dev/latest/docs/slint/guide/development/best-practices/) and its language reference, plus what the spike confirmed.

- **Layout of `crates/ui-slint`.** `.slint` files in `ui/`, with `ui/app-window.slint` as the entry point; images in `ui/images/`, fonts in `ui/fonts/`, translations in `translations/`.
- **Logic in Rust, presentation in Slint.** A `.slint` file declares what the UI looks like for a given state; the decisions live in the engine. Prefer bindings, which stay correct when their inputs change, to imperative assignments in callbacks.
- **Properties are a component's interface.** `in` for what the parent sets, `out` for what it reads, `in-out` only when both sides write, and everything else private.
- **Accessibility from the start.** Every component of our own declares `accessible-role`, `accessible-label` and its actions (`accessible-action-default`…). Screen readers need them, and the tests find elements through them.
- **One `global Theme`**, re-exported from `app-window.slint` so Rust can reach it. Components read colours and sizes from `Theme` only.
- **States and animations.** Hover, pressed and focus looks are bindings or `states`, with `animate` kept under 150 ms (see the brief's principles).
- **Long lists.** A `for` placed directly in our own `ListView` (a `Flickable` with `visible-width` and `visible-height`) is virtualised. Rows come from Rust as a `ModelRc`; change a model through its methods (`set_row_data`, `push`…) so that only the affected rows update.
- **Desktop scrolling.** A mouse drag never pans a list (`mouse-drag-pan-enabled: false`), it selects; the wheel, the trackpad and our own scroll bars scroll.
- **Other threads** never touch the UI: they hand results back with `Weak::upgrade_in_event_loop` or `slint::invoke_from_event_loop`.
- **Generated code.** `slint::include_modules!()` goes in its own module with `#![allow(clippy::unwrap_used, clippy::expect_used)]`, because Slint's generated code unwraps internally. For the same reason the workspace denies `unsafe_code` rather than forbidding it: a Slint macro allows it locally.
- **Formatting.** `slint-lsp format -i` formats `.slint` files. The formatter is still young: check its output in the diff.

## Definition of done

A change is done when all of this holds, and the summary says which checks ran:

- `cargo fmt --all --check` passes.
- `cargo clippy --workspace --all-targets -- -D warnings` passes.
- `cargo test --workspace` passes, with new tests for the new behaviour.
- UI changes: the app was run, and the summary includes a screenshot (`screencapture`) or a Slint reference capture of the result (see [Testing](#testing)).
- Anything not verified is named as such. Never claim a check that did not run.

## Rules that are never bent

- **User files are sacred.** Writing tags never touches audio bytes. A write goes to a temporary file in the same directory, is flushed, then renamed over the original. Tests never write to a real user file: they copy fixtures into a temporary directory.
- **No panic on untrusted input.** Audio files are untrusted. Truncated, corrupted or lying files give an error or a partial result, never a panic. No `unwrap` or `expect` on data that comes from a file.
- **The UI thread never blocks.** Scanning folders, reading tags, decoding audio and computing waveforms run off the UI thread and report back through channels.
- **Engine first.** Every user action is a command in the engine. The UI, the CLI and later an MCP server call the same commands. A feature that only exists in the UI is a bug.
- **Business logic is tested.** Every change to `engine`, `tags`, `audio` or `library` comes with tests for the behaviour it adds or fixes. The UI is tested too whenever it can be, with Slint's testing backend (see [Testing](#testing)); what cannot be tested is checked by running the app and named as such in the summary.
- **Dependencies point down.** `engine`, `tags`, `audio` and `library` never depend on `slint`.

## Architecture

A Cargo workspace, in the style of PhotoCraft (`github.com/storytold/photocraft`): a pure-data engine with a thin Slint UI on top.

| Crate | Role |
| --- | --- |
| `crates/tags` | Read and write metadata through `lofty` (https://docs.rs/lofty), which covers every format TagForge targets (MP3, FLAC, WAV, AIFF, M4A, Ogg, APE…), writes ID3v2.3 or 2.4 (`WriteOptions::use_id3v23`) with a chosen padding (`preferred_padding`), writes ID3v1, and gives the audio properties (bitrate, sample rate, duration). TagForge adds validation and safe writing. For the few developer-mode writes `lofty` does not do (ID3v2.2, unsynchronisation, compression, forcing ID3v1.0 rather than 1.1), check first, then use the `id3` crate's `Encoder` behind developer mode only. |
| `crates/audio` | Decoding with `symphonia`, playback with `cpal`, the min/max waveform pyramid, the FFT (`realfft`). |
| `crates/library` | Scanning folders, the track model, caching tag reads. |
| `crates/engine` | Application state: open library, selection, pending edits, undo and redo, the command registry (a stable id and JSON parameters for each command). No UI types. |
| `crates/ui-slint` | The Slint frontend: the `.slint` files (the `global Theme`, TagForge's own components, the panels), compiled by `slint-build` in its `build.rs`, and the Rust bridge that turns engine state into Slint properties and models, and Slint callbacks into engine commands. It reads engine state and issues commands, nothing else. |
| `apps/tagforge` | The desktop app: the Slint application, which wires `ui-slint` to the engine. |
| `apps/tagforge-cli` | Headless use: print and edit tags, batch edits, run any command. Later: an MCP server so agents can drive TagForge. |

Add a crate only when a real boundary appears, never upfront.

Throwaway experiments live in `spikes/`: standalone crates outside the workspace, ignored locally through `.git/info/exclude`, never committed.

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

- The engine and the UI speak a generic track model (title, artist, album, track and total, disc, year, genre, comment, cover). Nothing outside `crates/tags` names an ID3 frame.
- Format-specific details (tag versions, the developer mode's "Tag format" section, raw frames) hang off the generic model as an optional per-format extension, never as fields of the generic model.
- The scanner accepts a list of extensions; v1 lists `.mp3` only.
- Fields do not map one to one (`TRCK` = `3/12` against `TRACKNUMBER` and `TRACKTOTAL`, dates, multiple artists). When a later version adds a format, a conversion that loses information is flagged in the inspector, never silent.
- For WAV, a policy like the ID3v1 one will be needed (ID3 chunk as the main tag, RIFF INFO kept where it exists). Decide it when WAV is planned.

## Stack

- Rust 1.99, pinned in `rust-toolchain.toml` and set as the workspace's `rust-version`; edition 2024. Workspace-wide versions and lints in the root `Cargo.toml`.
- `slint` for the UI (1.18 at the time of writing), with `slint-build` to compile the `.slint` files at build time. TagForge draws its own components rather than using the std-widgets styles (see the design brief).
- **Slint's license.** TagForge's own code is under the MIT license. Slint is used under its Royalty-free License 2.0, which allows that for a desktop application on one condition: show the `AboutSlint` widget in an About dialog reachable from the app's top-level menu, or show the "Made with Slint" badge on the public page where TagForge is downloaded. The About dialog must exist before the first build anyone else downloads. The same license forbids distributing an application that exposes Slint's own APIs, so Slint's debugging MCP server (`slint/mcp`) never ships in a release build.
- `lofty` for tags and audio properties (`id3` only for the developer-mode writes `lofty` lacks), `symphonia` for decoding, `cpal` for output, `realfft` for spectra, `rfd` for native file dialogs.
- Check crates.io for the current version before adding a dependency, and say in the plan why it is needed.

## Testing

- **Fixtures** are generated by `testdata/make.sh` with ffmpeg (`-id3v2_version 3` or `4`, `-write_id3v1 1`) plus hand-made byte files for edge cases. Third-party test files stay out of the repo until their license is checked.
- **Parity:** values read by `tags` match `ffprobe -show_format -show_streams` on the fixtures.
- **Round trips:** write then read gives the same tags, and a hash of the audio bytes is unchanged.
- **Robustness:** a corpus of truncated and mutated fixtures, generated in a temporary directory, runs without a single panic.
- **UI:** Slint's testing backend (`i-slint-backend-testing`) runs the UI without a window. Tests find elements by accessible label (`ElementHandle::find_by_accessible_label`), so every component sets `accessible-role` and `accessible-label`, and drive them through accessibility actions or simulated clicks, with mocked time for animations. Its API is preliminary and does not follow semver: pin it to the exact `slint` version (`=1.18.x`) and update both together. Element lookups need the compiler's debug info, which `build.rs` turns on for debug builds (`CompilerConfiguration::with_debug_info`). Tests select their language (`slint::select_bundled_translation`) so they do not depend on the machine's language.
- **Reference captures:** for the panels that matter, the testing backend renders with Slint's software renderer, `Window::take_snapshot()` returns the pixels, and the test compares them with a stored PNG. Fonts are embedded so a capture does not depend on the machine.

## Design

[`docs/design/brief.md`](docs/design/brief.md) is the reference, and [`docs/design/`](docs/design/README.md) holds the mockup screens: one visual identity on every platform, small platform adaptations (window controls, menus, shortcuts, dialog button order, file dialogs), dense pro-tool layout, draft tokens, components and their states.

- Until a mockup is approved, the tokens in the brief are drafts. Do not invent other colours, sizes or radii: add a token to the brief first.
- Once the main screen exists in the app and Florent approves it, the app becomes the source of truth and the mockup is no longer updated.
- All theme values live in a `global Theme` in `crates/ui-slint`, named like the tokens in the brief. Components read their colours from `Theme`, never from a literal.

## Translations

TagForge is translatable from the first screen. v1 ships English and French.

- Every user-facing text is written in English in the `.slint` files with `@tr("...")`, plurals included (`@tr("{n} track" | "{n} tracks" % count)`).
- Translations are gettext `.po` files in `crates/ui-slint/translations/<lang>/LC_MESSAGES/`, bundled into the binary by `slint-build` (`with_bundled_translations`). `slint-tr-extractor` extracts the strings, `msgmerge` updates each `.po`.
- At startup Slint picks the system language (the exact locale, then the language alone) and falls back to English.
- The engine never returns sentences for the user: it returns typed values and errors, and the UI turns them into translated text. Numbers and dates are formatted for the user's language by TagForge, since `@tr` does not do it.
- Layouts leave room for longer translations: a column, a button or a label sized for the English text cuts the French one.

## Roadmap

Each step ends on something Florent can run. Cut a step into slices before starting it.

1. **Skeleton.**
   - **Slint spike, first, before anything else.** It validates:
     - a smooth 10 000-row table that scrolls horizontally, with the status, number and title columns pinned on the left (two lists with synchronised scrolling);
     - the context menu on the column header (the column chooser);
     - a fake waveform displayed from an image buffer (`SharedPixelBuffer` shown by an `Image`);
     - switching between the dark and the light theme;
     - translations: texts marked with `@tr`, a French `.po` bundled into the binary, the system language picked at startup with English as fallback;
     - a test with Slint's testing backend that finds an element by its accessible label and activates it, and a reference capture of one panel rendered with the software renderer (`Window::take_snapshot()`), compared with a stored PNG.

     If a point blocks, stop and discuss it with Florent before going further.
   - Then the skeleton itself: the workspace, the Slint window with the `global Theme` (dark and light), the English and French translations, and the layout chosen in the design brief in grey boxes, the collapsible sidebar and inspector with their buttons and shortcuts, `tagforge-cli --version`.
2. **Library.** Open a folder with the native dialog, scan MP3 files in the background, a virtualised track list that stays smooth with 10 000 entries and scrolls horizontally when its columns do not fit, with status, number and title pinned on the left.
3. **Read tags.** The `tags` crate, fixtures, ffprobe parity, no panic on the corrupted corpus. The edit panel shows the values, read only, the column chooser (right click on the header), and the Tags column, off by default, which shows the tag formats present in each file (`ID3v2.3, ID3v1.1`).
4. **Edit and save.** Editable fields, pending edits, undo and redo through commands, safe writing, round-trip tests. Writes ID3v2.4 by default. ID3v1 is kept where it exists and rewritten from the new values, with a warning when a value does not fit its 30 Latin-1 characters. Removing an ID3v1 tag always goes through a confirmation dialog.
5. **Tag versions and developer mode.** The developer mode switch, the inspector's "Tag format" section (ID3v2 none, 2.2, 2.3, 2.4; ID3v1 none, 1.0, 1.1), and round-trip tests for every version, checked against ffprobe and against a second reader.
6. **Cover art.** Display, replace by drag and drop or file dialog, extract to a file.
7. **Player.** Play, pause, seek, a playhead that stays in sync over a 6 minute track.
8. **Waveform and spectrum.** The min/max pyramid for instant zoom and scrub, the spectrum, then a multi-band waveform.
9. **Album batch edit.** Edit the fields shared by every track of an album at once.
10. **Polish.** Command palette, keyboard shortcuts, hover transitions, icons, empty and error states.
11. **Advanced developer tools.** Padding size, unsynchronisation, compression, text encoding per frame, and a raw frame view with each frame's ID, offset, size, flags and decoded value. `lofty` covers padding and the text encoding of ID3v2 frames; the rest goes through the `id3` crate or a small reader of our own. Check before planning.

Later versions:

- **Other formats**, all through `lofty`: FLAC and Ogg, M4A, WAV, AIFF. Mostly scanning, the inspector fields each format supports, the conversions that lose information, and fixtures. The Tags column shows `Vorbis`, `MP4` or `RIFF INFO, ID3v2.4`.
- The MCP server in `tagforge-cli`, a web build.

