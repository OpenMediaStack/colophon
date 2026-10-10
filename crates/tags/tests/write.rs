mod common;

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};

use colophon_tags::{
    Id3v1Version, Id3v2Version, TagFormat, Tags, WriteError, formats_after_write, id3v1_losses,
    read, write,
};
use lofty::config::ParseOptions;
use lofty::file::AudioFile;
use lofty::id3::v2::{Frame, FrameId};
use lofty::mpeg::MpegFile;
use tempfile::TempDir;

use common::{TestResult, fixture, fixtures_dir};

/// A copy of a fixture in a folder of its own, which lives as long as the folder.
fn copy_of(name: &str) -> Result<(TempDir, PathBuf), Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    let path = folder.path().join(name);
    fs::copy(fixture(name), &path)?;
    Ok((folder, path))
}

fn new_tags() -> Tags {
    Tags {
        title: Some("Neon Overpass".into()),
        artist: Some("坂本龍一".into()),
        album_artist: Some("Cassette Bloom".into()),
        album: Some("Analog Hearts".into()),
        year: Some(2024),
        track: Some(4),
        track_total: Some(9),
        disc: Some(2),
        disc_total: Some(3),
        genre: Some("Synthwave".into()),
        comment: Some("Remastered from the original tapes.".into()),
    }
}

/// The audio of an MP3: from its first frame to its trailing tags.
fn audio(bytes: &[u8]) -> &[u8] {
    let tag_end = if bytes.starts_with(b"ID3") {
        10 + bytes[6..10]
            .iter()
            .fold(0, |size, byte| size << 7 | usize::from(*byte))
    } else {
        0
    };
    let start = (tag_end..bytes.len().saturating_sub(1))
        .find(|&at| bytes[at] == 0xff && bytes[at + 1] & 0xe0 == 0xe0)
        .unwrap_or(tag_end);
    let mut end = bytes.len();
    if end >= start + 128 && &bytes[end - 128..end - 125] == b"TAG" {
        end -= 128;
    }
    if let Some(ape) = bytes[start..end]
        .windows(8)
        .position(|window| window == b"APETAGEX")
    {
        end = start + ape;
    }
    &bytes[start..end]
}

fn readable_fixtures() -> Result<Vec<String>, Box<dyn Error>> {
    let mut names: Vec<String> = fs::read_dir(fixtures_dir())?
        .map(|entry| entry.map(|entry| entry.file_name().to_string_lossy().into_owned()))
        .collect::<Result<_, _>>()?;
    names.retain(|name| name.ends_with(".mp3") && read(&fixture(name)).is_ok());
    names.sort();
    Ok(names)
}

#[test]
fn every_fixture_reads_back_what_was_written_with_its_audio_untouched() -> TestResult {
    let fixtures = readable_fixtures()?;
    assert!(fixtures.len() > 10, "{fixtures:?}");
    for name in fixtures {
        let (_folder, path) = copy_of(&name)?;
        let before = fs::read(&path)?;
        let formats = read(&path)?.formats;

        let written = write(&path, &new_tags())?;

        assert_eq!(written.tags, new_tags(), "{name}");
        assert_eq!(
            written.formats,
            formats_after_write(&formats, &new_tags()),
            "{name}"
        );
        assert_eq!(read(&path)?, written, "{name}");
        assert_eq!(
            written.formats.first(),
            Some(&TagFormat::Id3v2(Id3v2Version::V2_4)),
            "{name}"
        );
        assert!(
            audio(&fs::read(&path)?) == audio(&before),
            "{name}: the audio changed"
        );
    }
    Ok(())
}

#[test]
fn removed_fields_are_gone() -> TestResult {
    let (_folder, path) = copy_of("v23_full.mp3")?;
    let tags = Tags {
        title: Some("Only a title".into()),
        ..Tags::default()
    };

    let written = write(&path, &tags)?;

    assert_eq!(written.tags, tags);
    Ok(())
}

#[test]
fn ffmpegs_comment_goes_with_the_comment() -> TestResult {
    let (_folder, path) = copy_of("v23_full.mp3")?;
    let mut tags = read(&path)?.tags;
    assert!(tags.comment.is_some());
    tags.comment = None;

    let written = write(&path, &tags)?;

    assert_eq!(written.tags.comment, None);
    Ok(())
}

