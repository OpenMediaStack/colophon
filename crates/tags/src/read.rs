use std::fs::File;
use std::io::{self, BufReader};
use std::panic::{self, UnwindSafe};
use std::path::Path;
use std::time::Duration;

use lofty::config::ParseOptions;
use lofty::error::FileParseError;
use lofty::file::AudioFile;
use lofty::id3::v1::{GENRES, Id3v1Tag};
use lofty::id3::v2::{self, Frame, Id3v2Tag};
use lofty::mpeg::{MpegFile, MpegProperties};
use lofty::tag::{Accessor, ItemKey, Tag};

use crate::{AudioProperties, Id3v1Version, Id3v2Version, Metadata, TagFormat, Tags, bitrate_mode};

#[derive(Debug, thiserror::Error)]
pub enum ReadError {
    /// The file is gone, or Colophon may not read it.
    #[error("could not open the file")]
    Open(#[source] io::Error),
    /// The file is not an MP3, or it is too damaged to make sense of.
    #[error("could not make sense of the file")]
    Damaged(#[source] FileParseError),
    /// The reader panicked on this file, which is a bug in lofty.
    #[error("the reader failed on this file")]
    ReaderPanicked,
}

/// Reads the tags and the audio properties of an MP3 file. A damaged file gives what can be read
/// of it, or an error.
pub fn read(path: &Path) -> Result<Metadata, ReadError> {
    guarded(|| read_mpeg(path))
}

/// lofty means never to panic on a damaged file. Should it panic all the same, only this file
/// fails, not the scan reading a whole folder.
fn guarded(
    read: impl FnOnce() -> Result<Metadata, ReadError> + UnwindSafe,
) -> Result<Metadata, ReadError> {
    panic::catch_unwind(read).unwrap_or(Err(ReadError::ReaderPanicked))
}

fn read_mpeg(path: &Path) -> Result<Metadata, ReadError> {
    let mut reader = BufReader::new(File::open(path).map_err(ReadError::Open)?);
    let options = ParseOptions::new().read_cover_art(false);
    let mpeg = MpegFile::read_from(&mut reader, options).map_err(ReadError::Damaged)?;
    Ok(Metadata {
        tags: primary_tags(&mpeg),
        audio: AudioProperties {
            bitrate_mode: bitrate_mode::read_mode(&mut reader),
            ..audio_properties(mpeg.properties())
        },
        formats: formats(&mpeg),
    })
}

fn formats(mpeg: &MpegFile) -> Vec<TagFormat> {
    let id3v2 = mpeg.id3v2().map(|tag| {
        TagFormat::Id3v2(match tag.original_version() {
            v2::Id3v2Version::V2 => Id3v2Version::V2_2,
            v2::Id3v2Version::V3 => Id3v2Version::V2_3,
            v2::Id3v2Version::V4 => Id3v2Version::V2_4,
        })
    });
    let id3v1 = mpeg.id3v1().map(|tag| {
        TagFormat::Id3v1(match tag.track_number {
            Some(_) => Id3v1Version::V1_1,
            None => Id3v1Version::V1_0,
        })
    });
    let ape = mpeg.ape().map(|_| TagFormat::Ape);
    [id3v2, id3v1, ape].into_iter().flatten().collect()
}

/// The values of the file's richest tag, never mixed field by field: a mix would hide the
/// differences between two tags of the same file.
fn primary_tags(mpeg: &MpegFile) -> Tags {
    if let Some(id3v2) = mpeg.id3v2() {
        let mut tags = tags_from(&Tag::from(id3v2.clone()));
        tags.comment = tags.comment.or_else(|| ffmpeg_comment(id3v2));
        tags
    } else if let Some(id3v1) = mpeg.id3v1() {
        id3v1_tags(id3v1)
    } else if let Some(ape) = mpeg.ape() {
        tags_from(&Tag::from(ape.clone()))
    } else {
        Tags::default()
    }
}

fn tags_from(tag: &Tag) -> Tags {
    Tags {
        title: text(tag.title().as_deref()),
        artist: text(tag.artist().as_deref()),
        album_artist: text(tag.get_string(ItemKey::AlbumArtist)),
        album: text(tag.album().as_deref()),
        year: tag.date().map(|date| date.year),
        track: tag.track(),
        track_total: tag.track_total(),
        disc: tag.disk(),
        disc_total: tag.disk_total(),
        genre: text(tag.genre().as_deref()),
        comment: text(tag.comment().as_deref()),
    }
}

/// ffmpeg writes its comment in a TXXX frame described "comment" rather than in a COMM frame, and
/// reads it back as the comment, so files made with ffmpeg carry their comment there.
fn ffmpeg_comment(tag: &Id3v2Tag) -> Option<String> {
    tag.into_iter().find_map(|frame| match frame {
        Frame::UserText(frame) if frame.description.eq_ignore_ascii_case("comment") => {
            text(Some(&frame.content))
        }
        _ => None,
    })
}

fn id3v1_tags(tag: &Id3v1Tag) -> Tags {
    let text = |value: &Option<String>| text(value.as_deref()).map(|value| utf8_if_valid(&value));
    Tags {
        title: text(&tag.title),
        artist: text(&tag.artist),
        album: text(&tag.album),
        year: tag.year,
        track: tag.track_number.map(u32::from),
        genre: tag
            .genre
            .and_then(|genre| GENRES.get(usize::from(genre)))
            .map(|genre| genre.to_string()),
        comment: text(&tag.comment),
        ..Tags::default()
    }
}

fn text(value: Option<&str>) -> Option<String> {
    value.filter(|value| !value.is_empty()).map(str::to_owned)
}

/// ID3v1 text is Latin-1 by the spec, but some taggers, ffmpeg among them, write UTF-8 there.
/// lofty decodes Latin-1, one char per byte, so the bytes come back unchanged and get a second
/// chance as UTF-8.
fn utf8_if_valid(latin1: &str) -> String {
    latin1
        .chars()
        .map(u8::try_from)
        .collect::<Result<Vec<u8>, _>>()
        .ok()
        .and_then(|bytes| String::from_utf8(bytes).ok())
        .unwrap_or_else(|| latin1.to_owned())
}

fn audio_properties(properties: &MpegProperties) -> AudioProperties {
    let known = |value: u32| (value > 0).then_some(value);
    AudioProperties {
        duration: Some(properties.duration()).filter(|duration| *duration > Duration::ZERO),
        bitrate: known(properties.audio_bitrate()),
        sample_rate: known(properties.sample_rate()),
        channels: Some(properties.channels()).filter(|channels| *channels > 0),
        bitrate_mode: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_panic_while_reading_fails_only_this_file() {
        let result = guarded(|| panic!("a bug in the reader"));

        assert!(
            matches!(result, Err(ReadError::ReaderPanicked)),
            "{result:?}"
        );
    }

    #[test]
    fn latin1_text_stays_latin1() {
        assert_eq!(utf8_if_valid("Caf\u{e9}"), "Café");
    }

    #[test]
    fn utf8_bytes_read_as_latin1_become_utf8_again() {
        assert_eq!(utf8_if_valid("Caf\u{c3}\u{a9}"), "Café");
    }

    #[test]
    fn utf8_cut_in_the_middle_of_a_character_stays_latin1() {
        assert_eq!(utf8_if_valid("abc\u{c3}"), "abc\u{c3}");
    }
}
