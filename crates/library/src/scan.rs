use std::ffi::OsStr;
use std::fmt;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::thread;

use walkdir::{DirEntry, WalkDir};

use crate::Track;

/// What a scan reports, in order: the files it finds, the entries it cannot read, then how it ended.
#[derive(Debug)]
pub enum ScanEvent {
    Found(Track),
    Unreadable(ScanError),
    Finished(ScanOutcome),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScanOutcome {
    Completed,
    Stopped,
}

/// A folder or a file the scan could not read. The scan skips it and goes on.
#[derive(Debug)]
pub struct ScanError {
    pub path: PathBuf,
    pub source: io::Error,
}

impl fmt::Display for ScanError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "cannot read {}: {}",
            self.path.display(),
            self.source
        )
    }
}

impl std::error::Error for ScanError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.source)
    }
}

/// Walks `root` and its subfolders, sorted by name, and reports every file whose extension is in
/// `extensions`, ignoring case. Hidden entries are skipped, among them the `._` files macOS leaves on
/// external drives. Checks `stop` between entries.
pub fn scan(
    root: &Path,
    extensions: &[&str],
    stop: &AtomicBool,
    mut report: impl FnMut(ScanEvent),
) {
    let entries = WalkDir::new(root)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|entry| entry.depth() == 0 || !is_hidden(entry));

    for entry in entries {
        if stop.load(Ordering::Relaxed) {
            report(ScanEvent::Finished(ScanOutcome::Stopped));
            return;
        }
        match entry {
            Ok(entry) if entry.file_type().is_file() && has_extension(entry.path(), extensions) => {
                report(match track(&entry) {
                    Ok(track) => ScanEvent::Found(track),
                    Err(error) => ScanEvent::Unreadable(error),
                });
            }
            Ok(_) => {}
            Err(error) => {
                let path = error.path().unwrap_or(root).to_path_buf();
                report(ScanEvent::Unreadable(ScanError {
                    path,
                    source: error.into(),
                }));
            }
        }
    }
    report(ScanEvent::Finished(ScanOutcome::Completed));
}

fn is_hidden(entry: &DirEntry) -> bool {
    entry.file_name().to_string_lossy().starts_with('.')
}

fn has_extension(path: &Path, extensions: &[&str]) -> bool {
    path.extension()
        .and_then(OsStr::to_str)
        .is_some_and(|extension| {
            extensions
                .iter()
                .any(|wanted| wanted.eq_ignore_ascii_case(extension))
        })
}

fn track(entry: &DirEntry) -> Result<Track, ScanError> {
    let metadata = entry.metadata().map_err(|error| ScanError {
        path: entry.path().to_path_buf(),
        source: error.into(),
    })?;
    Ok(Track {
        path: entry.path().to_path_buf(),
        size: metadata.len(),
        modified: metadata.modified().ok(),
    })
}

/// A scan running on its own thread. Dropping the handle stops the scan.
#[derive(Debug)]
pub struct ScanHandle {
    stop: Arc<AtomicBool>,
    events: Receiver<ScanEvent>,
}

impl ScanHandle {
    /// Asks the scan to stop. It ends with [`ScanOutcome::Stopped`] after the entry it is reading.
    pub fn stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
    }

    /// The events of the scan, in order. The channel closes after [`ScanEvent::Finished`].
    pub fn events(&self) -> &Receiver<ScanEvent> {
        &self.events
    }
}

impl Drop for ScanHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Starts [`scan`] on a new thread, so that the caller, the UI thread above all, never waits for the disk.
pub fn spawn_scan(root: PathBuf, extensions: &'static [&'static str]) -> io::Result<ScanHandle> {
    let stop = Arc::new(AtomicBool::new(false));
    let (sender, events) = mpsc::channel();
    let thread_stop = Arc::clone(&stop);
    thread::Builder::new()
        .name("library scan".to_string())
        .spawn(move || {
            scan(&root, extensions, &thread_stop, |event| {
                // A closed channel means nobody listens any more: the rest of the scan is not needed.
                if sender.send(event).is_err() {
                    thread_stop.store(true, Ordering::Relaxed);
                }
            });
        })?;
    Ok(ScanHandle { stop, events })
}
