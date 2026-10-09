//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::RefCell;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::time::Duration;

use colophon_engine::{Command, Engine, Library, ScanStatus, ViewState};
use slint::{Model, ModelRc, SharedString, Timer, TimerMode, VecModel};

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

pub use generated::{AppWindow, ScanState, Theme, TrackRow};
pub use slint::{ComponentHandle, PlatformError};

/// How often the window takes in what a running scan found: often enough to look live, rarely
/// enough to update the table in batches.
const SCAN_POLL_INTERVAL: Duration = Duration::from_millis(50);

/// Creates the main window and hands its user actions to the engine, which then drives what it shows.
/// `pick_folder` asks the user for a folder, usually through the system's dialog.
pub fn main_window(
    engine: Engine,
    pick_folder: impl Fn() -> Option<PathBuf> + 'static,
) -> Result<AppWindow, PlatformError> {
    let window = AppWindow::new()?;
    let tracks = Rc::new(VecModel::default());
    window.set_tracks(ModelRc::from(Rc::clone(&tracks)));
    let bridge = Rc::new(Bridge {
        engine: RefCell::new(engine),
        window: window.as_weak(),
        tracks,
        scan_timer: Timer::default(),
        pick_folder: Box::new(pick_folder),
    });
    bridge.show();
    window.on_run({
        let bridge = Rc::clone(&bridge);
        move |command| run(&bridge, command)
    });
    Ok(window)
}

struct Bridge {
    engine: RefCell<Engine>,
    window: slint::Weak<AppWindow>,
    tracks: Rc<VecModel<TrackRow>>,
    scan_timer: Timer,
    pick_folder: Box<dyn Fn() -> Option<PathBuf>>,
}

fn run(bridge: &Rc<Bridge>, command: generated::Command) {
    let command = match command {
        generated::Command::ToggleSidebar => Command::ToggleSidebar,
        generated::Command::ToggleInspector => Command::ToggleInspector,
        generated::Command::StopScan => Command::StopScan,
        generated::Command::OpenFolder => match (bridge.pick_folder)() {
            Some(folder) => Command::OpenFolder(folder),
            None => return,
        },
    };
    bridge.engine.borrow_mut().execute(command);
    bridge.show();
    if bridge.engine.borrow().library().status == ScanStatus::Scanning {
        watch_scan(bridge);
    }
}

/// Polls the engine on a timer while its scan runs. The timer holds the bridge weakly, since the
/// bridge owns the timer.
fn watch_scan(bridge: &Rc<Bridge>) {
    let bridge_weak: Weak<Bridge> = Rc::downgrade(bridge);
    bridge
        .scan_timer
        .start(TimerMode::Repeated, SCAN_POLL_INTERVAL, move || {
            if let Some(bridge) = bridge_weak.upgrade() {
                bridge.poll_scan();
            }
        });
}

impl Bridge {
    fn poll_scan(&self) {
        let changed = self.engine.borrow_mut().poll();
        if changed {
            self.show();
        }
        if self.engine.borrow().library().status != ScanStatus::Scanning {
            self.scan_timer.stop();
        }
    }

    fn show(&self) {
        let Some(window) = self.window.upgrade() else {
            return;
        };
        let engine = self.engine.borrow();
        show_view(&window, engine.view());
        show_library(&window, engine.library());
        self.show_tracks(engine.library());
    }

    /// Adds the tracks found since the last call. A newly opened folder has fewer tracks than the
    /// table, which empties it first.
    fn show_tracks(&self, library: &Library) {
        if library.tracks.len() < self.tracks.row_count() {
            self.tracks.clear();
        }
        let folder = library.folder.as_deref().unwrap_or(Path::new(""));
        let found = library
            .tracks
            .get(self.tracks.row_count()..)
            .unwrap_or_default();
        self.tracks
            .extend(found.iter().map(|track| track_row(folder, &track.path)));
    }
}

fn show_view(window: &AppWindow, view: &ViewState) {
    window.set_sidebar_visible(view.sidebar_visible);
    window.set_inspector_visible(view.inspector_visible);
}

fn show_library(window: &AppWindow, library: &Library) {
    window.set_folder_open(library.folder.is_some());
    window.set_folder(
        library
            .folder
            .as_deref()
            .map(display_folder)
            .unwrap_or_default()
            .into(),
    );
    window.set_scan_state(match library.status {
        ScanStatus::Idle => generated::ScanState::Idle,
        ScanStatus::Scanning => generated::ScanState::Scanning,
        ScanStatus::Completed => generated::ScanState::Completed,
        ScanStatus::Stopped => generated::ScanState::Stopped,
        ScanStatus::Failed => generated::ScanState::Failed,
    });
    window.set_track_count(count(library.tracks.len()));
    window.set_unreadable_count(count(library.unreadable.len()));
}

/// A track as the table shows it. Until its tags are read, its title is its file name.
fn track_row(folder: &Path, path: &Path) -> TrackRow {
    let text = |part: Option<&OsStr>| -> SharedString {
        part.map(|part| part.to_string_lossy().as_ref().into())
            .unwrap_or_default()
    };
    TrackRow {
        title: text(path.file_stem()),
        file: text(path.file_name()),
        folder: path
            .parent()
            .and_then(|parent| parent.strip_prefix(folder).ok())
            .map(|relative| relative.display().to_string().into())
            .unwrap_or_default(),
    }
}

fn count(length: usize) -> i32 {
    i32::try_from(length).unwrap_or(i32::MAX)
}

/// The folder as people read it, with `~` for their home folder.
fn display_folder(folder: &Path) -> String {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    match home
        .as_deref()
        .and_then(|home| folder.strip_prefix(home).ok())
    {
        Some(relative) if relative.as_os_str().is_empty() => "~".to_string(),
        Some(relative) => format!("~/{}", relative.display()),
        None => folder.display().to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn home() -> PathBuf {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default()
    }

    #[test]
    fn a_track_is_titled_after_its_file_name() {
        let row = track_row(
            Path::new("/music"),
            Path::new("/music/07 Paper Satellites.mp3"),
        );

        assert_eq!(row.title, "07 Paper Satellites");
        assert_eq!(row.file, "07 Paper Satellites.mp3");
        assert_eq!(row.folder, "");
    }

    #[test]
    fn a_track_in_a_subfolder_shows_the_path_from_the_opened_folder() {
        let folder = Path::new("/music");
        let row = track_row(
            folder,
            &folder
                .join("Marlowe Kite")
                .join("Small Hours")
                .join("07.mp3"),
        );

        assert_eq!(
            row.folder,
            Path::new("Marlowe Kite")
                .join("Small Hours")
                .display()
                .to_string()
        );
    }

    #[test]
    fn a_folder_in_the_home_folder_starts_with_a_tilde() {
        assert_eq!(display_folder(&home().join("Music")), "~/Music");
    }

    #[test]
    fn the_home_folder_itself_is_a_tilde() {
        assert_eq!(display_folder(&home()), "~");
    }

    #[test]
    fn a_folder_elsewhere_keeps_its_full_path() {
        assert_eq!(
            display_folder(Path::new("/Volumes/Music")),
            "/Volumes/Music"
        );
    }
}
