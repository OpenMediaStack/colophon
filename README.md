<p align="center">
  <img src="assets/icon/colophon.svg" alt="Colophon" width="160" />
</p>

<h1 align="center">Colophon</h1>

<p align="center">
  A desktop MP3 tag editor for macOS, Windows and Linux.
  <br />
  <a href="https://openmediastack.github.io/colophon/">openmediastack.github.io/colophon</a>
</p>

<p align="center">
  <a href="https://github.com/OpenMediaStack/colophon/actions/workflows/rust.yml"><img src="https://github.com/OpenMediaStack/colophon/actions/workflows/rust.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/rust-1.99-CE422B?logo=rust" alt="Rust 1.99" />
  <img src="https://img.shields.io/badge/slint-1.18-2379F4" alt="Slint 1.18" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
</p>

---

## Overview

Colophon reads and writes the tags of MP3 files: title, artist, album, track and disc numbers,
year, genre, comment and cover art. Open a folder or a few files, browse them by album, artist or
folder, edit one track or a whole album at once, and save when you are ready: nothing touches your
files before that.

It reads and writes ID3v2.2, ID3v2.3, ID3v2.4, ID3v1.0 and ID3v1.1, and reads APE tags, which it
leaves as they are.

<p align="center">
  <img src="docs/assets/screenshot-light.png" alt="Colophon, light theme" width="49%" />
  <img src="docs/assets/screenshot-dark.png" alt="Colophon, dark theme" width="49%" />
</p>

---

## Features

- **Library**: open folders and files, or drop them on the window. The sidebar lists the folders,
  albums and artists, every track, the recently changed ones and the files that could not be read.
- **Table**: sort by any column, filter by title, artist or album, and show, hide, resize and
  reorder the columns.
- **Editing**: in the inspector or right in the table, one track or many at once, where values the
  tracks do not share say so. Number the tracks of an album in one go, select a whole album, undo
  and redo every change.
- **Cover art**: replace it with an image picked or dropped on the window, extract it to a file,
  or remove it.
- **Saving**: changes wait, marked track by track, until you save them, and quitting asks what to
  do with them.
- **Warnings**: a track without a number in a numbered album, an album artist unlike the rest of
  its album, a value an ID3v1 tag cannot hold whole.
- **Tag versions**: write ID3v2.4 or ID3v2.3 by default, and keep, always write or never write
  ID3v1. Developer mode chooses the versions file by file and shows every frame, with the text
  encoding, padding and unsynchronisation of what is saved.
- **Player**: listen to a track before tagging it, and seek in its waveform.
- **Command palette**: every command by name, with <kbd>Ctrl</kbd>+<kbd>K</kbd>
  (<kbd>⌘</kbd>+<kbd>K</kbd> on macOS), and the keyboard shortcuts of each platform.
- **Light and dark themes**, following the system, in **English and French**.

---

## Install

Download the latest version from the
[releases page](https://github.com/OpenMediaStack/colophon/releases/latest):

| Platform | File |
|---|---|
| macOS, Apple silicon and Intel | `Colophon-<version>.dmg` |
| Windows 10 and 11, x64 | `Colophon-<version>-setup.exe` |
| Linux, x86_64 | `Colophon-<version>-x86_64.AppImage` |

**macOS**: open the disk image and drag Colophon to Applications. The app is not signed with an
Apple Developer ID, so the first time macOS says it could not verify Colophon and only offers
**Done** or **Move to Trash**: click **Done**, then either

- go to **System Settings → Privacy & Security**, scroll down to **Security**, click
  **Open Anyway** next to the line about Colophon (it shows for about an hour after the attempt),
  confirm with your password or Touch ID, and open Colophon again;
- or lift the quarantine macOS put on the downloaded app, from the Terminal:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Colophon.app
  ```

Either way, macOS remembers it, and Colophon then opens like any other app.

**Windows**: run the installer. SmartScreen may warn about an unknown publisher: click
**More info**, then **Run anyway**.

**Linux**: make the AppImage executable, then run it:

```bash
chmod +x Colophon-*-x86_64.AppImage
./Colophon-*-x86_64.AppImage
```

Some distributions need FUSE 2 for AppImages (`libfuse2` on Debian and Ubuntu).

---

## Development

### Prerequisites

- Rust 1.99, which [rustup](https://rustup.rs) installs from
  [`rust-toolchain.toml`](rust-toolchain.toml)
- On Linux, the libraries of Slint and ALSA:

  ```bash
  sudo apt-get install libfontconfig-dev libxcb-shape0-dev libxcb-xfixes0-dev libxkbcommon-dev libasound2-dev
  ```

### Run and test

```bash
cargo run -p colophon                                   # Build and start the app
cargo test --workspace                                  # Every test, the interface's captures included
cargo clippy --workspace --all-targets -- -D warnings   # What the CI lints
cargo fmt
```

The interface tests compare the window with the captures of
[`crates/ui-slint/tests/references`](crates/ui-slint/tests/references): after a change of the
interface, `UPDATE_REFERENCES=1 cargo test -p colophon-ui` writes them again. The screenshots
above come from `cargo test -p colophon-ui --test screenshots -- --ignored`.

### Layout

| Folder | What it holds |
|---|---|
| [`apps/colophon`](apps/colophon) | The application: the window, the system's dialogs, and what macOS needs |
| [`crates/ui-slint`](crates/ui-slint) | The interface, in [Slint](https://slint.dev), its French translation, and its bridge to the engine |
| [`crates/engine`](crates/engine) | The application state and every command: selection, edits, undo, sorting, preferences |
| [`crates/library`](crates/library) | Finding the audio files of a folder, reading and saving them |
| [`crates/tags`](crates/tags) | Reading and writing ID3v2, ID3v1 and APE tags |
| [`crates/player`](crates/player) | Playing tracks and drawing their waveform |

### Third-party licenses

The About dialog lists the licenses of every crate Colophon ships, from
[`crates/ui-slint/licenses/third-party.json`](crates/ui-slint/licenses/third-party.json). After a
change of dependencies, [cargo-about](https://github.com/EmbarkStudios/cargo-about) writes it again,
which the CI checks:

```bash
cargo about generate -m apps/colophon/Cargo.toml --frozen about.hbs -o crates/ui-slint/licenses/third-party.json
```

---

## License

MIT. Colophon ships open-source fonts, icons and crates under their own licenses, listed in its
About dialog.
