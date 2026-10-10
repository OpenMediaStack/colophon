//! Colophon's library: finding the audio files of a folder, reading and writing them. No UI types.

mod save;
mod scan;

use std::path::PathBuf;
use std::time::SystemTime;

pub use colophon_tags as tags;
pub use save::{SaveEvent, SaveHandle, SaveJob, Written, spawn_save};
pub use scan::{ScanError, ScanEvent, ScanHandle, ScanOutcome, scan, spawn_scan};

/// The extensions of the files Colophon reads. Later versions add other formats here.
pub const AUDIO_EXTENSIONS: &[&str] = &["mp3"];

/// An audio file found in the opened folder.
#[derive(Debug)]
pub struct Track {
    pub path: PathBuf,
    pub size: u64,
    pub modified: Option<SystemTime>,
    /// Its tags and audio properties, or why they could not be read: the file stays in the
    /// library either way.
    pub metadata: Result<tags::Metadata, tags::ReadError>,
}
