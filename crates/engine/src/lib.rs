//! Colophon's application state and the commands that change it. No UI types.

mod columns;
mod edits;
mod inspection;
mod listing;
mod selection;

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::path::PathBuf;
use std::sync::mpsc::TryRecvError;

use colophon_library::tags::WriteError;
use colophon_library::{
    SaveEvent, SaveHandle, SaveJob, ScanError, ScanEvent, ScanHandle, ScanOutcome, spawn_save,
    spawn_scan,
};

pub use colophon_library::{AUDIO_EXTENSIONS, Track, tags};
pub use columns::{Column, ColumnWidths, Columns};
pub use edits::{Edit, Edits, Field, VersionChoice};
pub use inspection::{AudioLine, Inspection, Shared, Summary};
pub use listing::{AlbumKey, Groups, Sort, SortColumn, Source};
pub use selection::{Selection, Step};

/// A user action. The UI turns buttons, menu items and shortcuts into commands.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Command {
    ToggleSidebar,
    ToggleInspector,
    /// Shows the tools for people who write ID3 readers and writers.
    ToggleDeveloperMode,
    /// Adds a folder's audio files to the library.
    OpenFolder(PathBuf),
    /// Adds audio files to the library, their folders with them.
    OpenFiles(Vec<PathBuf>),
    StopScan,
    ToggleColumn(Column),
    ResizeColumns(ColumnWidths),
    ResetColumns,
    /// A click on a track, by its place in the library: it alone becomes the selection.
    Select(usize),
    /// A Command click: the track joins the selection or leaves it.
    ToggleSelected(usize),
    /// A Shift click: the tracks from the last one clicked to this one become the selection.
    SelectRange(usize),
    SelectAll,
    /// An arrow key: the selection moves to the previous or next track.
    MoveSelection(Step),
    /// A Shift arrow: the selection grows or shrinks by one track.
    ExtendSelection(Step),
    /// A new value for one field of every selected track.
    Edit(Edit),
    /// The same, typed on: it goes on with the latest step of the history when that step edited
    /// the same field of the same tracks.
    ContinueEdit(Edit),
    Undo,
    Redo,
    /// Brings the selected tracks back to their files' tags.
    Revert,
    /// The version to write one tag of the selected tracks in, or none to remove it.
    ChooseVersion(VersionChoice),
    /// Writes every pending change to its file, in the background.
    Save,
    /// Lists the tracks of a source in the table.
    ShowSource(Source),
    /// Lists only the tracks whose title, artist, album or file name holds this text.
    Filter(String),
    /// Sorts the table by a column, or the other way round when it is sorted by it already.
    SortBy(SortColumn),
}

impl Command {
    /// A stable identifier, for the command palette and the shortcut table.
    pub fn id(&self) -> &'static str {
        match self {
            Command::ToggleSidebar => "view.toggle_sidebar",
            Command::ToggleInspector => "view.toggle_inspector",
            Command::ToggleDeveloperMode => "view.toggle_developer_mode",
            Command::OpenFolder(_) => "library.open_folder",
            Command::OpenFiles(_) => "library.open_files",
            Command::StopScan => "library.stop_scan",
            Command::ToggleColumn(_) => "view.toggle_column",
            Command::ResizeColumns(_) => "view.resize_columns",
            Command::ResetColumns => "view.reset_columns",
            Command::Select(_) => "selection.select",
            Command::ToggleSelected(_) => "selection.toggle",
            Command::SelectRange(_) => "selection.select_range",
            Command::SelectAll => "selection.select_all",
            Command::MoveSelection(_) => "selection.move",
            Command::ExtendSelection(_) => "selection.extend",
            Command::Edit(_) => "tags.edit",
            Command::ContinueEdit(_) => "tags.continue_edit",
            Command::Undo => "edit.undo",
            Command::Redo => "edit.redo",
            Command::Revert => "tags.revert",
            Command::ChooseVersion(_) => "tags.choose_version",
            Command::Save => "tags.save",
            Command::ShowSource(_) => "view.show_source",
            Command::Filter(_) => "view.filter",
            Command::SortBy(_) => "view.sort_by",
        }
    }
}

/// Which panels and columns the user wants to see. The UI may still hide the sidebar when the
/// window is too narrow.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ViewState {
    pub sidebar_visible: bool,
    pub inspector_visible: bool,
    pub columns: Columns,
    /// `None` until the user resizes a column: the table then shares its width between them.
    pub column_widths: Option<ColumnWidths>,
    /// The inspector chooses the tag versions to write, ID3v2.2 included.
    pub developer_mode: bool,
}

