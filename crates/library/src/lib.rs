//! Colophon's library: finding the audio files of a folder. No UI types.

mod scan;

use std::path::PathBuf;
use std::time::SystemTime;

pub use scan::{ScanError, ScanEvent, ScanHandle, ScanOutcome, scan, spawn_scan};

/// The extensions of the files Colophon reads. Later versions add other formats here.
pub const AUDIO_EXTENSIONS: &[&str] = &["mp3"];

/// An audio file found in the opened folder. Its tags come later, when they are read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Track {
    pub path: PathBuf,
    pub size: u64,
    pub modified: Option<SystemTime>,
}
