//! Every version Colophon writes, read back by Colophon, by ffprobe and by the `id3` crate.

mod common;

use std::collections::HashMap;
use std::error::Error;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::Arc;

use colophon_tags::{
    Cover, Id3v1Version, Id3v2Version, TagVersions, Tags, formats_after_write, read, write,
};
use id3::TagLike;

use common::{TestResult, fixture};

/// Fixtures with every mix of ID3 tags Colophon reads, and none.
const FIXTURES: [&str; 6] = [
    "no_tag.mp3",
    "v1_1_ascii.mp3",
    "v22.mp3",
    "v23_full.mp3",
    "v23_cover.mp3",
    "v24_full.mp3",
];
const ID3V2: [Option<Id3v2Version>; 4] = [
    Some(Id3v2Version::V2_4),
    Some(Id3v2Version::V2_3),
    Some(Id3v2Version::V2_2),
    None,
];
const ID3V1: [Option<Id3v1Version>; 3] = [Some(Id3v1Version::V1_1), Some(Id3v1Version::V1_0), None];

/// Values every version holds whole, ID3v1 included: short Latin-1 text and a genre of its list.
fn tags() -> Tags {
    Tags {
        title: Some("Neon Overpass".into()),
        artist: Some("Cassette Bloom".into()),
        album_artist: Some("Cassette Bloom".into()),
        album: Some("Analog Hearts".into()),
        year: Some(2024),
        track: Some(4),
        track_total: Some(9),
        disc: Some(2),
        disc_total: Some(3),
        genre: Some("Folk".into()),
        comment: Some("Remastered in 2025.".into()),
        cover: Some(Cover {
            mime: Some("image/png".into()),
            data: Arc::from(PIXEL),
        }),
    }
}

/// A PNG of one transparent pixel.
const PIXEL: [u8; 67] = [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
    0x42, 0x60, 0x82,
];

/// What a file holds of `tags` once written in `versions`: everything with ID3v2, what ID3v1
/// holds without it, and nothing without either.
fn kept(versions: TagVersions) -> Tags {
    let tags = tags();
    match versions {
        TagVersions { id3v2: Some(_), .. } => tags,
        TagVersions {
            id3v2: None,
            id3v1: Some(version),
        } => Tags {
            album_artist: None,
            cover: None,
            track: tags.track.filter(|_| version == Id3v1Version::V1_1),
            track_total: None,
            disc: None,
            disc_total: None,
            ..tags
        },
        TagVersions {
            id3v2: None,
            id3v1: None,
        } => Tags::default(),
    }
}

