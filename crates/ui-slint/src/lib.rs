//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::{Cell, RefCell};
use std::collections::{BTreeSet, HashMap};
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::rc::{Rc, Weak};
use std::sync::Arc;
use std::sync::mpsc::{Receiver, TryRecvError};
use std::time::Duration;

use colophon_engine::tags::{self, Id3v1Loss, Id3v1Version, Id3v2Version, ReadError, WritePolicy};
use colophon_engine::{
    AlbumKey, AudioLine, Column, ColumnWidths, Command, Edit, Engine, Field, Inspection, Library,
    Preferences, ScanStatus, Selection, Shared, Sort, SortColumn, Source, Step, Summary, Track,
    VersionChoice, ViewState, WindowSize,
};
use slint::{
    CloseRequestResponse, Image, LogicalSize, Model, ModelRc, Rgba8Pixel, SharedPixelBuffer,
    SharedString, Timer, TimerMode, VecModel,
};

mod palette;

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

/// What the window asks the engine to run, before the bridge turns it into a [`Command`].
pub use generated::Command as WindowCommand;
pub use generated::{
    AppWindow, BitrateMode, ByteSize, CoverState, Id3v1Losses, Id3v1Policy, InspectedTracks,
    InspectorField, InspectorState, Kilohertz, PaletteAction, PaletteEntry, PaletteMatch,
    ReadProblem, RemovedTag, ScanState, SidebarItem, SizeUnit, SourceKind, TagEditing, TagField,
    TagRemoval, Theme, TrackColumn, TrackColumnWidths, TrackColumns, TrackRow, TrackSpectrum,
    TrackStatus, UnreadableFile, UnsavedChoice,
};
pub use slint::{ComponentHandle, PlatformError};

/// How often the window takes in what a running scan or save did: often enough to look live,
/// rarely enough to update the table in batches.
const POLL_INTERVAL: Duration = Duration::from_millis(50);

/// How many modified tracks the unsaved changes dialog names.
const NAMED_TRACKS: usize = 3;

/// How many files the dialog that asks before removing a tag lists.
const LISTED_FILES: usize = 8;

/// How many albums the sidebar shows until the user asks for them all.
const FIRST_ALBUMS: usize = 8;

/// The choices of the inspector's Tag format section, in their order.
const ID3V2_CHOICES: [Option<Id3v2Version>; 4] = [
    None,
    Some(Id3v2Version::V2_2),
    Some(Id3v2Version::V2_3),
    Some(Id3v2Version::V2_4),
];
const ID3V1_CHOICES: [Option<Id3v1Version>; 3] =
    [None, Some(Id3v1Version::V1_0), Some(Id3v1Version::V1_1)];

/// How the window asks the user for folders and files, usually through the system's dialogs.
pub trait Dialogs {
    fn pick_folder(&self) -> Option<PathBuf>;

    /// The audio files to open; none when the user cancels.
    fn pick_files(&self) -> Vec<PathBuf> {
        Vec::new()
    }

    /// A JPEG or PNG image to use as a cover.
    fn pick_image(&self) -> Option<PathBuf> {
        None
    }

    /// Where to save a file, starting from the name `suggested`.
    fn pick_save_path(&self, suggested: &str) -> Option<PathBuf> {
        let _ = suggested;
        None
    }
}

/// A function that picks a folder, for windows that never ask for anything else.
impl<F: Fn() -> Option<PathBuf>> Dialogs for F {
    fn pick_folder(&self) -> Option<PathBuf> {
        self()
    }
}

/// Creates the main window and hands its user actions to the engine, which then drives what it shows.
pub fn main_window(
    engine: Engine,
    dialogs: impl Dialogs + 'static,
) -> Result<AppWindow, PlatformError> {
    main_window_keeping(engine, dialogs, |_: &Preferences| {})
}

