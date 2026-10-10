//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::RefCell;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::time::Duration;

use colophon_engine::tags::ReadError;
use colophon_engine::{
    AudioLine, Column, ColumnWidths, Command, Engine, Inspection, Library, ScanStatus, Selection,
    Shared, Step, Summary, Track, ViewState,
};
use slint::{Model, ModelRc, SharedString, Timer, TimerMode, VecModel};

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

/// What the window asks the engine to run, before the bridge turns it into a [`Command`].
pub use generated::Command as WindowCommand;
pub use generated::{
    AppWindow, ByteSize, InspectedTracks, InspectorField, InspectorState, ReadProblem, ScanState,
    SizeUnit, Theme, TrackColumn, TrackColumnWidths, TrackColumns, TrackRow, TrackStatus,
    UnreadableFile,
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
        longest: RefCell::default(),
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
        move |column| {
            if let Some(column) = engine_column(column) {
                execute(&bridge, Command::ToggleColumn(column));
            }
        }
    });
    window.on_track_pressed({
        let bridge = Rc::clone(&bridge);
        move |row, toggle, extend| {
            let Ok(track) = usize::try_from(row) else {
                return;
            };
            let command = if extend {
                Command::SelectRange(track)
            } else if toggle {
                Command::ToggleSelected(track)
            } else {
                Command::Select(track)
            };
            execute(&bridge, command);
        }
    });
    window.on_resize_columns({
        let bridge = Rc::clone(&bridge);
        move |widths| execute(&bridge, Command::ResizeColumns(engine_widths(widths)))
    });
    Ok(window)
}

struct Bridge {
    engine: RefCell<Engine>,
    window: slint::Weak<AppWindow>,
    tracks: Rc<VecModel<TrackRow>>,
    /// The longest value of each column among the tracks shown.
    longest: RefCell<TrackRow>,
    scan_timer: Timer,
    pick_folder: Box<dyn Fn() -> Option<PathBuf>>,
}

fn run(bridge: &Rc<Bridge>, command: generated::Command) {
    let command = match command {
        generated::Command::ToggleSidebar => Command::ToggleSidebar,
        generated::Command::ToggleInspector => Command::ToggleInspector,
        generated::Command::StopScan => Command::StopScan,
        generated::Command::ResetColumns => Command::ResetColumns,
        generated::Command::SelectAll => Command::SelectAll,
        generated::Command::SelectPrevious => Command::MoveSelection(Step::Up),
        generated::Command::SelectNext => Command::MoveSelection(Step::Down),
        generated::Command::ExtendSelectionUp => Command::ExtendSelection(Step::Up),
        generated::Command::ExtendSelectionDown => Command::ExtendSelection(Step::Down),
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
        self.show_tracks(&window, engine.library());
        self.show_selection(&window, engine.selection());
        show_inspection(&window, engine.library(), engine.inspection());
    }

    /// Marks the selected rows, touching only the rows that change.
    fn show_selection(&self, window: &AppWindow, selection: &Selection) {
        for index in 0..self.tracks.row_count() {
            let Some(row) = self.tracks.row_data(index) else {
                continue;
            };
            let marks = SelectionMarks::of(index, |track| selection.contains(track));
            if SelectionMarks::from(&row) != marks {
                self.tracks.set_row_data(index, marks.on(row));
            }
        }
        window.set_focused_row(selection.focus().map_or(-1, count));
        window.set_selected_count(count(selection.len()));
    }

    /// Adds the tracks found since the last call. A newly opened folder has fewer tracks than the
    /// table, which empties it first.
    fn show_tracks(&self, window: &AppWindow, library: &Library) {
        if library.tracks.len() < self.tracks.row_count() {
            self.tracks.clear();
            self.longest.take();
        }
        let found = library
            .tracks
            .get(self.tracks.row_count()..)
            .unwrap_or_default();
        let rows: Vec<TrackRow> = found.iter().map(track_row).collect();
        let mut longest = self.longest.borrow_mut();
        for row in &rows {
            keep_longest(&mut longest, row);
        }
        window.set_longest(longest.clone());
        self.tracks.extend(rows);
    }
}