#[test]
fn frames_colophon_does_not_edit_are_kept() -> TestResult {
    let (_folder, path) = copy_of("v23_cover.mp3")?;

    write(&path, &new_tags())?;

    let mut file = fs::File::open(&path)?;
    let mpeg = MpegFile::read_from(&mut file, ParseOptions::new())?;
    let id3v2 = mpeg.id3v2().ok_or("no ID3v2 tag")?;
    let pictures = id3v2
        .into_iter()
        .filter(|frame| matches!(frame, Frame::Picture(_)))
        .count();
    assert_eq!(pictures, 1);
    assert_eq!(
        id3v2.get_text(&FrameId::new("TPUB")?),
        Some("Colophon Records")
    );
    Ok(())
}

#[test]
fn an_id3v1_tag_is_rewritten_from_the_new_values() -> TestResult {
    let (_folder, path) = copy_of("v23_v1_long_title.mp3")?;
    let tags = Tags {
        title: Some("A brand new title, well over thirty characters".into()),
        track: Some(4),
        ..new_tags()
    };

    let written = write(&path, &tags)?;

    assert_eq!(
        written.formats,
        [
            TagFormat::Id3v2(Id3v2Version::V2_4),
            TagFormat::Id3v1(Id3v1Version::V1_1)
        ]
    );
    let mut file = fs::File::open(&path)?;
    let mpeg = MpegFile::read_from(&mut file, ParseOptions::new())?;
    let id3v1 = mpeg.id3v1().ok_or("no ID3v1 tag")?;
    assert_eq!(
        id3v1.title.as_deref(),
        Some("A brand new title, well over t")
    );
    assert_eq!(id3v1.track_number, Some(4));
    assert!(!id3v1_losses(&tags).is_empty());
    Ok(())
}

#[test]
fn a_file_with_only_id3v1_gains_id3v2() -> TestResult {
    let (_folder, path) = copy_of("v1_1_ascii.mp3")?;

    let written = write(&path, &new_tags())?;

    assert_eq!(
        written.formats,
        [
            TagFormat::Id3v2(Id3v2Version::V2_4),
            TagFormat::Id3v1(Id3v1Version::V1_1)
        ]
    );
    Ok(())
}

fn files_in(folder: &Path) -> Result<Vec<String>, Box<dyn Error>> {
    let mut names: Vec<String> = fs::read_dir(folder)?
        .map(|entry| entry.map(|entry| entry.file_name().to_string_lossy().into_owned()))
        .collect::<Result<_, _>>()?;
    names.sort();
    Ok(names)
}

#[test]
fn no_copy_is_left_behind() -> TestResult {
    let (folder, path) = copy_of("v23_full.mp3")?;

    write(&path, &new_tags())?;

    assert_eq!(files_in(folder.path())?, ["v23_full.mp3"]);
    Ok(())
}

#[test]
fn a_read_only_file_is_left_alone() -> TestResult {
    let (_folder, path) = copy_of("v23_full.mp3")?;
    let before = fs::read(&path)?;
    let mut permissions = fs::metadata(&path)?.permissions();
    permissions.set_readonly(true);
    fs::set_permissions(&path, permissions)?;

    let result = write(&path, &new_tags());

    assert!(matches!(result, Err(WriteError::ReadOnly)), "{result:?}");
    assert_eq!(fs::read(&path)?, before);
    Ok(())
}

#[test]
fn a_missing_file_cannot_be_written() {
    let result = write(Path::new("/there/is/no/such/file.mp3"), &new_tags());

    assert!(matches!(result, Err(WriteError::Io(_))), "{result:?}");
}

#[test]
fn a_damaged_file_is_left_alone_and_cleaned_up_after() -> TestResult {
    let (folder, path) = copy_of("tiny_tag.mp3")?;

    let result = write(&path, &new_tags());

    assert!(matches!(result, Err(WriteError::Damaged(_))), "{result:?}");
    assert_eq!(fs::read(&path)?, b"TAG");
    assert_eq!(files_in(folder.path())?, ["tiny_tag.mp3"]);
    Ok(())
}

#[cfg(unix)]
#[test]
fn a_folder_that_cannot_be_written_leaves_the_file_alone() -> TestResult {
    use std::os::unix::fs::PermissionsExt;

    let (folder, path) = copy_of("v23_full.mp3")?;
    let before = fs::read(&path)?;
    fs::set_permissions(folder.path(), fs::Permissions::from_mode(0o555))?;

    let result = write(&path, &new_tags());

    fs::set_permissions(folder.path(), fs::Permissions::from_mode(0o755))?;
    assert!(matches!(result, Err(WriteError::Io(_))), "{result:?}");
    assert_eq!(fs::read(&path)?, before);
    Ok(())
}