/// The tags ffprobe reads in a file, by their `-of flat` keys, among those Colophon edits.
fn ffprobe(path: &Path) -> Result<HashMap<String, String>, Box<dyn Error>> {
    let output = Command::new("ffprobe")
        .args(["-v", "error", "-of", "flat", "-show_format"])
        .arg(path)
        .output()
        .map_err(|error| format!("ffprobe could not run, install ffmpeg: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(|line| line.strip_prefix("format.tags."))
        .filter_map(|line| line.split_once('='))
        // ffmpeg names every ID3v2.2 frame Colophon edits but the disc, which it leaves as TPA.
        .map(|(key, value)| (if key == "TPA" { "disc" } else { key }, value))
        .filter(|(key, _)| EDITED.contains(key))
        .map(|(key, value)| (key.to_owned(), value.trim_matches('"').to_owned()))
        .collect())
}

/// The ffprobe keys of the fields Colophon edits.
const EDITED: [&str; 9] = [
    "title",
    "artist",
    "album_artist",
    "album",
    "genre",
    "comment",
    "date",
    "track",
    "disc",
];

/// What ffprobe should read of `tags`.
fn as_ffprobe(tags: &Tags) -> HashMap<String, String> {
    let pair = |number: Option<u32>, total: Option<u32>| match (number, total) {
        (Some(number), Some(total)) => Some(format!("{number}/{total}")),
        (Some(number), None) => Some(number.to_string()),
        _ => None,
    };
    [
        ("title", tags.title.clone()),
        ("artist", tags.artist.clone()),
        ("album_artist", tags.album_artist.clone()),
        ("album", tags.album.clone()),
        ("genre", tags.genre.clone()),
        ("comment", tags.comment.clone()),
        ("date", tags.year.map(|year| year.to_string())),
        ("track", pair(tags.track, tags.track_total)),
        ("disc", pair(tags.disc, tags.disc_total)),
    ]
    .into_iter()
    .filter_map(|(key, value)| Some((key.to_owned(), value?)))
    .collect()
}

/// What the `id3` crate reads of a file's ID3v2 tag, in Colophon's terms, with its version.
fn id3_crate_v2(path: &Path) -> Result<Option<(Id3v2Version, Tags)>, Box<dyn Error>> {
    let tag = match id3::Tag::read_from_path(path) {
        Ok(tag) => tag,
        Err(error) if matches!(error.kind, id3::ErrorKind::NoTag) => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let version = match tag.version() {
        id3::Version::Id3v22 => Id3v2Version::V2_2,
        id3::Version::Id3v23 => Id3v2Version::V2_3,
        id3::Version::Id3v24 => Id3v2Version::V2_4,
    };
    let text = |value: Option<&str>| value.map(str::to_owned);
    let year = tag
        .year()
        .or_else(|| tag.date_recorded().map(|date| date.year))
        .and_then(|year| u16::try_from(year).ok());
    Ok(Some((
        version,
        Tags {
            title: text(tag.title()),
            artist: text(tag.artist()),
            album_artist: text(tag.album_artist()),
            album: text(tag.album()),
            year,
            track: tag.track(),
            track_total: tag.total_tracks(),
            disc: tag.disc(),
            disc_total: tag.total_discs(),
            genre: tag.genre_parsed().map(|genre| genre.into_owned()),
            comment: tag.comments().next().map(|comment| comment.text.clone()),
            cover: tag.pictures().next().map(|picture| Cover {
                mime: Some(picture.mime_type.clone()),
                data: Arc::from(picture.data.as_slice()),
            }),
        },
    )))
}

/// What the `id3` crate reads of a file's ID3v1 tag, in Colophon's terms, with its version.
fn id3_crate_v1(path: &Path) -> Result<Option<(Id3v1Version, Tags)>, Box<dyn Error>> {
    if !id3::v1::Tag::is_candidate(fs::File::open(path)?)? {
        return Ok(None);
    }
    let tag = id3::v1::Tag::read_from(fs::File::open(path)?)?;
    let text = |value: &str| Some(value.to_owned()).filter(|value| !value.is_empty());
    let version = match tag.track {
        Some(_) => Id3v1Version::V1_1,
        None => Id3v1Version::V1_0,
    };
    Ok(Some((
        version,
        Tags {
            title: text(&tag.title),
            artist: text(&tag.artist),
            album: text(&tag.album),
            year: tag.year.parse().ok(),
            track: tag.track.map(u32::from),
            genre: tag.genre().map(str::to_owned),
            comment: text(&tag.comment),
            ..Tags::default()
        },
    )))
}

#[test]
fn every_version_reads_back_the_same_in_colophon_ffprobe_and_the_id3_crate() -> TestResult {
    let mut report = Vec::new();
    for name in FIXTURES {
        for id3v2 in ID3V2 {
            for id3v1 in ID3V1 {
                let versions = TagVersions { id3v2, id3v1 };
                let folder = tempfile::tempdir()?;
                let path = folder.path().join(name);
                fs::copy(fixture(name), &path)?;
                let formats = read(&path)?.formats;

                let written = write(&path, &tags(), versions)?;

                let case = format!("{name} as {versions:?}");
                let expected = kept(versions);
                if written.tags != expected {
                    report.push(format!("{case}: Colophon reads {:?}", written.tags));
                }
                if written.formats != formats_after_write(&formats, &tags(), versions) {
                    report.push(format!("{case}: Colophon finds {:?}", written.formats));
                }
                let probe = ffprobe(&path)?;
                if probe != as_ffprobe(&expected) {
                    report.push(format!("{case}: ffprobe reads {probe:?}"));
                }
                let id3v2_read = id3_crate_v2(&path)?;
                let id3v2_expected = id3v2.map(|version| (version, tags()));
                if id3v2_read != id3v2_expected {
                    report.push(format!("{case}: the id3 crate reads {id3v2_read:?}"));
                }
                let id3v1_read = id3_crate_v1(&path)?;
                let id3v1_expected = id3v1.map(|version| {
                    let tags = kept(TagVersions {
                        id3v2: None,
                        id3v1: Some(version),
                    });
                    (version, tags)
                });
                if id3v1_read != id3v1_expected {
                    report.push(format!("{case}: the id3 crate reads {id3v1_read:?}"));
                }
            }
        }
    }
    assert!(report.is_empty(), "{}", report.join("\n"));
    Ok(())
}