/// How a row shows the selection: selected, and whether the rows above and below are too, so that
/// a run of selected rows gets one outline.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SelectionMarks {
    selected: bool,
    above: bool,
    below: bool,
}

impl SelectionMarks {
    fn of(index: usize, is_selected: impl Fn(usize) -> bool) -> Self {
        let selected = is_selected(index);
        Self {
            selected,
            above: selected && index.checked_sub(1).is_some_and(&is_selected),
            below: selected && is_selected(index + 1),
        }
    }

    fn on(self, row: TrackRow) -> TrackRow {
        TrackRow {
            selected: self.selected,
            selected_above: self.above,
            selected_below: self.below,
            ..row
        }
    }
}

impl From<&TrackRow> for SelectionMarks {
    fn from(row: &TrackRow) -> Self {
        Self {
            selected: row.selected,
            above: row.selected_above,
            below: row.selected_below,
        }
    }
}

fn show_inspection(window: &AppWindow, library: &Library, inspection: Inspection<'_>) {
    let state = match inspection {
        _ if library.folder.is_none() => InspectorState::Empty,
        Inspection::Nothing => InspectorState::NothingSelected,
        Inspection::Unreadable { track, error } => {
            window.set_unreadable_file(UnreadableFile {
                path: display_folder(&track.path).into(),
                problem: read_problem(error),
                size: byte_size(track.size),
            });
            InspectorState::Unreadable
        }
        Inspection::Tracks(summary) => {
            window.set_inspected_tracks(inspected_tracks(&summary));
            InspectorState::Tracks
        }
    };
    window.set_inspector_state(state);
}

fn read_problem(error: &ReadError) -> ReadProblem {
    match error {
        ReadError::Open(_) => ReadProblem::CannotOpen,
        ReadError::Damaged(_) => ReadProblem::Damaged,
        ReadError::ReaderPanicked => ReadProblem::ReaderFailed,
    }
}

fn inspected_tracks(summary: &Summary) -> InspectedTracks {
    let audio = match summary.audio {
        Shared::Same(audio) => Some(audio),
        Shared::Empty | Shared::Mixed => None,
    };
    let AudioLine {
        bitrate,
        sample_rate,
    } = audio.unwrap_or(AudioLine {
        bitrate: 0,
        sample_rate: 0,
    });
    // Tenths of kilohertz, rounded: 44100 Hz reads 44.1 kHz, 22050 Hz 22.1 kHz.
    let tenths = (sample_rate + 50) / 100;
    InspectedTracks {
        count: count(summary.count),
        unreadable: count(summary.unreadable),
        heading: summary.heading.clone().unwrap_or_default().into(),
        title: field(&summary.title, String::clone),
        artist: field(&summary.artist, String::clone),
        album_artist: field(&summary.album_artist, String::clone),
        album: field(&summary.album, String::clone),
        year: field(&summary.year, ToString::to_string),
        track: field(&summary.track, ToString::to_string),
        track_total: field(&summary.track_total, ToString::to_string),
        genre: field(&summary.genre, String::clone),
        comment: field(&summary.comment, String::clone),
        audio_shared: audio.is_some(),
        bitrate: number(bitrate),
        sample_rate_whole: number(tenths / 10),
        sample_rate_tenth: number(tenths % 10),
        formats: field(&summary.formats, |formats| {
            formats
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        }),
        size: byte_size(summary.size),
    }
}

fn field<T>(value: &Shared<T>, text: impl Fn(&T) -> String) -> InspectorField {
    match value {
        Shared::Empty => InspectorField::default(),
        Shared::Same(value) => InspectorField {
            text: text(value).into(),
            mixed: false,
        },
        Shared::Mixed => InspectorField {
            text: SharedString::default(),
            mixed: true,
        },
    }
}

