use std::borrow::Cow;
use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io::{self, Seek};
use std::path::{Path, PathBuf};

use lofty::TextEncoding;
use lofty::config::{ParseOptions, WriteOptions};
use lofty::error::{FileEncodingError, FileParseError};
use lofty::file::AudioFile;
use lofty::id3::v1::{GENRES, Id3v1Tag};
use lofty::id3::v2::{Frame, FrameId, Id3v2Tag, TextInformationFrame};
use lofty::mpeg::MpegFile;
use lofty::tag::Accessor;
use lofty::tag::items::Timestamp;

use crate::{Metadata, ReadError, Tags, read};

const ALBUM_ARTIST: FrameId<'static> = FrameId::Valid(Cow::Borrowed("TPE2"));
/// Every frame that holds a date, in ID3v2.4 (TDRC) or as ID3v2.2 and 2.3 kept it. lofty may
/// turn an old one into a TDRC of its own, which `set_date` adds to rather than replaces.
const DATE_FRAMES: [&str; 7] = ["TDRC", "TYER", "TDAT", "TIME", "TYE", "TDA", "TIM"];

#[derive(Debug, thiserror::Error)]
pub enum WriteError {
    /// The file is marked read only, which Colophon respects.
    #[error("the file is read only")]
    ReadOnly,
    /// The file, or the folder that holds it, could not be read or written.
    #[error("could not write the file")]
    Io(#[from] io::Error),
    #[error("could not make sense of the file")]
    Damaged(#[source] FileParseError),
    #[error("could not write the tags")]
    Encode(#[source] FileEncodingError),
    /// The tags were written, but the file could not be read back.
    #[error("could not read the file back")]
    ReadBack(#[source] ReadError),
}

/// Writes `tags` into an MP3: in ID3v2.4, and in ID3v1 too when the file has one. Every other frame
/// and the audio stay as they are. The tags go into a copy of the file in the same folder, which
/// replaces the original only once complete on disk: a failed write leaves the original untouched.
/// Gives back what the written file holds.
pub fn write(path: &Path, tags: &Tags) -> Result<Metadata, WriteError> {
    if fs::metadata(path)?.permissions().readonly() {
        return Err(WriteError::ReadOnly);
    }
    let copy = copy_path(path);
    let written = write_copy(path, &copy, tags).and_then(|()| Ok(fs::rename(&copy, path)?));
    if written.is_err() {
        // The original is untouched; the copy is all there is to clean up, if it was made at all.
        let _ = fs::remove_file(&copy);
    }
    written?;
    read(path).map_err(WriteError::ReadBack)
}

/// A hidden file next to the original, named after it and after this process.
fn copy_path(path: &Path) -> PathBuf {
    let mut name = OsString::from(".");
    name.push(path.file_name().unwrap_or_default());
    name.push(format!(".colophon-{}.tmp", std::process::id()));
    path.with_file_name(name)
}

fn write_copy(path: &Path, copy: &Path, tags: &Tags) -> Result<(), WriteError> {
    fs::copy(path, copy)?;
    let mut file = OpenOptions::new().read(true).write(true).open(copy)?;
    let mut mpeg =
        MpegFile::read_from(&mut file, ParseOptions::new()).map_err(WriteError::Damaged)?;
    if mpeg.id3v2().is_none() {
        mpeg.set_id3v2(Id3v2Tag::new());
    }
    if let Some(id3v2) = mpeg.id3v2_mut() {
        set_id3v2(id3v2, tags);
    }
    if let Some(id3v1) = mpeg.id3v1_mut() {
        *id3v1 = id3v1_from(tags);
    }
    file.rewind()?;
    mpeg.save_to(&mut file, WriteOptions::new())
        .map_err(WriteError::Encode)?;
    file.sync_all()?;
    Ok(())
}

fn set_id3v2(tag: &mut Id3v2Tag, tags: &Tags) {
    let text = |tag: &mut Id3v2Tag,
                value: &Option<String>,
                set: fn(&mut Id3v2Tag, String),
                remove: fn(&mut Id3v2Tag)| match value {
        Some(value) => set(tag, value.clone()),
        None => remove(tag),
    };
    text(
        tag,
        &tags.title,
        Accessor::set_title,
        Accessor::remove_title,
    );
    text(
        tag,
        &tags.artist,
        Accessor::set_artist,
        Accessor::remove_artist,
    );
    text(
        tag,
        &tags.album,
        Accessor::set_album,
        Accessor::remove_album,
    );
    text(
        tag,
        &tags.genre,
        Accessor::set_genre,
        Accessor::remove_genre,
    );
    text(
        tag,
        &tags.comment,
        Accessor::set_comment,
        Accessor::remove_comment,
    );
    // ffmpeg's comment, which Colophon reads when there is no COMM frame: it would come back
    // when the comment is removed.
    tag.retain(|frame| {
        !matches!(frame, Frame::UserText(text) if text.description.eq_ignore_ascii_case("comment"))
    });

    drop(tag.remove(&ALBUM_ARTIST));
    if let Some(album_artist) = &tags.album_artist {
        tag.insert(Frame::Text(TextInformationFrame::new(
            ALBUM_ARTIST,
            TextEncoding::UTF8,
            album_artist.clone(),
        )));
    }

    tag.retain(|frame| !DATE_FRAMES.contains(&frame.id_str()));
    if let Some(year) = tags.year {
        tag.set_date(Timestamp {
            year,
            ..Timestamp::default()
        });
    }

    // The number and the total share one frame, so both go before either comes back.
    tag.remove_track();
    tag.remove_disk();
    if let Some(track) = tags.track {
        tag.set_track(track);
    }
    if let Some(total) = tags.track_total {
        tag.set_track_total(total);
    }
    if let Some(disc) = tags.disc {
        tag.set_disk(disc);
    }
    if let Some(total) = tags.disc_total {
        tag.set_disk_total(total);
    }
}

/// An ID3v1.1 tag with what it can hold of `tags`; lofty cuts the text to its 30 Latin-1 bytes.
fn id3v1_from(tags: &Tags) -> Id3v1Tag {
    Id3v1Tag {
        title: tags.title.clone(),
        artist: tags.artist.clone(),
        album: tags.album.clone(),
        year: tags.year,
        comment: tags.comment.clone(),
        track_number: tags.track.and_then(|track| u8::try_from(track).ok()),
        genre: tags.genre.as_deref().and_then(id3v1_genre),
    }
}

fn id3v1_genre(name: &str) -> Option<u8> {
    GENRES
        .iter()
        .position(|genre| genre.eq_ignore_ascii_case(name))
        .and_then(|index| u8::try_from(index).ok())
}

/// A field whose value an ID3v1 tag cannot hold whole.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Id3v1Loss {
    Title,
    Artist,
    Album,
    Year,
    Comment,
    Track,
    Genre,
}

/// What an ID3v1 tag would lose of `tags`. It keeps 30 Latin-1 characters of text, 28 of the
/// comment next to a track number, a track up to 255, a four digit year, and the genres of its list.
pub fn id3v1_losses(tags: &Tags) -> Vec<Id3v1Loss> {
    let fits = |value: &Option<String>, length: usize| {
        value.as_deref().is_none_or(|value| {
            value.chars().count() <= length && value.chars().all(|c| u32::from(c) <= 0xff)
        })
    };
    let track_fits = tags.track.is_none_or(|track| track <= 255);
    let comment_length = if tags.track.is_some() && track_fits {
        28
    } else {
        30
    };
    [
        (Id3v1Loss::Title, fits(&tags.title, 30)),
        (Id3v1Loss::Artist, fits(&tags.artist, 30)),
        (Id3v1Loss::Album, fits(&tags.album, 30)),
        (Id3v1Loss::Year, tags.year.is_none_or(|year| year <= 9999)),
        (Id3v1Loss::Comment, fits(&tags.comment, comment_length)),
        (Id3v1Loss::Track, track_fits),
        (
            Id3v1Loss::Genre,
            tags.genre
                .as_deref()
                .is_none_or(|genre| id3v1_genre(genre).is_some()),
        ),
    ]
    .into_iter()
    .filter_map(|(loss, fits)| (!fits).then_some(loss))
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_copy_hides_next_to_the_original() {
        let copy = copy_path(Path::new("/music/07 Paper Satellites.mp3"));

        assert_eq!(copy.parent(), Some(Path::new("/music")));
        let name = copy.file_name().unwrap_or_default().to_string_lossy();
        assert!(
            name.starts_with(".07 Paper Satellites.mp3.colophon-"),
            "{name}"
        );
    }

    #[test]
    fn values_that_fit_id3v1_lose_nothing() {
        let tags = Tags {
            title: Some("Paper Satellites".into()),
            artist: Some("Björk".into()),
            year: Some(2019),
            track: Some(3),
            comment: Some("Exactly twenty-eight bytes!!".into()),
            genre: Some("folk".into()),
            ..Tags::default()
        };

        assert_eq!(id3v1_losses(&tags), []);
    }

    #[test]
    fn values_too_long_or_outside_latin1_are_lost() {
        let tags = Tags {
            title: Some("A title longer than thirty characters".into()),
            artist: Some("坂本龍一".into()),
            track: Some(3),
            comment: Some("Twenty-nine bytes, one too many".into()),
            genre: Some("Hyperpop".into()),
            ..Tags::default()
        };

        assert_eq!(
            id3v1_losses(&tags),
            [
                Id3v1Loss::Title,
                Id3v1Loss::Artist,
                Id3v1Loss::Comment,
                Id3v1Loss::Genre
            ]
        );
    }

    #[test]
    fn a_comment_without_a_track_keeps_30_characters() {
        let comment = Some("Thirty bytes, the whole field.".to_string());
        let with_track = Tags {
            comment: comment.clone(),
            track: Some(1),
            ..Tags::default()
        };
        let without = Tags {
            comment,
            ..Tags::default()
        };

        assert_eq!(id3v1_losses(&with_track), [Id3v1Loss::Comment]);
        assert_eq!(id3v1_losses(&without), []);
    }
}
