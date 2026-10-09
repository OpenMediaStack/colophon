//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::time::Duration;

use colophon_engine::{Command, Engine, Library, ScanStatus, ViewState};
use slint::{Timer, TimerMode};

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

pub use generated::{AppWindow, Theme};
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
    let bridge = Rc::new(Bridge {
        engine: RefCell::new(engine),
        window: window.as_weak(),
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