/// A size in decimal units, as macOS writes them: a whole number of kilobytes, one decimal digit
/// from a megabyte on.
fn byte_size(bytes: u64) -> ByteSize {
    let (unit, scale) = match bytes {
        0..1_000 => return sized(bytes, 0, SizeUnit::Bytes),
        1_000..1_000_000 => return sized((bytes + 500) / 1_000, 0, SizeUnit::Kilobytes),
        1_000_000..1_000_000_000 => (SizeUnit::Megabytes, 100_000),
        _ => (SizeUnit::Gigabytes, 100_000_000),
    };
    let tenths = (bytes + scale / 2) / scale;
    sized(tenths / 10, tenths % 10, unit)
}

fn sized(whole: u64, tenth: u64, unit: SizeUnit) -> ByteSize {
    ByteSize {
        whole: number(whole),
        tenth: number(tenth),
        unit,
    }
}

fn number(value: impl TryInto<i32>) -> i32 {
    value.try_into().unwrap_or(i32::MAX)
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
    window.set_columns_sized(view.column_widths.is_some());
    if let Some(widths) = view.column_widths {
        window.set_column_widths(slint_widths(widths));
    }
}

/// The title cannot be hidden, so it is not a column of the chooser.
fn engine_column(column: TrackColumn) -> Option<Column> {
    match column {
        TrackColumn::Title => None,
        TrackColumn::Artist => Some(Column::Artist),
        TrackColumn::Album => Some(Column::Album),
        TrackColumn::Year => Some(Column::Year),
        TrackColumn::Genre => Some(Column::Genre),
        TrackColumn::Time => Some(Column::Time),
        TrackColumn::Bitrate => Some(Column::Bitrate),
        TrackColumn::Tags => Some(Column::Tags),
        TrackColumn::File => Some(Column::File),
        TrackColumn::Folder => Some(Column::Folder),
    }
}

/// Widths in whole logical pixels, which is all a column needs.
fn engine_widths(widths: TrackColumnWidths) -> ColumnWidths {
    let pixels = |width: f32| width.round() as u32;
    ColumnWidths {
        title: pixels(widths.title),
        artist: pixels(widths.artist),
        album: pixels(widths.album),
        year: pixels(widths.year),
        genre: pixels(widths.genre),
        time: pixels(widths.time),
        bitrate: pixels(widths.bitrate),
        tags: pixels(widths.tags),
        file: pixels(widths.file),
        folder: pixels(widths.folder),
    }
}

fn slint_widths(widths: ColumnWidths) -> TrackColumnWidths {
    let length = |pixels: u32| pixels as f32;
    TrackColumnWidths {
        title: length(widths.title),
        artist: length(widths.artist),
        album: length(widths.album),
        year: length(widths.year),
        genre: length(widths.genre),
        time: length(widths.time),
        bitrate: length(widths.bitrate),
        tags: length(widths.tags),
        file: length(widths.file),
        folder: length(widths.folder),
    }
}

