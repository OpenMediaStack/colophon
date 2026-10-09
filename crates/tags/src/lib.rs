//! Colophon's tags: what an audio file says about itself. No UI types.

mod read;

use std::fmt;
use std::time::Duration;

pub use read::{ReadError, read};

/// Everything Colophon reads from an audio file.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Metadata {
    pub tags: Tags,
    pub audio: AudioProperties,
    /// The tags found in the file, in the order Colophon prefers them.
    pub formats: Vec<TagFormat>,
}

/// The fields Colophon shows and edits, the same for every format. A field the file does not
/// give is `None`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Tags {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album_artist: Option<String>,
    pub album: Option<String>,
    pub year: Option<u16>,
    pub track: Option<u32>,
    pub track_total: Option<u32>,
    pub disc: Option<u32>,
    pub disc_total: Option<u32>,
    pub genre: Option<String>,
    pub comment: Option<String>,
}

/// What the audio stream says about itself. A value the file does not give is `None`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct AudioProperties {
    pub duration: Option<Duration>,
    /// In kilobits per second, averaged over the file when the bitrate varies.
    pub bitrate: Option<u32>,
    /// In hertz.
    pub sample_rate: Option<u32>,
    pub channels: Option<u8>,
}

/// A kind of tag found in a file, with its version.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TagFormat {
    Id3v2(Id3v2Version),
    Id3v1(Id3v1Version),
    Ape,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Id3v2Version {
    V2_2,
    V2_3,
    V2_4,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Id3v1Version {
    V1_0,
    /// ID3v1.1 takes the last byte of the comment for a track number.
    V1_1,
}

impl fmt::Display for TagFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            TagFormat::Id3v2(Id3v2Version::V2_2) => "ID3v2.2",
            TagFormat::Id3v2(Id3v2Version::V2_3) => "ID3v2.3",
            TagFormat::Id3v2(Id3v2Version::V2_4) => "ID3v2.4",
            TagFormat::Id3v1(Id3v1Version::V1_0) => "ID3v1.0",
            TagFormat::Id3v1(Id3v1Version::V1_1) => "ID3v1.1",
            TagFormat::Ape => "APE",
        };
        f.write_str(name)
    }
}
