//! How tags are laid out, read by Colophon's own reader and checked against what wrote them.

mod common;

use colophon_tags::{FrameValue, Id3v2Version, TextEncoding, layout};

use common::{TestResult, fixture};

fn ids(path: &std::path::Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    Ok(layout(path)?
        .id3v2
        .map(|tag| tag.frames.into_iter().map(|frame| frame.id).collect())
        .unwrap_or_default())
}

#[test]
fn an_id3v2_3_tag_shows_its_frames_where_they_are() -> TestResult {
    let tag = layout(&fixture("v23_full.mp3"))?
        .id3v2
        .ok_or("no ID3v2 tag")?;

    assert_eq!(tag.version, Id3v2Version::V2_3);
    assert_eq!((tag.size, tag.padding), (226, 10));
    assert_eq!(
        ids(&fixture("v23_full.mp3"))?,
        [
            "TIT2", "TPE1", "TPE2", "TALB", "TYER", "TRCK", "TPOS", "TCON", "TXXX"
        ]
    );
    let title = &tag.frames[0];
    assert_eq!((title.offset, title.size), (10, 18));
    assert_eq!(title.encoding, Some(TextEncoding::Latin1));
    assert_eq!(title.value, FrameValue::Text("Paper Satellites".into()));
    assert_eq!(
        tag.frames[8].value,
        FrameValue::Text("comment: Recorded in one take.".into())
    );
    Ok(())
}

#[test]
fn every_version_and_encoding_reads() -> TestResult {
    let v22 = layout(&fixture("v22.mp3"))?.id3v2.ok_or("no ID3v2.2 tag")?;
    assert_eq!(v22.version, Id3v2Version::V2_2);
    assert_eq!(v22.frames[4].id, "TRK");
    assert_eq!(v22.frames[4].value, FrameValue::Text("3/12".into()));

    let unicode = layout(&fixture("v24_unicode.mp3"))?
        .id3v2
        .ok_or("no ID3v2.4 tag")?;
    assert_eq!(unicode.frames[1].encoding, Some(TextEncoding::Utf8));
    assert_eq!(unicode.frames[1].value, FrameValue::Text("坂本龍一".into()));
    Ok(())
}

#[test]
fn a_picture_shows_its_type_and_size() -> TestResult {
    let tag = layout(&fixture("v23_cover.mp3"))?
        .id3v2
        .ok_or("no ID3v2 tag")?;

    assert_eq!(
        tag.frames[2].value,
        FrameValue::Picture {
            mime: "image/png".into(),
            size: 96
        }
    );
    Ok(())
}

#[test]
fn an_id3v1_tag_shows_where_it_starts() -> TestResult {
    let path = fixture("v1_1_ascii.mp3");
    let length = std::fs::metadata(&path)?.len();

    let found = layout(&path)?;

    assert_eq!(found.id3v1, Some(length - 128));
    assert_eq!(found.id3v2, None);
    Ok(())
}

/// A copy of `v23_full.mp3` rewritten by the `id3` crate with `encoder`.
fn rewritten(encoder: id3::Encoder) -> Result<tempfile::TempDir, Box<dyn std::error::Error>> {
    let folder = tempfile::tempdir()?;
    let path = folder.path().join("1.mp3");
    std::fs::copy(fixture("v23_full.mp3"), &path)?;
    let mut tag = id3::Tag::read_from_path(&path)?;
    // Ÿ is 0xFF in Latin-1: unsynchronisation has something to do.
    id3::TagLike::set_title(&mut tag, "Ÿes");
    encoder.write_to_path(&tag, &path)?;
    Ok(folder)
}

#[test]
fn unsynchronisation_and_padding_read_as_written() -> TestResult {
    let folder = rewritten(
        id3::Encoder::new()
            .version(id3::Version::Id3v23)
            .unsynchronisation(true)
            .padding(100),
    )?;

    let tag = layout(&folder.path().join("1.mp3"))?
        .id3v2
        .ok_or("no ID3v2 tag")?;

    assert!(tag.unsynchronisation);
    assert_eq!(tag.padding, 100);
    let title = tag.frames.iter().find(|frame| frame.id == "TIT2");
    assert_eq!(
        title.map(|frame| &frame.value),
        Some(&FrameValue::Text("Ÿes".into()))
    );
    Ok(())
}

#[test]
fn a_compressed_frame_says_so() -> TestResult {
    // An ID3v2.4 tag of one TIT2 frame, compressed with a data length indicator, whose content
    // this reader does not open.
    let content = [0, 0, 0, 5, 0x78, 0x9c, 3, 0, 0, 0, 0, 1];
    let mut bytes = b"ID3\x04\x00\x00".to_vec();
    bytes.extend([0, 0, 0, 10 + content.len() as u8]);
    bytes.extend(b"TIT2");
    bytes.extend([0, 0, 0, content.len() as u8, 0x00, 0x09]);
    bytes.extend(content);
    bytes.extend([0xff, 0xfb, 0x90, 0x00]);
    let folder = tempfile::tempdir()?;
    let path = folder.path().join("1.mp3");
    std::fs::write(&path, bytes)?;

    let tag = layout(&path)?.id3v2.ok_or("no ID3v2 tag")?;

    let frame = &tag.frames[0];
    assert!(frame.flags.compression && frame.flags.data_length);
    assert_eq!(frame.value, FrameValue::Sealed);
    assert_eq!(tag.padding, 0);
    Ok(())
}
