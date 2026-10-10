//! Colophon's application state and the commands that change it. No UI types.

mod columns;
mod selection;

use std::path::PathBuf;
use std::sync::mpsc::TryRecvError;

use colophon_library::{
    AUDIO_EXTENSIONS, ScanError, ScanEvent, ScanHandle, ScanOutcome, spawn_scan,
};

pub use colophon_library::{Track, tags};
pub use columns::{Column, ColumnWidths, Columns};
pub use selection::{Selection, Step};

/// A user action. The UI turns buttons, menu items and shortcuts into commands.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Command {
    ToggleSidebar,
    ToggleInspector,
    OpenFolder(PathBuf),
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
}

impl Command {
    /// A stable identifier, for the command palette and the shortcut table.
    pub fn id(&self) -> &'static str {
        match self {
            Command::ToggleSidebar => "view.toggle_sidebar",
            Command::ToggleInspector => "view.toggle_inspector",
            Command::OpenFolder(_) => "library.open_folder",
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
}

impl Default for ViewState {
    fn default() -> Self {
        Self {
            sidebar_visible: true,
            inspector_visible: true,
            columns: Columns::default(),
            column_widths: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ScanStatus {
    /// No folder has been opened.
    #[default]
    Idle,
    Scanning,
    Completed,
    /// The user stopped the scan; the tracks found until then stay.
    Stopped,
    /// The scan could not start, or its thread ended without saying how.
    Failed,
}

/// The opened folder and what its scan found so far.
#[derive(Debug, Default)]
pub struct Library {
    pub folder: Option<PathBuf>,
    pub tracks: Vec<Track>,
    pub unreadable: Vec<ScanError>,
    pub status: ScanStatus,
}

#[derive(Debug, Default)]
pub struct Engine {
    view: ViewState,
    library: Library,
    selection: Selection,
    scan: Option<ScanHandle>,
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

    pub fn execute(&mut self, command: Command) {
        match command {
            Command::ToggleSidebar => self.view.sidebar_visible = !self.view.sidebar_visible,
            Command::ToggleInspector => self.view.inspector_visible = !self.view.inspector_visible,
            Command::OpenFolder(folder) => self.open_folder(folder),
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
                self.selection.select_range(track);
            }
            Command::Select(_) | Command::ToggleSelected(_) | Command::SelectRange(_) => {}
            Command::SelectAll => self.selection.select_all(self.library.tracks.len()),
            Command::MoveSelection(step) => {
                self.selection.step(step, self.library.tracks.len(), false);
            }
            Command::ExtendSelection(step) => {
                self.selection.step(step, self.library.tracks.len(), true);
            }
        }
    }

    /// Takes in what the running scan reported since the last call, and says whether the library changed.
    /// The UI calls it regularly while a scan runs; it never waits.
    pub fn poll(&mut self) -> bool {
        let Some(scan) = &self.scan else {
            return false;
        };
        let mut changed = false;
        loop {
            match scan.events().try_recv() {
                Ok(ScanEvent::Found(track)) => self.library.tracks.push(*track),
                Ok(ScanEvent::Unreadable(error)) => self.library.unreadable.push(error),
                Ok(ScanEvent::Finished(outcome)) => {
                    self.library.status = match outcome {
                        ScanOutcome::Completed => ScanStatus::Completed,
                        ScanOutcome::Stopped => ScanStatus::Stopped,
                    };
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    if self.library.status == ScanStatus::Scanning {
                        self.library.status = ScanStatus::Failed;
                    }
                    break;
                }
            }
            changed = true;
        }
        if self.library.status != ScanStatus::Scanning {
            self.scan = None;
        }
        changed
    }

    fn has_track(&self, track: usize) -> bool {
        track < self.library.tracks.len()
    }

    fn open_folder(&mut self, folder: PathBuf) {
        self.scan = None;
        self.selection = Selection::default();
        self.library = Library {
            folder: Some(folder.clone()),
            ..Library::default()
        };
        match spawn_scan(folder, AUDIO_EXTENSIONS) {
            Ok(scan) => {
                self.scan = Some(scan);
                self.library.status = ScanStatus::Scanning;
            }
            Err(_) => self.library.status = ScanStatus::Failed,
        }
    }

    /// Stops at once: what the scan reports afterwards is dropped with its handle.
    fn stop_scan(&mut self) {
        if self.scan.take().is_some() {
            self.library.status = ScanStatus::Stopped;
        }
    }
}
