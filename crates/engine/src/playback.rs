use std::fmt::Debug;
use std::path::Path;
use std::time::Duration;

/// Where the engine sends the sound of a track: the system's speakers, or a fake in tests.
pub trait Output: Debug {
    /// Plays a file from its start, in place of what played.
    fn play(&mut self, path: &Path) -> Result<(), PlayError>;
    fn pause(&mut self);
    fn resume(&mut self);
    fn stop(&mut self);
    fn seek(&mut self, position: Duration) -> Result<(), PlayError>;
    /// How far the file has played.
    fn position(&self) -> Duration;
    /// The file has played to its end.
    fn finished(&self) -> bool;
    /// From 0, silent, to 1, as loud as the file.
    fn set_volume(&mut self, volume: f32);
}

#[derive(Debug, thiserror::Error)]
pub enum PlayError {
    #[error("could not open the file")]
    Open(#[source] std::io::Error),
    #[error("could not decode the file: {0}")]
    Decode(String),
    #[error("could not reach that position: {0}")]
    Seek(String),
}

/// What plays: a track of the library, playing or paused, and how loud.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Playback {
    pub track: Option<usize>,
    pub paused: bool,
    pub volume: f32,
}

impl Default for Playback {
    fn default() -> Self {
        Self {
            track: None,
            paused: false,
            volume: 0.8,
        }
    }
}

impl Playback {
    pub fn playing(&self) -> bool {
        self.track.is_some() && !self.paused
    }
}
