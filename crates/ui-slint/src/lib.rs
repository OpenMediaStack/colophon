//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::RefCell;
use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::time::Duration;

use colophon_engine::tags::{self, Id3v1Loss, ReadError};
use colophon_engine::{
    AudioLine, Column, ColumnWidths, Command, Edit, Engine, Field, Inspection, Library, ScanStatus,
    Selection, Shared, Step, Summary, Track, ViewState,
};
use slint::{CloseRequestResponse, Model, ModelRc, SharedString, Timer, TimerMode, VecModel};

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

/// What the window asks the engine to run, before the bridge turns it into a [`Command`].
pub use generated::Command as WindowCommand;
pub use generated::{
    AppWindow, BitrateMode, ByteSize, Id3v1Losses, InspectedTracks, InspectorField, InspectorState,
    Leaving, ReadProblem, ScanState, SizeUnit, TagEditing, TagField, Theme, TrackColumn,
    TrackColumnWidths, TrackColumns, TrackRow, TrackStatus, UnreadableFile, UnsavedChoice,
};
pub use slint::{ComponentHandle, PlatformError};

/// How often the window takes in what a running scan or save did: often enough to look live,
/// rarely enough to update the table in batches.
const POLL_INTERVAL: Duration = Duration::from_millis(50);

/// How many modified tracks the unsaved changes dialog names.
const NAMED_TRACKS: usize = 3;

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
        shown_modified: RefCell::default(),
        poll_timer: Timer::default(),
        pick_folder: Box::new(pick_folder),
        departure: RefCell::default(),
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
    let editing = window.global::<TagEditing>();
    editing.on_invalid(|field, text| parse_edit(field, &text).is_none());
    editing.on_commit({
        let bridge = Rc::clone(&bridge);
        move |field, text, continues| {
            if let Some(edit) = parse_edit(field, &text) {
                let command = if continues {
                    Command::ContinueEdit(edit)
                } else {
                    Command::Edit(edit)
                };
                execute(&bridge, command);
            }
        }
    });
    editing.on_cancel_typing({
        let bridge = Rc::clone(&bridge);
        move || execute(&bridge, Command::Undo)
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
    window.window().on_close_requested({
        let bridge = Rc::clone(&bridge);
        move || {
            if bridge.has_changes() {
                ask(&bridge, Destination::Quit);
                CloseRequestResponse::KeepWindowShown
            } else {
                CloseRequestResponse::HideWindow
            }
        }
    });
    window.on_unsaved_changes({
        let bridge = Rc::clone(&bridge);
        move |choice| answer(&bridge, choice)
    });
    Ok(window)
}

/// Asks the window to close, as its close button does, and says whether it closed: it stays open
/// while it asks what to do with pending changes.
pub fn request_close(window: &AppWindow) -> bool {
    window
        .window()
        .dispatch_event(slint::platform::WindowEvent::CloseRequested);
    !window.window().is_visible()
}

struct Bridge {
    engine: RefCell<Engine>,
    window: slint::Weak<AppWindow>,
    tracks: Rc<VecModel<TrackRow>>,
    /// The longest value of each column among the tracks shown.
    longest: RefCell<TrackRow>,
    /// The tracks shown with pending changes, whose rows change again when the changes go.
    shown_modified: RefCell<BTreeSet<usize>>,
    poll_timer: Timer,
    pick_folder: Box<dyn Fn() -> Option<PathBuf>>,
    departure: RefCell<Option<Departure>>,
}

/// Where the user was going when pending changes stopped them.
enum Destination {
    Quit,
    Folder(PathBuf),
}

/// A departure held up by pending changes.
enum Departure {
    /// The window asks what to do with them.
    Asking(Destination),
    /// Waits for the running save to end, then saves what is left first when `save` holds.
    AfterSave {
        destination: Destination,
        save: bool,
    },
    /// Goes once this save has written every file.
    Saving(Destination),
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
        generated::Command::Save => Command::Save,
        generated::Command::Undo => Command::Undo,
        generated::Command::Redo => Command::Redo,
        generated::Command::Revert => Command::Revert,
        generated::Command::OpenFolder => match (bridge.pick_folder)() {
            Some(folder) if bridge.has_changes() => {
                ask(bridge, Destination::Folder(folder));
                return;
            }
            Some(folder) => Command::OpenFolder(folder),
            None => return,
        },
    };
    execute(bridge, command);
}