/// Keeps, column by column, the value with the most characters: a close enough guess at the
/// widest one, which the table then measures.
fn keep_longest(longest: &mut TrackRow, row: &TrackRow) {
    let keep = |longest: &mut SharedString, value: &SharedString| {
        if value.chars().count() > longest.chars().count() {
            *longest = value.clone();
        }
    };
    keep(&mut longest.title, &row.title);
    keep(&mut longest.artist, &row.artist);
    keep(&mut longest.album, &row.album);
    keep(&mut longest.year, &row.year);
    keep(&mut longest.genre, &row.genre);
    keep(&mut longest.time, &row.time);
    keep(&mut longest.bitrate, &row.bitrate);
    keep(&mut longest.tags, &row.tags);
    keep(&mut longest.file, &row.file);
    keep(&mut longest.folder, &row.folder);
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
fn track_row(track: &Track) -> TrackRow {
    let path = &track.path;
    let name = |part: Option<&OsStr>| -> SharedString {
        part.map(|part| part.to_string_lossy().as_ref().into())
            .unwrap_or_default()
    };
    let row = TrackRow {
        title: name(path.file_stem()),
        file: name(path.file_name()),
        folder: path.parent().map(display_folder).unwrap_or_default().into(),
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
        let row = track_row(&track(path, Ok(paper_satellites())));

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
        let row = track_row(&track(path, Ok(Metadata::default())));

        assert_eq!(row.title, "07 Paper Satellites");
        assert!(row.untitled);
        assert_eq!(row.number, "");
        assert_eq!(row.time, "");
    }

    #[test]
    fn an_unreadable_track_is_titled_after_its_file_name() {
        let path = Path::new("/music/07 Paper Satellites.mp3");
        let row = track_row(&track(path, Err(ReadError::ReaderPanicked)));

        assert_eq!(row.status, TrackStatus::Unreadable);
        assert_eq!(row.title, "07 Paper Satellites");
        assert_eq!(row.artist, "");
    }

    #[test]
    fn the_longest_value_of_each_column_is_kept() {
        let mut longest = TrackRow::default();
        let row = |title: &str, artist: &str| TrackRow {
            title: title.into(),
            artist: artist.into(),
            ..TrackRow::default()
        };

        keep_longest(&mut longest, &row("Neon Overpass", "Cassette Bloom"));
        keep_longest(&mut longest, &row("Long Exposure at Night", "Bloom"));

        assert_eq!(longest.title, "Long Exposure at Night");
        assert_eq!(longest.artist, "Cassette Bloom");
    }

    #[test]
    fn a_run_of_selected_rows_is_marked_as_one() {
        let selected = |track: usize| matches!(track, 2..=4 | 7);
        let marks = |index| {
            let marks = SelectionMarks::of(index, selected);
            (marks.selected, marks.above, marks.below)
        };

        assert_eq!(marks(1), (false, false, false));
        assert_eq!(marks(2), (true, false, true));
        assert_eq!(marks(3), (true, true, true));
        assert_eq!(marks(4), (true, true, false));
        assert_eq!(marks(5), (false, false, false));
        assert_eq!(marks(7), (true, false, false));
    }

    #[test]
    fn sizes_read_as_on_macos() {
        let size = |bytes| {
            let size = byte_size(bytes);
            (size.whole, size.tenth, size.unit)
        };

        assert_eq!(size(999), (999, 0, SizeUnit::Bytes));
        assert_eq!(size(1_202), (1, 0, SizeUnit::Kilobytes));
        assert_eq!(size(850_400), (850, 0, SizeUnit::Kilobytes));
        assert_eq!(size(25_400_000), (25, 4, SizeUnit::Megabytes));
        assert_eq!(size(8_349_999), (8, 3, SizeUnit::Megabytes));
        assert_eq!(size(1_250_000_000), (1, 3, SizeUnit::Gigabytes));
    }

    #[test]
    fn a_mixed_field_has_no_text() {
        let mixed = field(&Shared::<String>::Mixed, String::clone);
        let same = field(&Shared::Same(2019), ToString::to_string);

        assert!(mixed.mixed && mixed.text.is_empty());
        assert_eq!((same.text.as_str(), same.mixed), ("2019", false));
    }

    #[test]
    fn durations_read_as_in_a_player() {
        let text = |seconds| duration_text(Duration::from_secs(seconds));

        assert_eq!(text(5), "0:05");
        assert_eq!(text(221), "3:41");
        assert_eq!(text(3723), "1:02:03");
    }

    #[test]
    fn a_track_shows_the_full_path_of_its_folder() {
        let path = Path::new("/Volumes/Music/Marlowe Kite/Small Hours/07.mp3");
        let row = track_row(&track(path, Ok(Metadata::default())));

        assert_eq!(row.folder, "/Volumes/Music/Marlowe Kite/Small Hours");
    }

    #[test]
    fn a_track_in_the_home_folder_shows_its_folder_with_a_tilde() {
        let path = home().join("Music").join("07.mp3");
        let row = track_row(&track(&path, Ok(Metadata::default())));

        assert_eq!(row.folder, "~/Music");
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
