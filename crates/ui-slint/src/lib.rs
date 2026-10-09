//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::RefCell;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::time::Duration;

use colophon_engine::{Column, Command, Engine, Library, ScanStatus, Track, ViewState};
use slint::{Model, ModelRc, SharedString, Timer, TimerMode, VecModel};

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

pub use generated::{
    AppWindow, ScanState, Theme, TrackColumn, TrackColumns, TrackRow, TrackStatus,
};
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
    window.on_toggle_column({
        let bridge = Rc::clone(&bridge);
        move |column| execute(&bridge, Command::ToggleColumn(engine_column(column)))
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
        generated::Command::ResetColumns => Command::ResetColumns,
        generated::Command::OpenFolder => match (bridge.pick_folder)() {
            Some(folder) => Command::OpenFolder(folder),
            None => return,
        },
    };
    execute(bridge, command);
}

fn execute(bridge: &Rc<Bridge>, command: Command) {
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
            .extend(found.iter().map(|track| track_row(folder, track)));
    }
}

fn show_view(window: &AppWindow, view: &ViewState) {
    window.set_sidebar_visible(view.sidebar_visible);
    window.set_inspector_visible(view.inspector_visible);
    let shown = |column| view.columns.contains(column);
    window.set_columns(TrackColumns {
        artist: shown(Column::Artist),
        album: shown(Column::Album),
        year: shown(Column::Year),
        genre: shown(Column::Genre),
        time: shown(Column::Time),
        bitrate: shown(Column::Bitrate),
        tags: shown(Column::Tags),
        file: shown(Column::File),
        folder: shown(Column::Folder),
    });
}

fn engine_column(column: TrackColumn) -> Column {
    match column {
        TrackColumn::Artist => Column::Artist,
        TrackColumn::Album => Column::Album,
        TrackColumn::Year => Column::Year,
        TrackColumn::Genre => Column::Genre,
        TrackColumn::Time => Column::Time,
        TrackColumn::Bitrate => Column::Bitrate,
        TrackColumn::Tags => Column::Tags,
        TrackColumn::File => Column::File,
        TrackColumn::Folder => Column::Folder,
    }
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

/// A track as the table shows it. A file without a title tag, or whose tags cannot be read, is
/// titled after its file name.
fn track_row(folder: &Path, track: &Track) -> TrackRow {
    let path = &track.path;
    let name = |part: Option<&OsStr>| -> SharedString {
        part.map(|part| part.to_string_lossy().as_ref().into())
            .unwrap_or_default()
    };
    let row = TrackRow {
        title: name(path.file_stem()),
        file: name(path.file_name()),
        folder: path
            .parent()
            .and_then(|parent| parent.strip_prefix(folder).ok())
            .map(|relative| relative.display().to_string().into())
            .unwrap_or_default(),
        ..TrackRow::default()
    };
    let Ok(metadata) = &track.metadata else {
        return TrackRow {
            status: TrackStatus::Unreadable,
            ..row
        };
    };
    let tags = &metadata.tags;
    let audio = &metadata.audio;
    let text =
        |value: &Option<String>| -> SharedString { value.as_deref().unwrap_or_default().into() };
    let number = |value: Option<String>| -> SharedString { value.unwrap_or_default().into() };
    TrackRow {
        number: number(tags.track.map(|track| format!("{track:02}"))),
        title: tags
            .title
            .as_deref()
            .map_or(row.title.clone(), SharedString::from),
        untitled: tags.title.is_none(),
        artist: text(&tags.artist),
        album: text(&tags.album),
        year: number(tags.year.map(|year| year.to_string())),
        genre: text(&tags.genre),
        time: number(audio.duration.map(duration_text)),
        bitrate: number(audio.bitrate.map(|bitrate| bitrate.to_string())),
        tags: metadata
            .formats
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ")
            .into(),
        ..row
    }
}

/// A duration as players show it: minutes and seconds, with hours from an hour on.
fn duration_text(duration: Duration) -> String {
    let seconds = duration.as_secs();
    let (hours, minutes, seconds) = (seconds / 3600, seconds / 60 % 60, seconds % 60);
    if hours > 0 {
        format!("{hours}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes}:{seconds:02}")
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

    use colophon_engine::tags::{
        AudioProperties, Id3v1Version, Id3v2Version, Metadata, ReadError, TagFormat, Tags,
    };

    fn track(path: &Path, metadata: Result<Metadata, ReadError>) -> Track {
        Track {
            path: path.to_path_buf(),
            size: 0,
            modified: None,
            metadata,
        }
    }

    fn paper_satellites() -> Metadata {
        Metadata {
            tags: Tags {
                title: Some("Paper Satellites".into()),
                artist: Some("Marlowe Kite".into()),
                album: Some("Small Hours".into()),
                year: Some(2019),
                track: Some(3),
                track_total: Some(12),
                genre: Some("Folk".into()),
                ..Tags::default()
            },
            audio: AudioProperties {
                duration: Some(Duration::from_millis(221_700)),
                bitrate: Some(320),
                ..AudioProperties::default()
            },
            formats: vec![
                TagFormat::Id3v2(Id3v2Version::V2_3),
                TagFormat::Id3v1(Id3v1Version::V1_1),
            ],
        }
    }

    #[test]
    fn a_track_shows_its_tags() {
        let path = Path::new("/music/07.mp3");
        let row = track_row(Path::new("/music"), &track(path, Ok(paper_satellites())));

        assert_eq!(row.status, TrackStatus::Normal);
        assert_eq!(row.number, "03");
        assert_eq!(row.title, "Paper Satellites");
        assert!(!row.untitled);
        assert_eq!(row.artist, "Marlowe Kite");
        assert_eq!(row.album, "Small Hours");
        assert_eq!(row.year, "2019");
        assert_eq!(row.genre, "Folk");
        assert_eq!(row.time, "3:41");
        assert_eq!(row.bitrate, "320");
        assert_eq!(row.tags, "ID3v2.3, ID3v1.1");
        assert_eq!(row.file, "07.mp3");
    }

    #[test]
    fn a_track_without_a_title_is_titled_after_its_file_name() {
        let path = Path::new("/music/07 Paper Satellites.mp3");
        let row = track_row(Path::new("/music"), &track(path, Ok(Metadata::default())));

        assert_eq!(row.title, "07 Paper Satellites");
        assert!(row.untitled);
        assert_eq!(row.number, "");
        assert_eq!(row.time, "");
    }

    #[test]
    fn an_unreadable_track_is_titled_after_its_file_name() {
        let path = Path::new("/music/07 Paper Satellites.mp3");
        let row = track_row(
            Path::new("/music"),
            &track(path, Err(ReadError::ReaderPanicked)),
        );

        assert_eq!(row.status, TrackStatus::Unreadable);
        assert_eq!(row.title, "07 Paper Satellites");
        assert_eq!(row.artist, "");
    }

    #[test]
    fn durations_read_as_in_a_player() {
        let text = |seconds| duration_text(Duration::from_secs(seconds));

        assert_eq!(text(5), "0:05");
        assert_eq!(text(221), "3:41");
        assert_eq!(text(3723), "1:02:03");
    }

    #[test]
    fn a_track_in_a_subfolder_shows_the_path_from_the_opened_folder() {
        let folder = Path::new("/music");
        let path = folder
            .join("Marlowe Kite")
            .join("Small Hours")
            .join("07.mp3");
        let row = track_row(folder, &track(&path, Ok(Metadata::default())));

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