fn ask(bridge: &Rc<Bridge>, destination: Destination) {
    bridge
        .departure
        .replace(Some(Departure::Asking(destination)));
    bridge.show();
}

fn answer(bridge: &Rc<Bridge>, choice: UnsavedChoice) {
    let Some(Departure::Asking(destination)) = bridge.departure.take() else {
        return;
    };
    let saving = bridge.engine.borrow().saving().is_some();
    match choice {
        UnsavedChoice::Cancel => bridge.show(),
        UnsavedChoice::Save | UnsavedChoice::Discard if saving => {
            let save = choice == UnsavedChoice::Save;
            bridge
                .departure
                .replace(Some(Departure::AfterSave { destination, save }));
            bridge.show();
        }
        UnsavedChoice::Save => save_then_go(bridge, destination),
        UnsavedChoice::Discard => go(bridge, destination),
    }
}

fn save_then_go(bridge: &Rc<Bridge>, destination: Destination) {
    execute(bridge, Command::Save);
    let (saving, failed) = {
        let engine = bridge.engine.borrow();
        (
            engine.saving().is_some(),
            !engine.save_failures().is_empty(),
        )
    };
    if saving {
        bridge
            .departure
            .replace(Some(Departure::Saving(destination)));
    } else if !failed {
        go(bridge, destination);
    }
}

/// Goes on with a departure that waited for the save, once it has ended. A file it could not
/// write keeps the user where they are, with the failure in the status bar.
fn after_save(bridge: &Rc<Bridge>) {
    match bridge.departure.take() {
        Some(Departure::AfterSave {
            destination,
            save: true,
        }) => save_then_go(bridge, destination),
        Some(Departure::AfterSave {
            destination,
            save: false,
        }) => go(bridge, destination),
        Some(Departure::Saving(destination)) => {
            if bridge.engine.borrow().save_failures().is_empty() {
                go(bridge, destination);
            }
        }
        waiting => {
            bridge.departure.replace(waiting);
        }
    }
}

fn go(bridge: &Rc<Bridge>, destination: Destination) {
    match destination {
        Destination::Quit => {
            if let Some(window) = bridge.window.upgrade() {
                window.hide().ok();
            }
        }
        Destination::Folder(folder) => execute(bridge, Command::OpenFolder(folder)),
    }
}

fn execute(bridge: &Rc<Bridge>, command: Command) {
    bridge.engine.borrow_mut().execute(command);
    bridge.show();
    if bridge.engine_busy() {
        watch_engine(bridge);
    }
}

/// Polls the engine on a timer while a scan or a save runs. The timer holds the bridge weakly,
/// since the bridge owns the timer.
fn watch_engine(bridge: &Rc<Bridge>) {
    if bridge.poll_timer.running() {
        return;
    }
    let bridge_weak: Weak<Bridge> = Rc::downgrade(bridge);
    bridge
        .poll_timer
        .start(TimerMode::Repeated, POLL_INTERVAL, move || {
            if let Some(bridge) = bridge_weak.upgrade() {
                poll_engine(&bridge);
            }
        });
}

fn poll_engine(bridge: &Rc<Bridge>) {
    let changed = bridge.engine.borrow_mut().poll();
    if changed {
        bridge.show();
    }
    if bridge.engine.borrow().saving().is_none() {
        after_save(bridge);
    }
    if !bridge.engine_busy() {
        bridge.poll_timer.stop();
    }
}

