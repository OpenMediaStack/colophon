mod common;

use std::fs;
use std::time::Duration;

use colophon_tags::{Id3v1Version, Id3v2Version, ReadError, TagFormat, Tags, read};

use common::{TestResult, fixture};

fn every_field() -> Tags {
    Tags {
        title: Some("Paper Satellites".into()),
        artist: Some("Marlowe Kite".into()),
        album_artist: Some("Various Artists".into()),
        album: Some("Small Hours".into()),
        year: Some(2019),
        track: Some(3),
        track_total: Some(12),
        disc: Some(1),
        disc_total: Some(2),
        genre: Some("Folk".into()),
        comment: Some("Recorded in one take.".into()),
    }
}

fn text(value: &str) -> Option<String> {
    Some(value.into())
}

#[test]
fn a_file_without_tags_has_no_values() -> TestResult {
    let metadata = read(&fixture("no_tag.mp3"))?;

    assert_eq!(metadata.tags, Tags::default());
    assert!(metadata.formats.is_empty());
    Ok(())
}

#[test]
fn id3v2_3_gives_every_field() -> TestResult {
    let metadata = read(&fixture("v23_full.mp3"))?;

    assert_eq!(metadata.tags, every_field());
    assert_eq!(metadata.formats, [TagFormat::Id3v2(Id3v2Version::V2_3)]);
    Ok(())
}

#[test]
fn id3v2_4_gives_every_field() -> TestResult {
    let metadata = read(&fixture("v24_full.mp3"))?;

    assert_eq!(metadata.tags, every_field());
    assert_eq!(metadata.formats, [TagFormat::Id3v2(Id3v2Version::V2_4)]);
    Ok(())
}

#[test]
fn id3v2_2_gives_its_fields() -> TestResult {
    let metadata = read(&fixture("v22.mp3"))?;

    assert_eq!(
        metadata.tags,
        Tags {
            album_artist: None,
            disc: None,
            disc_total: None,
            genre: None,
            ..every_field()
        }
    );
    assert_eq!(metadata.formats, [TagFormat::Id3v2(Id3v2Version::V2_2)]);
    Ok(())
}

#[test]
fn an_ape_tag_gives_every_field() -> TestResult {
    let metadata = read(&fixture("ape.mp3"))?;

    assert_eq!(metadata.tags, every_field());
    assert_eq!(metadata.formats, [TagFormat::Ape]);
    Ok(())
}

#[test]
fn id3v1_wins_over_ape() -> TestResult {
    let metadata = read(&fixture("ape_v1.mp3"))?;

    assert_eq!(metadata.tags.title, text("Plain ASCII title"));
    assert_eq!(
        metadata.formats,
        [TagFormat::Id3v1(Id3v1Version::V1_0), TagFormat::Ape]
    );
    Ok(())
}

#[test]
fn the_comment_comes_from_a_comm_frame() -> TestResult {
    let tags = read(&fixture("v23_comm.mp3"))?.tags;

    assert_eq!(tags.title, text("A real COMM frame"));
    assert_eq!(tags.comment, text("Recorded in one take."));
    Ok(())
}

#[test]
fn id3v2_wins_over_id3v1() -> TestResult {
    let metadata = read(&fixture("v23_v1_long_title.mp3"))?;

    assert_eq!(
        metadata.tags.title,
        text("A title longer than thirty characters")
    );
    assert_eq!(
        metadata.formats,
        [
            TagFormat::Id3v2(Id3v2Version::V2_3),
            TagFormat::Id3v1(Id3v1Version::V1_1)
        ]
    );
    Ok(())
}

#[test]
fn text_outside_latin1_reads_in_id3v2_3_and_2_4() -> TestResult {
    for name in ["v23_unicode.mp3", "v24_unicode.mp3"] {
        let tags = read(&fixture(name))?.tags;

        assert_eq!(tags.title, text("Café"), "{name}");
        assert_eq!(tags.artist, text("坂本龍一"), "{name}");
        assert_eq!(tags.album, text("Ελληνικά"), "{name}");
    }
    Ok(())
}

#[test]
fn id3v1_0_gives_its_fields_without_a_track() -> TestResult {
    let metadata = read(&fixture("v1_0_ascii.mp3"))?;

    assert_eq!(
        metadata.tags,
        Tags {
            title: text("Plain ASCII title"),
            artist: text("Plain ASCII artist"),
            album: text("Plain ASCII album"),
            year: Some(1999),
            genre: text("Rock"),
            comment: text("A comment of exactly 30 bytes."),
            ..Tags::default()
        }
    );
    assert_eq!(metadata.formats, [TagFormat::Id3v1(Id3v1Version::V1_0)]);
    Ok(())
}