impl Default for ViewState {
    fn default() -> Self {
        Self {
            sidebar_visible: true,
            inspector_visible: true,
            columns: Columns::default(),
            column_widths: None,
            developer_mode: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ScanStatus {
    /// Nothing has been opened.
    #[default]
    Idle,
    Scanning,
    Completed,
    /// The user stopped the scans; the tracks found until then stay.
    Stopped,
    /// The scan could not start, or its thread ended without saying how.
    Failed,
}

/// How far a save has got.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SaveProgress {
    pub done: usize,
    pub total: usize,
}

/// A file a save could not write. Its changes stay pending.
#[derive(Debug)]
pub struct SaveFailure {
    pub track: usize,
    pub error: WriteError,
}

#[derive(Debug)]
struct Saving {
    handle: SaveHandle,
    progress: SaveProgress,
}

/// The opened folders and files, and what their scans found so far.
#[derive(Debug, Default)]
pub struct Library {
    /// The folders opened, and those of the files opened alone, none inside another, in order.
    pub roots: Vec<PathBuf>,
    pub tracks: Vec<Track>,
    pub unreadable: Vec<ScanError>,
    pub status: ScanStatus,
}

#[derive(Debug, Default)]
pub struct Engine {
    view: ViewState,
    library: Library,
    selection: Selection,
    edits: Edits,
    saving: Option<Saving>,
    save_failures: Vec<SaveFailure>,
    scans: Vec<ScanHandle>,
    /// The paths of the tracks found, so that opening a file twice lists it once.
    found: HashSet<PathBuf>,
    /// The tracks saved since Colophon started.
    saved: BTreeSet<usize>,
    source: Source,
    filter: String,
    sort: Option<Sort>,
    /// The tracks the table lists, in its order.
    listed: Vec<usize>,
}

impl Engine {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn view(&self) -> &ViewState {
        &self.view
    }

    pub fn library(&self) -> &Library {
        &self.library
    }

    pub fn selection(&self) -> &Selection {
        &self.selection
    }

    /// The pending changes to the tags, and their history.
    pub fn edits(&self) -> &Edits {
        &self.edits
    }

    /// How far the running save has got, if one runs.
    pub fn saving(&self) -> Option<SaveProgress> {
        self.saving.as_ref().map(|saving| saving.progress)
    }

    /// The files the last save could not write.
    pub fn save_failures(&self) -> &[SaveFailure] {
        &self.save_failures
    }

    /// The source of the table's tracks, its filter and its order.
    pub fn source(&self) -> &Source {
        &self.source
    }

    pub fn filter(&self) -> &str {
        &self.filter
    }

    pub fn sort(&self) -> Option<Sort> {
        self.sort
    }

    /// The tracks the table lists, by their place in the library, in its order. Edits leave it as
    /// it is until the source, the filter, the order or the library changes, so that a track does
    /// not move away while it is being edited.
    pub fn listed(&self) -> &[usize] {
        &self.listed
    }

    /// The tracks with changes waiting to be saved, or saved since Colophon started.
    pub fn changed(&self) -> BTreeSet<usize> {
        self.edits
            .modified()
            .map(|(track, _)| track)
            .chain(self.saved.iter().copied())
            .collect()
    }

    /// The albums and artists of the library.
    pub fn groups(&self) -> Groups {
        listing::groups(&self.library.tracks)
    }

    /// The tags a track shows: those waiting to be saved, or else its file's.
    pub fn tags_of(&self, track: usize) -> Option<&colophon_library::tags::Tags> {
        self.edits.pending(track).or_else(|| {
            let metadata = self.library.tracks.get(track)?.metadata.as_ref().ok()?;
            Some(&metadata.tags)
        })
    }

    /// The genres to suggest: those an ID3v1 tag can name and those of the files read, once each
    /// whatever their case, in alphabetical order. A genre only typed so far is not one of them.
    pub fn genres(&self) -> Vec<String> {
        let read = self.library.tracks.iter().filter_map(|track| {
            let metadata = track.metadata.as_ref().ok()?;
            metadata.tags.genre.as_deref()
        });
        let mut genres = BTreeMap::new();
        for genre in tags::id3v1_genres().iter().copied().chain(read) {
            genres
                .entry(genre.to_lowercase())
                .or_insert_with(|| genre.to_string());
        }
        genres.into_values().collect()
    }

    /// What the inspector shows of the selected tracks.
    pub fn inspection(&self) -> Inspection<'_> {
        inspection::inspect(&self.library.tracks, &self.selection, &self.edits)
    }

    pub fn execute(&mut self, command: Command) {
        match command {
            Command::ToggleSidebar => self.view.sidebar_visible = !self.view.sidebar_visible,
            Command::ToggleInspector => self.view.inspector_visible = !self.view.inspector_visible,
            Command::ToggleDeveloperMode => self.view.developer_mode = !self.view.developer_mode,
            Command::OpenFolder(folder) => self.open(vec![folder.clone()], [folder]),
            Command::OpenFiles(files) => {
                let folders: Vec<PathBuf> = files
                    .iter()
                    .filter_map(|file| file.parent().map(PathBuf::from))
                    .collect();
                self.open(files, folders);
            }
            Command::StopScan => self.stop_scan(),
            Command::ToggleColumn(column) => self.view.columns.toggle(column),
            Command::ResizeColumns(widths) => self.view.column_widths = Some(widths),
            Command::ResetColumns => {
                self.view.columns = Columns::default();
                self.view.column_widths = None;
            }
            Command::Select(track) if self.has_track(track) => self.selection.select(track),
            Command::ToggleSelected(track) if self.has_track(track) => {
                self.selection.toggle(track);
            }
            Command::SelectRange(track) if self.has_track(track) => {
                self.selection.select_range(track, &self.listed);
            }
            Command::Select(_) | Command::ToggleSelected(_) | Command::SelectRange(_) => {}
            Command::SelectAll => self.selection.select_all(&self.listed),
            Command::MoveSelection(step) => self.selection.step(step, &self.listed, false),
            Command::ExtendSelection(step) => self.selection.step(step, &self.listed, true),
            Command::Edit(edit) => {
                self.edits
                    .edit(&self.library.tracks, self.selection.iter(), &edit, false);
            }
            Command::ContinueEdit(edit) => {
                self.edits
                    .edit(&self.library.tracks, self.selection.iter(), &edit, true);
            }
            Command::Undo => self.edits.undo(&self.library.tracks),
            Command::Redo => self.edits.redo(&self.library.tracks),
            Command::Revert => self
                .edits
                .revert(&self.library.tracks, self.selection.iter()),
            Command::ChooseVersion(choice) => {
                self.edits
                    .choose_versions(&self.library.tracks, self.selection.iter(), choice);
            }
            Command::Save => self.save(),
            Command::ShowSource(source) => {
                self.source = source;
                self.relist();
            }
            Command::Filter(filter) => {
                self.filter = filter;
                self.relist();
            }
            Command::SortBy(column) => {
                self.sort = Some(Sort {
                    column,
                    descending: self
                        .sort
                        .is_some_and(|sort| sort.column == column && !sort.descending),
                });
                self.relist();
            }
        }
    }

    /// Takes in what the running scans and save reported since the last call, and says whether the
    /// library changed. The UI calls it regularly while they run; it never waits.
    pub fn poll(&mut self) -> bool {
        let scanned = self.poll_scan();
        let saved = self.poll_save();
        if scanned || saved {
            self.relist();
        }
        scanned || saved
    }

    /// Lists the tracks of the source again, filtered and sorted.
    fn relist(&mut self) {
        let changed = self.changed();
        let edits = &self.edits;
        let tracks = &self.library.tracks;
        let shown = |track: usize| {
            edits.pending(track).or_else(|| {
                tracks
                    .get(track)?
                    .metadata
                    .as_ref()
                    .ok()
                    .map(|metadata| &metadata.tags)
            })
        };
        let context = listing::Context {
            tracks,
            shown: &shown,
            changed: &changed,
        };
        self.listed = listing::list(&context, &self.source, &self.filter, self.sort);
    }

    fn poll_scan(&mut self) -> bool {
        if self.scans.is_empty() {
            return false;
        }
        let mut changed = false;
        let mut ended = None;
        let scans = std::mem::take(&mut self.scans);
        for scan in scans {
            let outcome = loop {
                match scan.events().try_recv() {
                    Ok(ScanEvent::Found(track)) => {
                        if self.found.insert(track.path.clone()) {
                            self.library.tracks.push(*track);
                        }
                    }
                    Ok(ScanEvent::Unreadable(error)) => self.library.unreadable.push(error),
                    Ok(ScanEvent::Finished(ScanOutcome::Completed)) => {
                        break Some(ScanStatus::Completed);
                    }
                    Ok(ScanEvent::Finished(ScanOutcome::Stopped)) => {
                        break Some(ScanStatus::Stopped);
                    }
                    Err(TryRecvError::Empty) => break None,
                    // The thread ended without saying how.
                    Err(TryRecvError::Disconnected) => break Some(ScanStatus::Failed),
                }
                changed = true;
            };
            match outcome {
                Some(status) => {
                    ended = Some(status);
                    changed = true;
                }
                None => self.scans.push(scan),
            }
        }
        if self.scans.is_empty()
            && let Some(status) = ended
        {
            self.library.status = status;
        }
        changed
    }

    /// Starts writing every pending change, unless a save already runs.
    fn save(&mut self) {
        if self.saving.is_some() {
            return;
        }
        let jobs: Vec<SaveJob> = self
            .edits
            .modified()
            .filter_map(|(track, tags)| {
                Some(SaveJob {
                    track,
                    path: self.library.tracks.get(track)?.path.clone(),
                    tags: tags.clone(),
                    versions: self.edits.versions(&self.library.tracks, track)?,
                })
            })
            .collect();
        if jobs.is_empty() {
            return;
        }
        self.save_failures.clear();
        let total = jobs.len();
        match spawn_save(jobs.clone()) {
            Ok(handle) => {
                self.saving = Some(Saving {
                    handle,
                    progress: SaveProgress { done: 0, total },
                });
            }
            Err(error) => {
                self.save_failures = jobs
                    .into_iter()
                    .map(|job| SaveFailure {
                        track: job.track,
                        error: WriteError::Io(std::io::Error::from(error.kind())),
                    })
                    .collect();
            }
        }
    }

    /// Takes in the files the save wrote: each track gets what its file now holds, and its
    /// pending tags go once the file holds them. A change made meanwhile stays pending.
    fn poll_save(&mut self) -> bool {
        let Some(saving) = &self.saving else {
            return false;
        };
        let mut events = Vec::new();
        let mut finished = false;
        loop {
            match saving.handle.events().try_recv() {
                Ok(SaveEvent::Finished) | Err(TryRecvError::Disconnected) => {
                    finished = true;
                    break;
                }
                Ok(event) => events.push(event),
                Err(TryRecvError::Empty) => break,
            }
        }
        let changed = finished || !events.is_empty();
        for event in events {
            let SaveEvent::Written { track, result } = event else {
                continue;
            };
            if let Some(saving) = &mut self.saving {
                saving.progress.done += 1;
            }
            match result {
                Ok(written) => {
                    if let Some(saved) = self.library.tracks.get_mut(track) {
                        saved.metadata = Ok(written.metadata);
                        saved.size = written.size;
                    }
                    self.saved.insert(track);
                    self.edits.settle(&self.library.tracks, track);
                }
                Err(error) => self.save_failures.push(SaveFailure { track, error }),
            }
        }
        if finished {
            self.saving = None;
        }
        changed
    }

    fn has_track(&self, track: usize) -> bool {
        track < self.library.tracks.len()
    }

    /// Scans `paths`, folders or files, for tracks the library does not have yet, and lists
    /// `folders` among its roots.
    fn open(&mut self, paths: Vec<PathBuf>, folders: impl IntoIterator<Item = PathBuf>) {
        for folder in folders {
            self.add_root(folder);
        }
        match spawn_scan(paths, AUDIO_EXTENSIONS) {
            Ok(scan) => {
                self.scans.push(scan);
                self.library.status = ScanStatus::Scanning;
            }
            Err(_) if self.scans.is_empty() => self.library.status = ScanStatus::Failed,
            Err(_) => {}
        }
    }

    /// Lists a folder among the roots, unless one holds it already; it replaces those it holds.
    fn add_root(&mut self, folder: PathBuf) {
        let roots = &mut self.library.roots;
        if roots.iter().any(|root| folder.starts_with(root)) {
            return;
        }
        roots.retain(|root| !root.starts_with(&folder));
        roots.push(folder);
        roots.sort();
    }

    /// Stops at once: what the scans report afterwards is dropped with their handles.
    fn stop_scan(&mut self) {
        if !self.scans.is_empty() {
            self.scans.clear();
            self.library.status = ScanStatus::Stopped;
        }
    }
}
