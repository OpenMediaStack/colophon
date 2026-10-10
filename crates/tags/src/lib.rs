//! Colophon's tags: what an audio file says about itself. No UI types.

mod bitrate_mode;
mod read;
mod write;

use std::fmt;
use std::sync::Arc;
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
    pub cover: Option<Cover>,
}

/// The picture of the release: the file's front cover, or else its first picture. Files of the same
/// album often hold the same bytes, which reading shares rather than copies.
#[derive(Debug, Clone, Default, PartialEq, Eq, Hash)]
pub struct Cover {
    /// Its type, such as `image/jpeg`, when the file says.
    pub mime: Option<String>,
    pub data: Arc<[u8]>,
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
        Self::following(WritePolicy::default(), formats)
    }

    /// What `policy` writes in a file that holds `formats`.
    pub fn following(policy: WritePolicy, formats: &[TagFormat]) -> Self {
        let has_id3v1 = formats
            .iter()
            .any(|format| matches!(format, TagFormat::Id3v1(_)));
        let id3v1 = match policy.id3v1 {
            Id3v1Policy::Keep => has_id3v1,
            Id3v1Policy::Always => true,
            Id3v1Policy::Never => false,
        };
        Self {
            id3v2: Some(policy.id3v2),
            id3v1: id3v1.then_some(Id3v1Version::V1_1),
        }
    }
}

/// The tags written in files the user chose no versions for: ID3v2 in this version, and ID3v1
/// as the policy says.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WritePolicy {
    pub id3v2: Id3v2Version,
    pub id3v1: Id3v1Policy,
}

impl Default for WritePolicy {
    fn default() -> Self {
        Self {
            id3v2: Id3v2Version::V2_4,
            id3v1: Id3v1Policy::Keep,
        }
    }
}

/// Which files get an ID3v1 tag.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum Id3v1Policy {
    /// Those that have one already.
    #[default]
    Keep,
    Always,
    Never,
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

#[cfg(test)]
mod tests {
    use super::*;

    const WITH_ID3V1: [TagFormat; 2] = [
        TagFormat::Id3v2(Id3v2Version::V2_3),
        TagFormat::Id3v1(Id3v1Version::V1_0),
    ];
    const WITHOUT_ID3V1: [TagFormat; 1] = [TagFormat::Id3v2(Id3v2Version::V2_3)];

    fn writing(id3v1: Id3v1Policy, formats: &[TagFormat]) -> TagVersions {
        let policy = WritePolicy {
            id3v2: Id3v2Version::V2_3,
            id3v1,
        };
        TagVersions::following(policy, formats)
    }

    #[test]
    fn the_policy_chooses_the_versions_to_write() {
        let id3v1 = |policy, formats: &[TagFormat]| writing(policy, formats).id3v1;

        assert_eq!(
            writing(Id3v1Policy::Keep, &WITH_ID3V1).id3v2,
            Some(Id3v2Version::V2_3)
        );
        assert_eq!(
            id3v1(Id3v1Policy::Keep, &WITH_ID3V1),
            Some(Id3v1Version::V1_1)
        );
        assert_eq!(id3v1(Id3v1Policy::Keep, &WITHOUT_ID3V1), None);
        assert_eq!(
            id3v1(Id3v1Policy::Always, &WITHOUT_ID3V1),
            Some(Id3v1Version::V1_1)
        );
        assert_eq!(id3v1(Id3v1Policy::Never, &WITH_ID3V1), None);
    }
}
