//! Colophon's tags: what an audio file says about itself. No UI types.

mod bitrate_mode;
mod read;
mod write;

use std::fmt;
use std::time::Duration;

pub use read::{ReadError, read};
pub use write::{Id3v1Loss, WriteError, formats_after_write, id3v1_losses, write};

/// The genres an ID3v1 tag can name, Winamp's extensions included: any other genre does not fit it.
pub fn id3v1_genres() -> &'static [&'static str] {
    &lofty::id3::v1::GENRES
}

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
    pub bitrate_mode: Option<BitrateMode>,
    /// In hertz.
    pub sample_rate: Option<u32>,
    pub channels: Option<u8>,
}

/// Whether the bitrate stays the same over the whole file.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BitrateMode {
    Constant,
    Variable,
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

/// The tags `write` leaves in a file, each in a version or not at all: a tag left out is removed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TagVersions {
    pub id3v2: Option<Id3v2Version>,
    pub id3v1: Option<Id3v1Version>,
}

impl TagVersions {
    /// What Colophon writes unless asked otherwise: ID3v2.4, and ID3v1.1 where the file has an
    /// ID3v1 tag.
    pub fn default_for(formats: &[TagFormat]) -> Self {
        let has_id3v1 = formats
            .iter()
            .any(|format| matches!(format, TagFormat::Id3v1(_)));
        Self {
            id3v2: Some(Id3v2Version::V2_4),
            id3v1: has_id3v1.then_some(Id3v1Version::V1_1),
        }
    }
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