#[test]
fn id3v1_1_gives_a_track_and_the_winamp_genres() -> TestResult {
    let metadata = read(&fixture("v1_1_ascii.mp3"))?;

    assert_eq!(metadata.tags.track, Some(7));
    assert_eq!(metadata.tags.genre, text("Folk-Rock"));
    assert_eq!(metadata.tags.comment, text("Short comment"));
    assert_eq!(metadata.formats, [TagFormat::Id3v1(Id3v1Version::V1_1)]);
    Ok(())
}

#[test]
fn id3v1_reads_latin1_and_utf8_alike() -> TestResult {
    let latin1 = read(&fixture("v1_latin1.mp3"))?.tags;
    let utf8 = read(&fixture("v1_utf8.mp3"))?.tags;

    for tags in [&latin1, &utf8] {
        assert_eq!(tags.title, text("Café"));
        assert_eq!(tags.artist, text("Björk"));
        assert_eq!(tags.album, text("Señor"));
    }
    Ok(())
}

#[test]
fn id3v1_utf8_cut_in_a_character_reads_as_latin1() -> TestResult {
    let tags = read(&fixture("v1_utf8_cut.mp3"))?.tags;

    assert_eq!(tags.title, text("ABCDEFGHIJKLMNOPQRSTUVWXYZabc\u{c3}"));
    assert_eq!(tags.artist, text("Cut in the middle"));
    Ok(())
}

#[test]
fn an_unknown_id3v1_genre_is_left_out() -> TestResult {
    let tags = read(&fixture("v1_genre_out_of_range.mp3"))?.tags;

    assert_eq!(tags.title, text("Unknown genre"));
    assert_eq!(tags.genre, None);
    Ok(())
}

fn assert_about_one_second(duration: Option<Duration>) {
    assert!(
        duration.is_some_and(
            |duration| duration.abs_diff(Duration::from_secs(1)) < Duration::from_millis(60)
        ),
        "{duration:?}"
    );
}

#[test]
fn a_constant_bitrate_gives_its_audio_properties() -> TestResult {
    let audio = read(&fixture("cbr_stereo.mp3"))?.audio;

    assert_about_one_second(audio.duration);
    assert!(
        audio
            .bitrate
            .is_some_and(|bitrate| (128..=132).contains(&bitrate))
    );
    assert_eq!(audio.sample_rate, Some(44_100));
    assert_eq!(audio.channels, Some(2));
    Ok(())
}

#[test]
fn a_variable_bitrate_gives_its_audio_properties() -> TestResult {
    let audio = read(&fixture("vbr_mono.mp3"))?.audio;

    assert_about_one_second(audio.duration);
    assert!(audio.bitrate.is_some());
    assert_eq!(audio.sample_rate, Some(48_000));
    assert_eq!(audio.channels, Some(1));
    Ok(())
}

#[test]
fn a_missing_file_cannot_be_opened() {
    let result = read(&fixture("there_is_no_such_file.mp3"));

    assert!(matches!(result, Err(ReadError::Open(_))), "{result:?}");
}

#[test]
fn a_file_of_three_bytes_is_damaged() {
    let result = read(&fixture("tiny_tag.mp3"));

    assert!(matches!(result, Err(ReadError::Damaged(_))), "{result:?}");
}

#[test]
fn a_text_file_is_damaged() -> TestResult {
    let folder = tempfile::tempdir()?;
    let path = folder.path().join("notes.mp3");
    fs::write(&path, "Not an MP3, only some text.")?;

    let result = read(&path);

    assert!(matches!(result, Err(ReadError::Damaged(_))), "{result:?}");
    Ok(())
}

#[test]
fn tag_formats_are_named_as_in_the_tags_column() {
    let names: Vec<String> = [
        TagFormat::Id3v2(Id3v2Version::V2_2),
        TagFormat::Id3v2(Id3v2Version::V2_3),
        TagFormat::Id3v2(Id3v2Version::V2_4),
        TagFormat::Id3v1(Id3v1Version::V1_0),
        TagFormat::Id3v1(Id3v1Version::V1_1),
        TagFormat::Ape,
    ]
    .iter()
    .map(ToString::to_string)
    .collect();

    assert_eq!(
        names,
        ["ID3v2.2", "ID3v2.3", "ID3v2.4", "ID3v1.0", "ID3v1.1", "APE"]
    );
}