impl Bridge {
    fn engine_busy(&self) -> bool {
        let engine = self.engine.borrow();
        engine.library().status == ScanStatus::Scanning || engine.saving().is_some()
    }

    fn has_changes(&self) -> bool {
        self.engine.borrow().edits().modified_count() > 0
    }

    fn show(&self) {
        let Some(window) = self.window.upgrade() else {
            return;
        };
        let engine = self.engine.borrow();
        show_view(&window, engine.view());
        show_library(&window, engine.library());
        self.show_tracks(&window, &engine);
        self.show_selection(&window, engine.selection());
        show_inspection(&window, engine.library(), engine.inspection());
        show_saving(&window, &engine);
        self.show_departure(&window, &engine);
    }

    /// Shows the unsaved changes dialog while it asks, naming the first modified tracks as the
    /// table titles them.
    fn show_departure(&self, window: &AppWindow, engine: &Engine) {
        let departure = self.departure.borrow();
        let Some(Departure::Asking(destination)) = departure.as_ref() else {
            window.set_asking_to_save(false);
            return;
        };
        window.set_leaving(match destination {
            Destination::Quit => Leaving::Quit,
            Destination::Folder(_) => Leaving::OpenFolder,
        });
        let titles: Vec<SharedString> = engine
            .edits()
            .modified()
            .take(NAMED_TRACKS)
            .filter_map(|(track, _)| self.tracks.row_data(track))
            .map(|row| row.title)
            .collect();
        window.set_unsaved_titles(ModelRc::new(VecModel::from(titles)));
        window.set_asking_to_save(true);
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

    /// Adds the tracks found since the last call, and redraws those whose pending changes came or
    /// went. A newly opened folder has fewer tracks than the table, which empties it first.
    fn show_tracks(&self, window: &AppWindow, engine: &Engine) {
        let library = engine.library();
        if library.tracks.len() < self.tracks.row_count() {
            self.tracks.clear();
            self.longest.take();
            self.shown_modified.take();
        }
        let found = library
            .tracks
            .get(self.tracks.row_count()..)
            .unwrap_or_default();
        let rows: Vec<TrackRow> = found.iter().map(|track| track_row(track, None)).collect();
        let mut longest = self.longest.borrow_mut();
        for row in &rows {
            keep_longest(&mut longest, row);
        }
        self.tracks.extend(rows);

        let modified: BTreeSet<usize> = engine.edits().modified().map(|(track, _)| track).collect();
        let changed = self.shown_modified.replace(modified.clone());
        for index in changed.union(&modified) {
            let (Some(track), Some(old)) =
                (library.tracks.get(*index), self.tracks.row_data(*index))
            else {
                continue;
            };
            let row = TrackRow {
                selected: old.selected,
                selected_above: old.selected_above,
                selected_below: old.selected_below,
                ..track_row(track, engine.edits().pending(*index))
            };
            if row != old {
                keep_longest(&mut longest, &row);
                self.tracks.set_row_data(*index, row);
            }
        }
        window.set_longest(longest.clone());
        window.set_modified_count(count(engine.edits().modified_count()));
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
        mode,
    } = audio.unwrap_or(AudioLine {
        bitrate: 0,
        sample_rate: 0,
        mode: None,
    });
    let modified = |field| summary.modified.contains(&field);
    // Tenths of kilohertz, rounded: 44100 Hz reads 44.1 kHz, 22050 Hz 22.1 kHz.
    let tenths = (sample_rate + 50) / 100;
    InspectedTracks {
        count: count(summary.count),
        unreadable: count(summary.unreadable),
        heading: summary.heading.clone().unwrap_or_default().into(),
        title: field(&summary.title, modified(Field::Title), String::clone),
        artist: field(&summary.artist, modified(Field::Artist), String::clone),
        album_artist: field(
            &summary.album_artist,
            modified(Field::AlbumArtist),
            String::clone,
        ),
        album: field(&summary.album, modified(Field::Album), String::clone),
        year: field(&summary.year, modified(Field::Year), ToString::to_string),
        track: field(&summary.track, modified(Field::Track), ToString::to_string),
        track_total: field(
            &summary.track_total,
            modified(Field::TrackTotal),
            ToString::to_string,
        ),
        genre: field(&summary.genre, modified(Field::Genre), String::clone),
        comment: field(&summary.comment, modified(Field::Comment), String::clone),
        audio_shared: audio.is_some(),
        bitrate: number(bitrate),
        bitrate_mode: match mode {
            Some(tags::BitrateMode::Constant) => BitrateMode::Constant,
            Some(tags::BitrateMode::Variable) => BitrateMode::Variable,
            None => BitrateMode::Unknown,
        },
        sample_rate_whole: number(tenths / 10),
        sample_rate_tenth: number(tenths % 10),
        formats: field(&summary.formats, false, |formats| {
            formats
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        }),
        size: byte_size(summary.size),
        has_changes: !summary.modified.is_empty(),
        saved_as: field(&summary.saved_as, false, |formats| {
            formats
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        }),
        id3v1_losses: Id3v1Losses {
            title: summary.id3v1_losses.contains(&Id3v1Loss::Title),
            artist: summary.id3v1_losses.contains(&Id3v1Loss::Artist),
            album: summary.id3v1_losses.contains(&Id3v1Loss::Album),
            year: summary.id3v1_losses.contains(&Id3v1Loss::Year),
            comment: summary.id3v1_losses.contains(&Id3v1Loss::Comment),
            track: summary.id3v1_losses.contains(&Id3v1Loss::Track),
            genre: summary.id3v1_losses.contains(&Id3v1Loss::Genre),
        },
    }
}

fn field<T>(value: &Shared<T>, modified: bool, text: impl Fn(&T) -> String) -> InspectorField {
    let (text, mixed) = match value {
        Shared::Empty => (SharedString::default(), false),
        Shared::Same(value) => (text(value).into(), false),
        Shared::Mixed => (SharedString::default(), true),
    };
    InspectorField {
        text,
        mixed,
        modified,
    }
}

/// What a field's text sets, or `None` when the field cannot hold it: a year runs from 1 to
/// 9999, a track number and a total from 1. Empty text empties the field.
fn parse_edit(field: TagField, text: &str) -> Option<Edit> {
    let text_value = || Some(text.to_string()).filter(|text| !text.is_empty());
    let number = || -> Option<Option<u32>> {
        match text.trim() {
            "" => Some(None),
            digits => digits.parse().ok().filter(|number| *number > 0).map(Some),
        }
    };
    Some(match field {
        TagField::Title => Edit::Title(text_value()),
        TagField::Artist => Edit::Artist(text_value()),
        TagField::AlbumArtist => Edit::AlbumArtist(text_value()),
        TagField::Album => Edit::Album(text_value()),
        TagField::Genre => Edit::Genre(text_value()),
        TagField::Comment => Edit::Comment(text_value()),
        TagField::Track => Edit::Track(number()?),
        TagField::TrackTotal => Edit::TrackTotal(number()?),
        TagField::Year => Edit::Year(match text.trim() {
            "" => None,
            digits => Some(
                digits
                    .parse()
                    .ok()
                    .filter(|year| (1..=9999).contains(year))?,
            ),
        }),
    })
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

fn show_saving(window: &AppWindow, engine: &Engine) {
    window.set_can_undo(engine.edits().can_undo());
    window.set_can_redo(engine.edits().can_redo());
    let progress = engine.saving();
    window.set_saving(progress.is_some());
    window.set_save_done(progress.map_or(0, |progress| count(progress.done)));
    window.set_save_total(progress.map_or(0, |progress| count(progress.total)));
    window.set_save_failures(count(engine.save_failures().len()));
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

/// A track as the table shows it, with its pending tags if it has some. A file without a title tag,
/// or whose tags cannot be read, is titled after its file name.
fn track_row(track: &Track, pending: Option<&tags::Tags>) -> TrackRow {
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
    let tags = pending.unwrap_or(&metadata.tags);
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
        bitrate: number(audio.bitrate.map(|bitrate| match audio.bitrate_mode {
            Some(tags::BitrateMode::Variable) => format!("VBR {bitrate}"),
            _ => bitrate.to_string(),
        })),
        tags: metadata
            .formats
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ")
            .into(),
        status: if pending.is_some() {
            TrackStatus::Modified
        } else {
            TrackStatus::Normal
        },
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
        let row = track_row(&track(path, Ok(paper_satellites())), None);

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
    fn a_variable_bitrate_reads_as_in_the_mockup() {
        let mut metadata = paper_satellites();
        metadata.audio.bitrate = Some(245);
        metadata.audio.bitrate_mode = Some(tags::BitrateMode::Variable);

        let row = track_row(&track(Path::new("/music/07.mp3"), Ok(metadata)), None);

        assert_eq!(row.bitrate, "VBR 245");
    }

    #[test]
    fn a_track_without_a_title_is_titled_after_its_file_name() {
        let path = Path::new("/music/07 Paper Satellites.mp3");
        let row = track_row(&track(path, Ok(Metadata::default())), None);

        assert_eq!(row.title, "07 Paper Satellites");
        assert!(row.untitled);
        assert_eq!(row.number, "");
        assert_eq!(row.time, "");
    }

    #[test]
    fn an_unreadable_track_is_titled_after_its_file_name() {
        let path = Path::new("/music/07 Paper Satellites.mp3");
        let row = track_row(&track(path, Err(ReadError::ReaderPanicked)), None);

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
    fn a_track_with_pending_tags_shows_them_as_modified() {
        let pending = Tags {
            title: Some("Neon Overpass".into()),
            ..Tags::default()
        };

        let row = track_row(
            &track(Path::new("/music/07.mp3"), Ok(paper_satellites())),
            Some(&pending),
        );

        assert_eq!(row.title, "Neon Overpass");
        assert_eq!(row.artist, "");
        assert_eq!(row.status, TrackStatus::Modified);
    }

    #[test]
    fn typed_text_becomes_an_edit_or_is_refused() {
        assert_eq!(
            parse_edit(TagField::Title, "Neon Overpass"),
            Some(Edit::Title(Some("Neon Overpass".into())))
        );
        assert_eq!(parse_edit(TagField::Genre, ""), Some(Edit::Genre(None)));
        assert_eq!(
            parse_edit(TagField::Year, " 2024 "),
            Some(Edit::Year(Some(2024)))
        );
        assert_eq!(parse_edit(TagField::Year, ""), Some(Edit::Year(None)));
        assert_eq!(
            parse_edit(TagField::Track, "07"),
            Some(Edit::Track(Some(7)))
        );
        assert_eq!(parse_edit(TagField::Year, "20x4"), None);
        assert_eq!(parse_edit(TagField::Year, "0"), None);
        assert_eq!(parse_edit(TagField::Year, "10000"), None);
        assert_eq!(parse_edit(TagField::Track, "-3"), None);
        assert_eq!(parse_edit(TagField::TrackTotal, "0"), None);
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
        let mixed = field(&Shared::<String>::Mixed, false, String::clone);
        let same = field(&Shared::Same(2019), true, ToString::to_string);

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
        let row = track_row(&track(path, Ok(Metadata::default())), None);

        assert_eq!(row.folder, "/Volumes/Music/Marlowe Kite/Small Hours");
    }

    #[test]
    fn a_track_in_the_home_folder_shows_its_folder_with_a_tilde() {
        let path = home().join("Music").join("07.mp3");
        let row = track_row(&track(&path, Ok(Metadata::default())), None);

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