/// The same, at the size the engine's preferences remember, handing them to `keep` each time
/// they change and when the window closes, so that the next launch starts from them.
pub fn main_window_keeping(
    engine: Engine,
    dialogs: impl Dialogs + 'static,
    keep: impl Fn(&Preferences) + 'static,
) -> Result<AppWindow, PlatformError> {
    let window = AppWindow::new()?;
    if let Some(size) = engine.view().window_size {
        window
            .window()
            .set_size(LogicalSize::new(size.width as f32, size.height as f32));
    }
    let kept = engine.preferences();
    let tracks = Rc::new(VecModel::default());
    window.set_tracks(ModelRc::from(Rc::clone(&tracks)));
    let bridge = Rc::new_cyclic(|me| Bridge {
        me: me.clone(),
        engine: RefCell::new(engine),
        window: window.as_weak(),
        tracks,
        longest: RefCell::default(),
        shown_modified: RefCell::default(),
        listed: RefCell::default(),
        row_of: RefCell::default(),
        poll_timer: Timer::default(),
        dialogs: Box::new(dialogs),
        departure: RefCell::default(),
        genres: RefCell::default(),
        genres_read_from: Cell::default(),
        removal: Cell::default(),
        sources: RefCell::default(),
        drawn_cover: RefCell::default(),
        thumbnails: RefCell::default(),
        thumbnail_timer: Timer::default(),
        shown_playing: Cell::default(),
        waveform: RefCell::default(),
        spectrum: RefCell::default(),
        spectrum_timer: Timer::default(),
        kept: Cell::new(kept),
        keep: Box::new(keep),
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
    editing.on_genres({
        let bridge = Rc::clone(&bridge);
        move |text| {
            let genres = suggested_genres(&bridge.genres.borrow(), &text);
            ModelRc::new(VecModel::from(genres))
        }
    });
    window.on_track_pressed({
        let bridge = Rc::clone(&bridge);
        move |row, toggle, extend| {
            let Some(track) = bridge.track_at(row) else {
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
    window.on_play_row({
        let bridge = Rc::clone(&bridge);
        move |row| {
            if let Some(track) = bridge.track_at(row) {
                execute(&bridge, Command::Play(track));
            }
        }
    });
    window.on_choose_id3v2({
        let bridge = Rc::clone(&bridge);
        move |index| {
            if let Some(version) = choice(&ID3V2_CHOICES, index) {
                choose_version(&bridge, VersionChoice::Id3v2(version));
            }
        }
    });
    window.on_choose_id3v1({
        let bridge = Rc::clone(&bridge);
        move |index| {
            if let Some(version) = choice(&ID3V1_CHOICES, index) {
                choose_version(&bridge, VersionChoice::Id3v1(version));
            }
        }
    });
    window.on_choose_id3v2_3({
        let bridge = Rc::clone(&bridge);
        move |older| {
            let id3v2 = if older {
                Id3v2Version::V2_3
            } else {
                Id3v2Version::V2_4
            };
            change_policy(&bridge, |policy| policy.id3v2 = id3v2);
        }
    });
    window.on_choose_id3v1_policy({
        let bridge = Rc::clone(&bridge);
        move |id3v1| {
            let id3v1 = match id3v1 {
                Id3v1Policy::Keep => tags::Id3v1Policy::Keep,
                Id3v1Policy::Always => tags::Id3v1Policy::Always,
                Id3v1Policy::Never => tags::Id3v1Policy::Never,
            };
            change_policy(&bridge, |policy| policy.id3v1 = id3v1);
        }
    });
    window.on_filter_palette(|entries, query| {
        ModelRc::new(VecModel::from(palette::matches(entries.iter(), &query)))
    });
    window.on_palette_chosen({
        let bridge = Rc::clone(&bridge);
        move |action| run_palette(&bridge, action)
    });
    window.on_removal_answered({
        let bridge = Rc::clone(&bridge);
        move |remove| {
            let removal = bridge.removal.take();
            if let Some(window) = bridge.window.upgrade() {
                window.set_confirming_removal(false);
            }
            match removal {
                Some(Removal::Choice(choice)) if remove => {
                    execute(&bridge, Command::ChooseVersion(choice));
                }
                Some(Removal::Save) if remove => execute(&bridge, Command::Save),
                Some(Removal::Save) => execute(&bridge, Command::SaveKeepingId3v1),
                _ => {}
            }
        }
    });
    window.on_show_source({
        let bridge = Rc::clone(&bridge);
        move |kind, index| {
            let source = {
                let sources = bridge.sources.borrow();
                let place = usize::try_from(index).unwrap_or(usize::MAX);
                match kind {
                    SourceKind::AllTracks => Some(Source::AllTracks),
                    SourceKind::RecentlyChanged => Some(Source::RecentlyChanged),
                    SourceKind::Unreadable => Some(Source::Unreadable),
                    SourceKind::Folder => sources.folders.get(place).cloned().map(Source::Folder),
                    SourceKind::Album => sources.albums.get(place).cloned().map(Source::Album),
                    SourceKind::Artist => sources.artists.get(place).cloned().map(Source::Artist),
                }
            };
            if let Some(source) = source {
                execute(&bridge, Command::ShowSource(source));
            }
        }
    });
    window.on_filter_edited({
        let bridge = Rc::clone(&bridge);
        move |text| execute(&bridge, Command::Filter(text.into()))
    });
    window.on_replace_cover({
        let bridge = Rc::clone(&bridge);
        move || {
            let Some(cover) = bridge
                .dialogs
                .pick_image()
                .and_then(|path| cover_from(&path))
            else {
                return;
            };
            execute(&bridge, Command::Edit(Edit::Cover(Some(cover))));
        }
    });
    window.on_remove_cover({
        let bridge = Rc::clone(&bridge);
        move || execute(&bridge, Command::Edit(Edit::Cover(None)))
    });
    window.on_extract_cover({
        let bridge = Rc::clone(&bridge);
        move || {
            let cover = match bridge.engine.borrow().inspection() {
                Inspection::Tracks(summary) => match summary.cover {
                    Shared::Same(cover) => Some(cover),
                    Shared::Empty | Shared::Mixed => None,
                },
                Inspection::Nothing | Inspection::Unreadable { .. } => None,
            };
            let Some(cover) = cover else {
                return;
            };
            let name = format!("cover.{}", cover_extension(&cover));
            if let Some(path) = bridge.dialogs.pick_save_path(&name) {
                // A failure leaves nothing behind; there is no message to show it yet.
                let _ = std::fs::write(path, &*cover.data);
            }
        }
    });
    window.on_player_seek({
        let bridge = Rc::clone(&bridge);
        move |progress| {
            let duration = bridge.playing_duration();
            if let Some(duration) = duration {
                execute(
                    &bridge,
                    Command::Seek(duration.mul_f32(progress.clamp(0.0, 1.0))),
                );
            }
        }
    });
    window.on_player_set_volume({
        let bridge = Rc::clone(&bridge);
        move |volume| {
            let percent = (volume.clamp(0.0, 1.0) * 100.0).round() as u8;
            execute(&bridge, Command::SetVolume(percent));
        }
    });
    window.on_sort_by({
        let bridge = Rc::clone(&bridge);
        move |column| execute(&bridge, Command::SortBy(engine_sort_column(column)))
    });
    window.on_resize_columns({
        let bridge = Rc::clone(&bridge);
        move |widths| execute(&bridge, Command::ResizeColumns(engine_widths(widths)))
    });
    window.window().on_close_requested({
        let bridge = Rc::clone(&bridge);
        move || {
            if bridge.has_changes() {
                ask(&bridge);
                CloseRequestResponse::KeepWindowShown
            } else {
                bridge.keep_window_size();
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
    /// The bridge itself, for the timers it starts.
    me: Weak<Bridge>,
    engine: RefCell<Engine>,
    window: slint::Weak<AppWindow>,
    tracks: Rc<VecModel<TrackRow>>,
    /// The longest value of each column among the tracks shown.
    longest: RefCell<TrackRow>,
    /// The tracks shown with pending changes, whose rows change again when the changes go.
    shown_modified: RefCell<BTreeSet<usize>>,
    /// The tracks the table lists, row by row, and the row of each track listed.
    listed: RefCell<Vec<usize>>,
    row_of: RefCell<HashMap<usize, usize>>,
    poll_timer: Timer,
    dialogs: Box<dyn Dialogs>,
    departure: RefCell<Option<Departure>>,
    /// The genres to suggest, and the state of the library they were read from.
    genres: RefCell<Vec<String>>,
    genres_read_from: Cell<Option<GenreSource>>,
    /// A tag removal that waits for the user's answer.
    removal: Cell<Option<Removal>>,
    /// The folders, albums and artists the sidebar lists, by their place in it.
    sources: RefCell<Sources>,
    /// The cover drawn last, so that a selection shown again does not decode it again.
    drawn_cover: RefCell<Option<(Arc<[u8]>, Image)>>,
    /// The album covers of the sidebar, drawn small on a thread of their own.
    thumbnails: RefCell<Thumbnails>,
    thumbnail_timer: Timer,
    /// The track marked as playing in the table.
    shown_playing: Cell<Option<usize>>,
    /// The playing track's waveform, read on a thread of its own.
    waveform: RefCell<WaveformDrawing>,
    /// The spectrum of the single selected track, read on a thread of its own.
    spectrum: RefCell<SpectrumDrawing>,
    spectrum_timer: Timer,
    /// The preferences handed to `keep` last.
    kept: Cell<Preferences>,
    keep: Box<dyn Fn(&Preferences)>,
}

/// The track whose spectrum shows or is being read.
#[derive(Default)]
struct SpectrumDrawing {
    track: Option<usize>,
    reading: Option<Receiver<Option<DrawnSpectrum>>>,
}

/// A spectrum's pixels, the highest frequency its file can hold and the highest it holds, in
/// hertz.
struct DrawnSpectrum {
    pixels: SharedPixelBuffer<Rgba8Pixel>,
    nyquist: u32,
    highest: Option<u32>,
}

/// The track whose waveform shows or is being read.
#[derive(Default)]
struct WaveformDrawing {
    track: Option<usize>,
    reading: Option<Receiver<Option<WaveformBars>>>,
}

/// A waveform's bars: the whole sound, its bass and its treble.
struct WaveformBars {
    sound: SharedPixelBuffer<Rgba8Pixel>,
    bass: SharedPixelBuffer<Rgba8Pixel>,
    treble: SharedPixelBuffer<Rgba8Pixel>,
}

/// Album covers drawn small, by the address of their shared bytes, and those being drawn.
#[derive(Default)]
struct Thumbnails {
    drawn: HashMap<usize, (Arc<[u8]>, Image)>,
    drawing: Option<Receiver<Thumbnail>>,
}

/// A cover's bytes and its pixels made small.
type Thumbnail = (Arc<[u8]>, SharedPixelBuffer<Rgba8Pixel>);

impl Thumbnails {
    fn get(&self, cover: &tags::Cover) -> Option<Image> {
        self.drawn
            .get(&cover_key(cover))
            .map(|(_, image)| image.clone())
    }
}

fn cover_key(cover: &tags::Cover) -> usize {
    Arc::as_ptr(&cover.data).cast::<u8>() as usize
}

/// The sources the sidebar lists, and the state of the library they were read from.
#[derive(Default)]
struct Sources {
    folders: Vec<PathBuf>,
    albums: Vec<AlbumKey>,
    album_covers: Vec<Option<tags::Cover>>,
    artists: Vec<String>,
    read_from: Option<GenreSource>,
}

/// What changes the genres to suggest: tracks found, and files saved.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct GenreSource {
    tracks: usize,
    status: ScanStatus,
    saving: bool,
}

/// What removes a tag once the user agrees.
#[derive(Debug, Clone, Copy)]
enum Removal {
    /// A version choice of the inspector's Tag format section.
    Choice(VersionChoice),
    /// A save while the write policy never writes ID3v1; refused, the files keep theirs.
    Save,
}

/// Quitting, held up by pending changes.
enum Departure {
    /// The window asks what to do with them.
    Asking,
    /// Waits for the running save to end, then saves what is left first when `save` holds.
    AfterSave { save: bool },
    /// Quits once this save has written every file.
    Saving,
}

fn run(bridge: &Rc<Bridge>, command: generated::Command) {
    let command = match command {
        generated::Command::ToggleSidebar => Command::ToggleSidebar,
        generated::Command::ToggleInspector => Command::ToggleInspector,
        generated::Command::ToggleDeveloperMode => Command::ToggleDeveloperMode,
        generated::Command::StopScan => Command::StopScan,
        generated::Command::ResetColumns => Command::ResetColumns,
        generated::Command::SelectAll => Command::SelectAll,
        generated::Command::SelectPrevious => Command::MoveSelection(Step::Up),
        generated::Command::SelectNext => Command::MoveSelection(Step::Down),
        generated::Command::ExtendSelectionUp => Command::ExtendSelection(Step::Up),
        generated::Command::ExtendSelectionDown => Command::ExtendSelection(Step::Down),
        generated::Command::Save => return save(bridge),
        generated::Command::Undo => Command::Undo,
        generated::Command::Redo => Command::Redo,
        generated::Command::Revert => Command::Revert,
        generated::Command::NumberTracks => Command::NumberTracks,
        generated::Command::SelectAlbum => Command::SelectAlbum,
        generated::Command::PlayPause => Command::PlayPause,
        generated::Command::PlayNext => Command::PlayNext,
        generated::Command::PlayPrevious => Command::PlayPrevious,
        generated::Command::OpenFolder => match bridge.dialogs.pick_folder() {
            Some(folder) => Command::OpenFolder(folder),
            None => return,
        },
        generated::Command::OpenFiles => {
            let files = bridge.dialogs.pick_files();
            if files.is_empty() {
                return;
            }
            Command::OpenFiles(files)
        }
    };
    execute(bridge, command);
}

fn change_policy(bridge: &Rc<Bridge>, change: impl FnOnce(&mut WritePolicy)) {
    let mut policy = bridge.engine.borrow().preferences().writing;
    change(&mut policy);
    execute(bridge, Command::SetWritePolicy(policy));
}

/// Runs the command chosen in the palette, as its menu item or its control would.
fn run_palette(bridge: &Rc<Bridge>, action: PaletteAction) {
    use generated::Command as Window;
    let Some(window) = bridge.window.upgrade() else {
        return;
    };
    let id3v2 = |version| choose_version(bridge, VersionChoice::Id3v2(version));
    let id3v1 = |version| choose_version(bridge, VersionChoice::Id3v1(version));
    let column = |column| execute(bridge, Command::ToggleColumn(column));
    match action {
        PaletteAction::OpenFolder => run(bridge, Window::OpenFolder),
        PaletteAction::OpenFiles => run(bridge, Window::OpenFiles),
        PaletteAction::Save => run(bridge, Window::Save),
        PaletteAction::Settings => window.set_settings_open(true),
        PaletteAction::Undo => run(bridge, Window::Undo),
        PaletteAction::Redo => run(bridge, Window::Redo),
        PaletteAction::Find => window.invoke_focus_filter(),
        PaletteAction::SelectAll => run(bridge, Window::SelectAll),
        PaletteAction::SelectAlbum => run(bridge, Window::SelectAlbum),
        PaletteAction::NumberTracks => run(bridge, Window::NumberTracks),
        PaletteAction::Revert => run(bridge, Window::Revert),
        PaletteAction::PlayPause => run(bridge, Window::PlayPause),
        PaletteAction::NextTrack => run(bridge, Window::PlayNext),
        PaletteAction::PreviousTrack => run(bridge, Window::PlayPrevious),
        PaletteAction::ToggleSidebar => run(bridge, Window::ToggleSidebar),
        PaletteAction::ToggleInspector => run(bridge, Window::ToggleInspector),
        PaletteAction::ToggleDeveloperMode => run(bridge, Window::ToggleDeveloperMode),
        PaletteAction::ResetColumns => run(bridge, Window::ResetColumns),
        PaletteAction::ToggleArtist => column(Column::Artist),
        PaletteAction::ToggleAlbum => column(Column::Album),
        PaletteAction::ToggleYear => column(Column::Year),
        PaletteAction::ToggleGenre => column(Column::Genre),
        PaletteAction::ToggleTime => column(Column::Time),
        PaletteAction::ToggleBitrate => column(Column::Bitrate),
        PaletteAction::ToggleTags => column(Column::Tags),
        PaletteAction::ToggleFile => column(Column::File),
        PaletteAction::ToggleFolder => column(Column::Folder),
        PaletteAction::WriteId3v24 => id3v2(Some(Id3v2Version::V2_4)),
        PaletteAction::WriteId3v23 => id3v2(Some(Id3v2Version::V2_3)),
        PaletteAction::WriteId3v22 => id3v2(Some(Id3v2Version::V2_2)),
        PaletteAction::RemoveId3v2 => id3v2(None),
        PaletteAction::WriteId3v11 => id3v1(Some(Id3v1Version::V1_1)),
        PaletteAction::WriteId3v10 => id3v1(Some(Id3v1Version::V1_0)),
        PaletteAction::RemoveId3v1 => id3v1(None),
        PaletteAction::DefaultId3v24 => {
            change_policy(bridge, |policy| policy.id3v2 = Id3v2Version::V2_4);
        }
        PaletteAction::DefaultId3v23 => {
            change_policy(bridge, |policy| policy.id3v2 = Id3v2Version::V2_3);
        }
        PaletteAction::Id3v1Keep => {
            change_policy(bridge, |policy| policy.id3v1 = tags::Id3v1Policy::Keep);
        }
        PaletteAction::Id3v1Always => {
            change_policy(bridge, |policy| policy.id3v1 = tags::Id3v1Policy::Always);
        }
        PaletteAction::Id3v1Never => {
            change_policy(bridge, |policy| policy.id3v1 = tags::Id3v1Policy::Never);
        }
    }
}

/// Chooses a tag version for the selected tracks, after asking first when the choice removes a
/// tag some of their files have.
fn choose_version(bridge: &Rc<Bridge>, choice: VersionChoice) {
    let tag = match choice {
        VersionChoice::Id3v2(None) => RemovedTag::Id3v2,
        VersionChoice::Id3v1(None) => RemovedTag::Id3v1,
        _ => return execute(bridge, Command::ChooseVersion(choice)),
    };
    let files = bridge.files_losing(tag);
    if !confirm_removal(bridge, tag, files, Removal::Choice(choice)) {
        execute(bridge, Command::ChooseVersion(choice));
    }
}

/// Saves, after asking first when the write policy would strip files of their ID3v1 tag.
fn save(bridge: &Rc<Bridge>) {
    let files: Vec<String> = {
        let engine = bridge.engine.borrow();
        let tracks = &engine.library().tracks;
        engine
            .losing_id3v1_to_policy()
            .into_iter()
            .filter_map(|track| {
                let name = tracks.get(track)?.path.file_name()?;
                Some(name.to_string_lossy().into_owned())
            })
            .collect()
    };
    if !confirm_removal(bridge, RemovedTag::Id3v1, files, Removal::Save) {
        execute(bridge, Command::Save);
    }
}

/// Asks before `removal` strips `tag` from `files`, and says whether it asked: with no files to
/// lose it, there is nothing to ask.
fn confirm_removal(
    bridge: &Rc<Bridge>,
    tag: RemovedTag,
    files: Vec<String>,
    removal: Removal,
) -> bool {
    let Some(window) = bridge.window.upgrade().filter(|_| !files.is_empty()) else {
        return false;
    };
    window.set_removal(TagRemoval {
        tag,
        count: count(files.len()),
        others: count(files.len().saturating_sub(LISTED_FILES)),
        files: ModelRc::new(VecModel::from(
            files
                .into_iter()
                .take(LISTED_FILES)
                .map(SharedString::from)
                .collect::<Vec<_>>(),
        )),
    });
    bridge.removal.set(Some(removal));
    window.set_confirming_removal(true);
    true
}

fn ask(bridge: &Rc<Bridge>) {
    bridge.departure.replace(Some(Departure::Asking));
    bridge.show();
}

fn answer(bridge: &Rc<Bridge>, choice: UnsavedChoice) {
    let Some(Departure::Asking) = bridge.departure.take() else {
        return;
    };
    let saving = bridge.engine.borrow().saving().is_some();
    match choice {
        UnsavedChoice::Cancel => bridge.show(),
        UnsavedChoice::Save | UnsavedChoice::Discard if saving => {
            let save = choice == UnsavedChoice::Save;
            bridge
                .departure
                .replace(Some(Departure::AfterSave { save }));
            bridge.show();
        }
        UnsavedChoice::Save => save_then_quit(bridge),
        UnsavedChoice::Discard => quit(bridge),
    }
}

/// Quitting asks nothing more: files the write policy would strip of their ID3v1 tag keep it.
fn save_then_quit(bridge: &Rc<Bridge>) {
    execute(bridge, Command::SaveKeepingId3v1);
    let (saving, failed) = {
        let engine = bridge.engine.borrow();
        (
            engine.saving().is_some(),
            !engine.save_failures().is_empty(),
        )
    };
    if saving {
        bridge.departure.replace(Some(Departure::Saving));
    } else if !failed {
        quit(bridge);
    }
}

/// Goes on with a departure that waited for the save, once it has ended. A file it could not
/// write keeps the user where they are, with the failure in the status bar.
fn after_save(bridge: &Rc<Bridge>) {
    match bridge.departure.take() {
        Some(Departure::AfterSave { save: true }) => save_then_quit(bridge),
        Some(Departure::AfterSave { save: false }) => quit(bridge),
        Some(Departure::Saving) => {
            if bridge.engine.borrow().save_failures().is_empty() {
                quit(bridge);
            }
        }
        waiting => {
            bridge.departure.replace(waiting);
        }
    }
}

fn quit(bridge: &Rc<Bridge>) {
    bridge.keep_window_size();
    if let Some(window) = bridge.window.upgrade() {
        window.hide().ok();
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
    } else if let Some(window) = bridge.window.upgrade() {
        show_playback(&window, &bridge.engine.borrow());
    }
    bridge.take_waveform();
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
        engine.library().status == ScanStatus::Scanning
            || engine.saving().is_some()
            || engine.playback().playing()
    }

    /// How long the playing track lasts.
    fn playing_duration(&self) -> Option<Duration> {
        let engine = self.engine.borrow();
        let track = engine.library().tracks.get(engine.playback().track?)?;
        track.metadata.as_ref().ok()?.audio.duration
    }

    /// The names of the selected files that have `tag` and would keep it when saved.
    fn files_losing(&self, tag: RemovedTag) -> Vec<String> {
        let engine = self.engine.borrow();
        let tracks = &engine.library().tracks;
        engine
            .selection()
            .iter()
            .filter_map(|index| {
                let track = tracks.get(index)?;
                let formats = &track.metadata.as_ref().ok()?.formats;
                let versions = engine.edits().versions(tracks, index)?;
                let (has, kept) = match tag {
                    RemovedTag::Id3v1 => (
                        formats
                            .iter()
                            .any(|format| matches!(format, tags::TagFormat::Id3v1(_))),
                        versions.id3v1.is_some(),
                    ),
                    RemovedTag::Id3v2 => (
                        formats
                            .iter()
                            .any(|format| matches!(format, tags::TagFormat::Id3v2(_))),
                        versions.id3v2.is_some(),
                    ),
                };
                let name = track.path.file_name()?.to_string_lossy().into_owned();
                (has && kept).then_some(name)
            })
            .collect()
    }

    fn has_changes(&self) -> bool {
        self.engine.borrow().edits().modified_count() > 0
    }

    fn show(&self) {
        let Some(window) = self.window.upgrade() else {
            return;
        };
        let engine = self.engine.borrow();
        self.read_genres(&engine);
        self.show_sources(&window, &engine);
        show_view(&window, engine.view());
        show_writing(&window, engine.preferences().writing);
        show_sort(&window, engine.sort());
        show_library(&window, engine.library());
        self.show_tracks(&window, &engine);
        self.show_selection(&window, engine.selection());
        show_inspection(&window, engine.library(), engine.inspection(), |cover| {
            self.cover_image(cover)
        });
        show_saving(&window, &engine);
        show_playback(&window, &engine);
        self.read_waveform(&window, &engine);
        self.read_spectrum(&window, &engine);
        self.show_departure(&window, &engine);
        let preferences = engine.preferences();
        if preferences != self.kept.get() {
            self.kept.set(preferences);
            (self.keep)(&preferences);
        }
    }

    /// Remembers the window's size for the next launch, before it closes.
    fn keep_window_size(&self) {
        let Some(window) = self.window.upgrade() else {
            return;
        };
        let window = window.window();
        let size = window.size().to_logical(window.scale_factor());
        let size = WindowSize {
            width: size.width.round() as u32,
            height: size.height.round() as u32,
        };
        self.engine
            .borrow_mut()
            .execute(Command::ResizeWindow(size));
        self.show();
    }

    /// Lists the sidebar's sources, again when the library changed, and marks the one shown.
    fn show_sources(&self, window: &AppWindow, engine: &Engine) {
        let library = engine.library();
        let source = GenreSource {
            tracks: library.tracks.len(),
            status: library.status,
            saving: engine.saving().is_some(),
        };
        let mut sources = self.sources.borrow_mut();
        if sources.read_from != Some(source) {
            sources.read_from = Some(source);
            let groups = engine.groups();
            sources.folders = library.roots.clone();
            sources.albums = groups
                .albums
                .iter()
                .map(|album| album.key.clone())
                .collect();
            sources.album_covers = groups
                .albums
                .iter()
                .map(|album| album.cover.clone())
                .collect();
            sources.artists = groups
                .artists
                .iter()
                .map(|(artist, _)| artist.clone())
                .collect();
            let folders: Vec<SidebarItem> = library
                .roots
                .iter()
                .enumerate()
                .map(|(index, folder)| SidebarItem {
                    kind: SourceKind::Folder,
                    index: count(index),
                    label: display_folder(folder).into(),
                    count: count(
                        library
                            .tracks
                            .iter()
                            .filter(|track| track.path.starts_with(folder))
                            .count(),
                    ),
                    ..SidebarItem::default()
                })
                .collect();
            let thumbnails = self.thumbnails.borrow();
            let albums: Vec<SidebarItem> = groups
                .albums
                .iter()
                .enumerate()
                .map(|(index, album)| {
                    let cover = album.cover.as_ref().and_then(|cover| thumbnails.get(cover));
                    SidebarItem {
                        kind: SourceKind::Album,
                        index: count(index),
                        label: album.key.title.as_str().into(),
                        count: count(album.tracks),
                        swatch: swatch(&album.key),
                        has_cover: cover.is_some(),
                        cover: cover.unwrap_or_default(),
                    }
                })
                .collect();
            drop(thumbnails);
            let artists: Vec<SidebarItem> = groups
                .artists
                .iter()
                .enumerate()
                .map(|(index, (artist, tracks))| SidebarItem {
                    kind: SourceKind::Artist,
                    index: count(index),
                    label: artist.as_str().into(),
                    count: count(*tracks),
                    ..SidebarItem::default()
                })
                .collect();
            let first: Vec<SidebarItem> = albums.iter().take(FIRST_ALBUMS).cloned().collect();
            window.set_folder_sources(ModelRc::new(VecModel::from(folders)));
            window.set_album_sources(ModelRc::new(VecModel::from(albums)));
            window.set_first_album_sources(ModelRc::new(VecModel::from(first)));
            window.set_artist_sources(ModelRc::new(VecModel::from(artists)));
            self.draw_thumbnails(&sources.album_covers);
        }

        let unreadable = library
            .tracks
            .iter()
            .filter(|track| track.metadata.is_err())
            .count();
        let library_items = [
            (SourceKind::AllTracks, library.tracks.len()),
            (SourceKind::RecentlyChanged, engine.changed().len()),
            (SourceKind::Unreadable, unreadable),
        ]
        .map(|(kind, tracks)| SidebarItem {
            kind,
            count: count(tracks),
            ..SidebarItem::default()
        });
        let shown_items = window.get_library_sources();
        if shown_items.row_count() != library_items.len()
            || library_items
                .iter()
                .enumerate()
                .any(|(row, item)| shown_items.row_data(row).as_ref() != Some(item))
        {
            window.set_library_sources(ModelRc::new(VecModel::from(library_items.to_vec())));
        }

        let place = |found: Option<usize>| found.map_or(-1, count);
        let (kind, index, label) = match engine.source() {
            Source::AllTracks => (SourceKind::AllTracks, 0, String::new()),
            Source::RecentlyChanged => (SourceKind::RecentlyChanged, 0, String::new()),
            Source::Unreadable => (SourceKind::Unreadable, 0, String::new()),
            Source::Folder(folder) => (
                SourceKind::Folder,
                place(sources.folders.iter().position(|shown| shown == folder)),
                display_folder(folder),
            ),
            Source::Album(album) => (
                SourceKind::Album,
                place(sources.albums.iter().position(|shown| shown == album)),
                album.title.clone(),
            ),
            Source::Artist(artist) => (
                SourceKind::Artist,
                place(sources.artists.iter().position(|shown| shown == artist)),
                artist.clone(),
            ),
        };
        window.set_shown_kind(kind);
        window.set_shown_index(index);
        window.set_shown_label(label.into());
    }

    /// Reads the waveform of a track that starts playing, on a thread of its own.
    fn read_waveform(&self, window: &AppWindow, engine: &Engine) {
        let playing = engine.playback().track;
        let mut drawing = self.waveform.borrow_mut();
        if drawing.track == playing {
            return;
        }
        drawing.track = playing;
        drawing.reading = None;
        window.set_player_has_waveform(false);
        let Some(path) = playing
            .and_then(|track| engine.library().tracks.get(track))
            .map(|track| track.path.clone())
        else {
            return;
        };
        let (sender, reading) = std::sync::mpsc::channel();
        let spawned = std::thread::Builder::new()
            .name("waveform".to_string())
            .spawn(move || {
                let bars = colophon_player::Waveform::read(&path).ok().map(|waveform| {
                    let peaks = waveform.peaks(WAVEFORM_BARS);
                    WaveformBars {
                        sound: waveform_bars(&peaks, |peak| (peak.low, peak.high)),
                        bass: waveform_bars(&peaks, |peak| (-peak.bass, peak.bass)),
                        treble: waveform_bars(&peaks, |peak| (-peak.treble, peak.treble)),
                    }
                });
                let _ = sender.send(bars);
            });
        if spawned.is_ok() {
            drawing.reading = Some(reading);
        }
    }

    /// Reads the spectrum of a track selected alone, on a thread of its own.
    fn read_spectrum(&self, window: &AppWindow, engine: &Engine) {
        let alone = match engine.inspection() {
            Inspection::Tracks(summary) if summary.count == 1 && summary.unreadable == 0 => {
                engine.selection().iter().next()
            }
            _ => None,
        };
        let mut drawing = self.spectrum.borrow_mut();
        if drawing.track == alone {
            return;
        }
        drawing.track = alone;
        drawing.reading = None;
        window.set_has_spectrum(false);
        let Some(path) = alone
            .and_then(|track| engine.library().tracks.get(track))
            .map(|track| track.path.clone())
        else {
            return;
        };
        let (sender, reading) = std::sync::mpsc::channel();
        let spawned = std::thread::Builder::new()
            .name("spectrum".to_string())
            .spawn(move || {
                let drawn = colophon_player::Spectrum::read(&path, SPECTRUM_COLUMNS, SPECTRUM_ROWS)
                    .ok()
                    .map(|spectrum| DrawnSpectrum {
                        pixels: spectrum_pixels(&spectrum),
                        nyquist: spectrum.nyquist,
                        highest: spectrum.highest,
                    });
                let _ = sender.send(drawn);
            });
        if spawned.is_err() {
            return;
        }
        drawing.reading = Some(reading);
        let me = self.me.clone();
        self.spectrum_timer
            .start(TimerMode::Repeated, POLL_INTERVAL, move || {
                if let Some(bridge) = me.upgrade() {
                    bridge.take_spectrum();
                }
            });
    }

    /// Shows the spectrum once read.
    fn take_spectrum(&self) {
        let mut drawing = self.spectrum.borrow_mut();
        let Some(reading) = &drawing.reading else {
            self.spectrum_timer.stop();
            return;
        };
        let drawn = match reading.try_recv() {
            Ok(drawn) => drawn,
            Err(TryRecvError::Empty) => return,
            Err(TryRecvError::Disconnected) => None,
        };
        drawing.reading = None;
        self.spectrum_timer.stop();
        let (Some(window), Some(drawn)) = (self.window.upgrade(), drawn) else {
            return;
        };
        window.set_spectrum(TrackSpectrum {
            image: Image::from_rgba8(drawn.pixels),
            nyquist: kilohertz(drawn.nyquist),
            holds_sound: drawn.highest.is_some(),
            highest: kilohertz(drawn.highest.unwrap_or_default()),
        });
        window.set_has_spectrum(true);
    }

    /// Shows the waveform once read.
    fn take_waveform(&self) {
        let mut drawing = self.waveform.borrow_mut();
        let Some(reading) = &drawing.reading else {
            return;
        };
        let bars = match reading.try_recv() {
            Ok(bars) => bars,
            Err(TryRecvError::Empty) => return,
            Err(TryRecvError::Disconnected) => None,
        };
        drawing.reading = None;
        if let (Some(window), Some(bars)) = (self.window.upgrade(), bars) {
            window.set_player_waveform(Image::from_rgba8(bars.sound));
            window.set_player_bass(Image::from_rgba8(bars.bass));
            window.set_player_treble(Image::from_rgba8(bars.treble));
            window.set_player_has_waveform(true);
        }
    }

    /// Draws on a thread of their own the album covers not drawn yet, then shows them as they come.
    fn draw_thumbnails(&self, covers: &[Option<tags::Cover>]) {
        let mut thumbnails = self.thumbnails.borrow_mut();
        if thumbnails.drawing.is_some() {
            return;
        }
        let mut wanted: HashMap<usize, Arc<[u8]>> = HashMap::new();
        for cover in covers.iter().flatten() {
            let key = cover_key(cover);
            if !thumbnails.drawn.contains_key(&key) {
                wanted.insert(key, Arc::clone(&cover.data));
            }
        }
        if wanted.is_empty() {
            return;
        }
        let (sender, drawn) = std::sync::mpsc::channel();
        let spawned = std::thread::Builder::new()
            .name("album covers".to_string())
            .spawn(move || {
                for data in wanted.into_values() {
                    let Some(buffer) = shrink(&data, THUMBNAIL_PIXELS) else {
                        continue;
                    };
                    if sender.send((data, buffer)).is_err() {
                        return;
                    }
                }
            });
        if spawned.is_err() {
            return;
        }
        thumbnails.drawing = Some(drawn);
        let me = self.me.clone();
        self.thumbnail_timer
            .start(TimerMode::Repeated, POLL_INTERVAL, move || {
                if let Some(bridge) = me.upgrade() {
                    bridge.take_thumbnails();
                }
            });
    }

    /// Takes in the album covers drawn since the last call, and puts them in the sidebar.
    fn take_thumbnails(&self) {
        let mut thumbnails = self.thumbnails.borrow_mut();
        let Some(drawing) = &thumbnails.drawing else {
            return;
        };
        let mut drawn = Vec::new();
        let finished = loop {
            match drawing.try_recv() {
                Ok(thumbnail) => drawn.push(thumbnail),
                Err(TryRecvError::Empty) => break false,
                Err(TryRecvError::Disconnected) => break true,
            }
        };
        for (data, buffer) in drawn {
            let key = Arc::as_ptr(&data).cast::<u8>() as usize;
            thumbnails
                .drawn
                .insert(key, (data, Image::from_rgba8(buffer)));
        }
        if finished {
            thumbnails.drawing = None;
            self.thumbnail_timer.stop();
        }
        let Some(window) = self.window.upgrade() else {
            return;
        };
        let sources = self.sources.borrow();
        for model in [window.get_album_sources(), window.get_first_album_sources()] {
            for row in 0..model.row_count() {
                let Some(item) = model.row_data(row) else {
                    continue;
                };
                let cover = usize::try_from(item.index)
                    .ok()
                    .and_then(|index| sources.album_covers.get(index))
                    .and_then(Option::as_ref)
                    .and_then(|cover| thumbnails.get(cover));
                if let Some(cover) = cover.filter(|_| !item.has_cover) {
                    model.set_row_data(
                        row,
                        SidebarItem {
                            cover,
                            has_cover: true,
                            ..item
                        },
                    );
                }
            }
        }
    }

    fn cover_image(&self, cover: &tags::Cover) -> Image {
        if let Some((data, image)) = &*self.drawn_cover.borrow()
            && Arc::ptr_eq(data, &cover.data)
        {
            return image.clone();
        }
        let image = decode_cover(&cover.data, COVER_PIXELS).unwrap_or_default();
        self.drawn_cover
            .replace(Some((Arc::clone(&cover.data), image.clone())));
        image
    }

    fn read_genres(&self, engine: &Engine) {
        let source = Some(GenreSource {
            tracks: engine.library().tracks.len(),
            status: engine.library().status,
            saving: engine.saving().is_some(),
        });
        if self.genres_read_from.replace(source) != source {
            self.genres.replace(engine.genres());
        }
    }

    /// Shows the unsaved changes dialog while it asks, naming the first modified tracks as the
    /// table titles them.
    fn show_departure(&self, window: &AppWindow, engine: &Engine) {
        let departure = self.departure.borrow();
        let Some(Departure::Asking) = departure.as_ref() else {
            window.set_asking_to_save(false);
            return;
        };
        let titles: Vec<SharedString> = engine
            .edits()
            .modified()
            .take(NAMED_TRACKS)
            .filter_map(|(track, pending)| {
                Some(track_row(engine.library().tracks.get(track)?, Some(pending)).title)
            })
            .collect();
        window.set_unsaved_titles(ModelRc::new(VecModel::from(titles)));
        window.set_asking_to_save(true);
    }

    /// Marks the selected rows, touching only the rows that change.
    /// The track a row of the table shows.
    fn track_at(&self, row: i32) -> Option<usize> {
        let row = usize::try_from(row).ok()?;
        self.listed.borrow().get(row).copied()
    }

    /// Marks the selected rows, touching only the rows that change.
    fn show_selection(&self, window: &AppWindow, selection: &Selection) {
        let listed = self.listed.borrow();
        let is_selected = |row: usize| {
            listed
                .get(row)
                .is_some_and(|track| selection.contains(*track))
        };
        for index in 0..self.tracks.row_count() {
            let Some(row) = self.tracks.row_data(index) else {
                continue;
            };
            let marks = SelectionMarks::of(index, is_selected);
            if SelectionMarks::from(&row) != marks {
                self.tracks.set_row_data(index, marks.on(row));
            }
        }
        let focused = selection
            .focus()
            .and_then(|track| self.row_of.borrow().get(&track).copied());
        window.set_focused_row(focused.map_or(-1, count));
        window.set_selected_count(count(selection.len()));
    }

    /// Lists the tracks the engine lists, adding rows when it only lists more, and redraws those
    /// whose pending changes came or went.
    fn show_tracks(&self, window: &AppWindow, engine: &Engine) {
        let library = engine.library();
        let edits = engine.edits();
        let row = |track: usize| {
            library
                .tracks
                .get(track)
                .map(|listed| track_row(listed, edits.pending(track)))
        };
        let mut listed = self.listed.borrow_mut();
        let mut longest = self.longest.borrow_mut();
        if engine.listed() != listed.as_slice() {
            let more = engine.listed().starts_with(&listed);
            if !more {
                listed.clear();
                *longest = TrackRow::default();
                self.tracks.clear();
            }
            let added = &engine.listed()[listed.len()..];
            let rows: Vec<TrackRow> = added.iter().filter_map(|track| row(*track)).collect();
            for row in &rows {
                keep_longest(&mut longest, row);
            }
            self.tracks.extend(rows);
            listed.extend_from_slice(added);
            let mut row_of = self.row_of.borrow_mut();
            if !more {
                row_of.clear();
            }
            for (place, track) in listed.iter().enumerate().skip(row_of.len()) {
                row_of.insert(*track, place);
            }
        }

        let modified: BTreeSet<usize> = edits.modified().map(|(track, _)| track).collect();
        let changed = self.shown_modified.replace(modified.clone());
        let row_of = self.row_of.borrow();
        for track in changed.union(&modified) {
            let (Some(place), Some(new)) = (row_of.get(track).copied(), row(*track)) else {
                continue;
            };
            let Some(old) = self.tracks.row_data(place) else {
                continue;
            };
            let new = TrackRow {
                selected: old.selected,
                selected_above: old.selected_above,
                selected_below: old.selected_below,
                ..new
            };
            if new != old {
                keep_longest(&mut longest, &new);
                self.tracks.set_row_data(place, new);
            }
        }
        window.set_longest(longest.clone());
        window.set_modified_count(count(edits.modified_count()));

        // The rows of the track that played and of the one that plays; rows listed again lose
        // their mark, which this puts back.
        let playing = engine.playback().track;
        let played = self.shown_playing.replace(playing);
        for track in [played, playing].into_iter().flatten() {
            let Some(place) = row_of.get(&track).copied() else {
                continue;
            };
            let Some(row) = self.tracks.row_data(place) else {
                continue;
            };
            let marked = Some(track) == playing;
            if row.playing != marked {
                self.tracks.set_row_data(
                    place,
                    TrackRow {
                        playing: marked,
                        ..row
                    },
                );
            }
        }
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

fn show_inspection(
    window: &AppWindow,
    library: &Library,
    inspection: Inspection<'_>,
    cover_image: impl Fn(&tags::Cover) -> Image,
) {
    let state = match inspection {
        _ if library.roots.is_empty() => InspectorState::Empty,
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
            let cover = match &summary.cover {
                Shared::Same(cover) => cover_image(cover),
                Shared::Empty | Shared::Mixed => Image::default(),
            };
            window.set_inspected_tracks(InspectedTracks {
                cover,
                ..inspected_tracks(&summary)
            });
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
        cover_state: match summary.cover {
            Shared::Empty => CoverState::None,
            Shared::Same(_) => CoverState::Shared,
            Shared::Mixed => CoverState::Mixed,
        },
        cover_modified: modified(Field::Cover),
        cover: Image::default(),
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
        disc: field(&summary.disc, modified(Field::Disc), ToString::to_string),
        disc_total: field(
            &summary.disc_total,
            modified(Field::DiscTotal),
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
        converted: count(summary.converted),
        id3v2_choice: place_of_versions(&summary.versions, &ID3V2_CHOICES, |versions| {
            versions.id3v2
        }),
        id3v1_choice: place_of_versions(&summary.versions, &ID3V1_CHOICES, |versions| {
            versions.id3v1
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

/// The choice of the Tag format section at `index`, if there is one.
fn choice<T: Copy>(choices: &[T], index: i32) -> Option<T> {
    usize::try_from(index)
        .ok()
        .and_then(|index| choices.get(index))
        .copied()
}

/// Where the version the tracks share stands among the choices, -1 while they have several.
fn place_of_versions<T: PartialEq>(
    versions: &Shared<tags::TagVersions>,
    choices: &[T],
    version: impl Fn(&tags::TagVersions) -> T,
) -> i32 {
    let Shared::Same(versions) = versions else {
        return -1;
    };
    let version = version(versions);
    choices
        .iter()
        .position(|choice| *choice == version)
        .map_or(-1, count)
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

/// The size covers are decoded at: the inspector draws them at 64 points, twice that on a sharp
/// screen.
const COVER_PIXELS: u32 = 128;

/// The bars of the player's waveform, and their size in pixels: a bar and a gap.
const WAVEFORM_BARS: usize = 240;
const BAR_WIDTH: u32 = 2;
const BAR_STRIDE: u32 = 3;
const WAVEFORM_HEIGHT: u32 = 72;

/// White bars on transparency, one per peak from the lowest to the highest value `extent` gives
/// it, that the window tints.
fn waveform_bars(
    peaks: &[colophon_player::Peak],
    extent: impl Fn(&colophon_player::Peak) -> (f32, f32),
) -> SharedPixelBuffer<Rgba8Pixel> {
    let width = u32::try_from(peaks.len()).unwrap_or(0) * BAR_STRIDE;
    let mut buffer = SharedPixelBuffer::<Rgba8Pixel>::new(width.max(1), WAVEFORM_HEIGHT);
    let middle = WAVEFORM_HEIGHT as f32 / 2.0;
    let row_length = buffer.width() as usize;
    let pixels = buffer.make_mut_slice();
    for (bar, peak) in peaks.iter().enumerate() {
        let (low, high) = extent(peak);
        // At least a line, so that silence still shows where the track is.
        let top = (middle - high.clamp(0.0, 1.0) * middle).min(middle - 1.0) as usize;
        let bottom = (middle - low.clamp(-1.0, 0.0) * middle).max(middle + 1.0) as usize;
        let left = bar * BAR_STRIDE as usize;
        for row in top..bottom.min(WAVEFORM_HEIGHT as usize) {
            let start = row * row_length + left;
            pixels[start..start + BAR_WIDTH as usize].fill(Rgba8Pixel {
                r: 255,
                g: 255,
                b: 255,
                a: 255,
            });
        }
    }
    buffer
}

/// The inspector's spectrum, in pixels: twice the 288 by 96 points it is drawn at.
const SPECTRUM_COLUMNS: usize = 576;
const SPECTRUM_ROWS: usize = 192;

/// The magma colour map, dark for silence to pale yellow for the loudest, as Spek draws spectra.
const MAGMA: [(f32, [u8; 3]); 6] = [
    (0.0, [0x0b, 0x0b, 0x10]),
    (0.3, [0x3b, 0x0f, 0x70]),
    (0.55, [0x8c, 0x29, 0x81]),
    (0.75, [0xde, 0x49, 0x68]),
    (0.9, [0xfe, 0x9f, 0x6d]),
    (1.0, [0xfc, 0xfd, 0xbf]),
];

fn magma(level: f32) -> Rgba8Pixel {
    let level = level.clamp(0.0, 1.0);
    let upper = MAGMA
        .iter()
        .position(|(stop, _)| *stop >= level)
        .unwrap_or(MAGMA.len() - 1)
        .max(1);
    let (from, low) = MAGMA[upper - 1];
    let (to, high) = MAGMA[upper];
    let mix = ((level - from) / (to - from)).clamp(0.0, 1.0);
    let channel =
        |at: usize| (f32::from(low[at]) + (f32::from(high[at]) - f32::from(low[at])) * mix) as u8;
    Rgba8Pixel {
        r: channel(0),
        g: channel(1),
        b: channel(2),
        a: 255,
    }
}

/// A spectrum drawn with the lowest frequencies at the bottom.
fn spectrum_pixels(spectrum: &colophon_player::Spectrum) -> SharedPixelBuffer<Rgba8Pixel> {
    let width = u32::try_from(spectrum.columns).unwrap_or(1).max(1);
    let height = u32::try_from(spectrum.rows).unwrap_or(1).max(1);
    let mut buffer = SharedPixelBuffer::<Rgba8Pixel>::new(width, height);
    let pixels = buffer.make_mut_slice();
    for row in 0..spectrum.rows {
        for column in 0..spectrum.columns {
            let level = spectrum.levels[row * spectrum.columns + column];
            pixels[(spectrum.rows - 1 - row) * spectrum.columns + column] = magma(level);
        }
    }
    buffer
}

/// A frequency in hertz as tenths of kilohertz, rounded.
fn kilohertz(hertz: u32) -> Kilohertz {
    let tenths = (hertz + 50) / 100;
    Kilohertz {
        whole: number(tenths / 10),
        tenth: number(tenths % 10),
    }
}

/// The size album covers are decoded at for the sidebar, which draws them at 18 points.
const THUMBNAIL_PIXELS: u32 = 36;

/// A cover made smaller, to draw; `None` when its bytes are no image Colophon reads.
fn decode_cover(data: &[u8], size: u32) -> Option<Image> {
    shrink(data, size).map(Image::from_rgba8)
}

/// The pixels of a cover made smaller, which another thread may compute.
fn shrink(data: &[u8], size: u32) -> Option<SharedPixelBuffer<Rgba8Pixel>> {
    let decoded = image::load_from_memory(data)
        .ok()?
        .thumbnail(size, size)
        .to_rgba8();
    Some(SharedPixelBuffer::<Rgba8Pixel>::clone_from_slice(
        decoded.as_raw(),
        decoded.width(),
        decoded.height(),
    ))
}

/// A cover from an image file, if it is a JPEG or a PNG.
fn cover_from(path: &Path) -> Option<tags::Cover> {
    let data = std::fs::read(path).ok()?;
    let mime = match image::guess_format(&data).ok()? {
        image::ImageFormat::Jpeg => "image/jpeg",
        image::ImageFormat::Png => "image/png",
        _ => return None,
    };
    Some(tags::Cover {
        mime: Some(mime.to_owned()),
        data: Arc::from(data),
    })
}

/// The extension of a file that holds `cover`.
fn cover_extension(cover: &tags::Cover) -> &'static str {
    match image::guess_format(&cover.data) {
        Ok(image::ImageFormat::Png) => "png",
        _ => "jpg",
    }
}

/// The colour that stands for an album's cover until covers show: a hue of its own.
fn swatch(album: &AlbumKey) -> slint::Color {
    use std::hash::{DefaultHasher, Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    album.hash(&mut hasher);
    let hue = (hasher.finish() % 360) as f32;
    slint::Color::from_hsva(hue, 0.55, 0.85, 1.0)
}

/// The genres that start with `text`, then those that hold it further on, ignoring case.
fn suggested_genres(genres: &[String], text: &str) -> Vec<SharedString> {
    let text = text.trim().to_lowercase();
    let (starting, holding): (Vec<_>, Vec<_>) = genres
        .iter()
        .filter_map(|genre| {
            let at = genre.to_lowercase().find(&text)?;
            Some((at == 0, SharedString::from(genre.as_str())))
        })
        .partition(|(starts, _)| *starts);
    starting
        .into_iter()
        .chain(holding)
        .map(|(_, genre)| genre)
        .collect()
}

/// What a field's text sets, or `None` when the field cannot hold it: a year runs from 1 to
/// 9999, a track or disc number and a total from 1. Empty text empties the field.
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
        TagField::Disc => Edit::Disc(number()?),
        TagField::DiscTotal => Edit::DiscTotal(number()?),
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

fn show_playback(window: &AppWindow, engine: &Engine) {
    let playback = engine.playback();
    let track = playback
        .track
        .and_then(|track| Some((track, engine.library().tracks.get(track)?)));
    window.set_player_available(engine.can_play());
    window.set_player_has_track(track.is_some());
    window.set_player_playing(playback.playing());
    window.set_player_volume(playback.volume);
    let Some((index, track)) = track else {
        window.set_player_title(SharedString::default());
        window.set_player_artist(SharedString::default());
        window.set_player_progress(0.0);
        window.set_player_position(SharedString::default());
        window.set_player_duration(SharedString::default());
        return;
    };
    let row = track_row(track, engine.edits().pending(index));
    let position = engine.position();
    let duration = track
        .metadata
        .as_ref()
        .ok()
        .and_then(|metadata| metadata.audio.duration)
        .unwrap_or_default();
    window.set_player_title(row.title);
    window.set_player_artist(row.artist);
    window.set_player_progress(if duration.is_zero() {
        0.0
    } else {
        (position.as_secs_f32() / duration.as_secs_f32()).min(1.0)
    });
    window.set_player_position(duration_text(position).into());
    window.set_player_duration(duration_text(duration).into());
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

fn show_writing(window: &AppWindow, policy: WritePolicy) {
    window.set_id3v2_3(policy.id3v2 == Id3v2Version::V2_3);
    window.set_id3v1_policy(match policy.id3v1 {
        tags::Id3v1Policy::Keep => Id3v1Policy::Keep,
        tags::Id3v1Policy::Always => Id3v1Policy::Always,
        tags::Id3v1Policy::Never => Id3v1Policy::Never,
    });
}

fn show_view(window: &AppWindow, view: &ViewState) {
    window.set_sidebar_visible(view.sidebar_visible);
    window.set_inspector_visible(view.inspector_visible);
    window.set_developer_mode(view.developer_mode);
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

fn show_sort(window: &AppWindow, sort: Option<Sort>) {
    window.set_sorted(sort.is_some());
    if let Some(sort) = sort {
        window.set_sorted_by(slint_sort_column(sort.column));
        window.set_sort_descending(sort.descending);
    }
}

const SORT_COLUMNS: [(generated::SortColumn, SortColumn); 11] = [
    (generated::SortColumn::Number, SortColumn::Number),
    (generated::SortColumn::Title, SortColumn::Title),
    (generated::SortColumn::Artist, SortColumn::Artist),
    (generated::SortColumn::Album, SortColumn::Album),
    (generated::SortColumn::Year, SortColumn::Year),
    (generated::SortColumn::Genre, SortColumn::Genre),
    (generated::SortColumn::Time, SortColumn::Time),
    (generated::SortColumn::Bitrate, SortColumn::Bitrate),
    (generated::SortColumn::Tags, SortColumn::Tags),
    (generated::SortColumn::File, SortColumn::File),
    (generated::SortColumn::Folder, SortColumn::Folder),
];

fn engine_sort_column(column: generated::SortColumn) -> SortColumn {
    SORT_COLUMNS
        .iter()
        .find(|(slint, _)| *slint == column)
        .map_or(SortColumn::Title, |(_, engine)| *engine)
}

fn slint_sort_column(column: SortColumn) -> generated::SortColumn {
    SORT_COLUMNS
        .iter()
        .find(|(_, engine)| *engine == column)
        .map_or(generated::SortColumn::Title, |(slint, _)| *slint)
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
    window.set_folder_open(!library.roots.is_empty());
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
    fn genres_that_start_with_the_text_come_first() {
        let genres: Vec<String> = ["Acid Rock", "Rock", "Rock & Roll", "Pop", "Synthwave"]
            .map(String::from)
            .to_vec();
        let suggested = |text| suggested_genres(&genres, text);

        assert_eq!(suggested("rock"), ["Rock", "Rock & Roll", "Acid Rock"]);
        assert_eq!(suggested(" SYNTH"), ["Synthwave"]);
        assert_eq!(suggested("").len(), 5);
        assert!(suggested("jazz").is_empty());
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
    fn each_band_of_a_waveform_draws_bars_as_high_as_it_is_loud() {
        let peaks = [colophon_player::Peak {
            low: -1.0,
            high: 1.0,
            bass: 0.5,
            treble: 0.0,
        }];
        let rows = |bars: SharedPixelBuffer<Rgba8Pixel>| {
            bars.as_slice()
                .chunks(bars.width() as usize)
                .filter(|row| row[0].a == 255)
                .count()
        };

        assert_eq!(
            rows(waveform_bars(&peaks, |peak| (peak.low, peak.high))),
            72
        );
        assert_eq!(
            rows(waveform_bars(&peaks, |peak| (-peak.bass, peak.bass))),
            36
        );
        // Silence still draws a line.
        assert_eq!(
            rows(waveform_bars(&peaks, |peak| (-peak.treble, peak.treble))),
            2
        );
    }

    #[test]
    fn a_folder_elsewhere_keeps_its_full_path() {
        assert_eq!(
            display_folder(Path::new("/Volumes/Music")),
            "/Volumes/Music"
        );
    }
}
