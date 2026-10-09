//! Colophon's application state and the commands that change it. No UI types.

use std::path::PathBuf;
use std::sync::mpsc::TryRecvError;

use colophon_library::{
    AUDIO_EXTENSIONS, ScanError, ScanEvent, ScanHandle, ScanOutcome, Track, spawn_scan,
};

/// A user action. The UI turns buttons, menu items and shortcuts into commands.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Command {
    ToggleSidebar,
    ToggleInspector,
    OpenFolder(PathBuf),
    StopScan,
}

impl Command {
    /// A stable identifier, for the command palette and the shortcut table.
    pub fn id(&self) -> &'static str {
        match self {
            Command::ToggleSidebar => "view.toggle_sidebar",
            Command::ToggleInspector => "view.toggle_inspector",
            Command::OpenFolder(_) => "library.open_folder",
            Command::StopScan => "library.stop_scan",
        }
    }
}

/// Which panels the user wants to see. The UI may still hide the sidebar when the window is too narrow.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ViewState {
    pub sidebar_visible: bool,
    pub inspector_visible: bool,
}

impl Default for ViewState {
    fn default() -> Self {
        Self {
            sidebar_visible: true,
            inspector_visible: true,
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

    pub fn execute(&mut self, command: Command) {
        match command {
            Command::ToggleSidebar => self.view.sidebar_visible = !self.view.sidebar_visible,
            Command::ToggleInspector => self.view.inspector_visible = !self.view.inspector_visible,
            Command::OpenFolder(folder) => self.open_folder(folder),
            Command::StopScan => self.stop_scan(),
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

    fn open_folder(&mut self, folder: PathBuf) {
        self.scan = None;
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
