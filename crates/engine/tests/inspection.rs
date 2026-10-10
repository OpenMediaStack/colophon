mod common;

use colophon_engine::tags::{BitrateMode, Id3v2Version, ReadError, TagFormat};
use colophon_engine::{AudioLine, Command, Inspection, Shared, Summary};

use common::{TestResult, engine_reading, folder_with_fixtures};

fn summary(inspection: Inspection<'_>) -> Result<Summary, String> {
    match inspection {
        Inspection::Tracks(summary) => Ok(*summary),
        other => Err(format!("not a summary: {other:?}")),
    }
}

fn same(value: &str) -> Shared<String> {
    Shared::Same(value.to_string())
}

#[test]
fn nothing_shows_until_a_track_is_selected() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;
    let engine = engine_reading(&folder)?;

    assert!(matches!(engine.inspection(), Inspection::Nothing));
    Ok(())
}

#[test]
fn one_track_shows_its_tags_and_its_file() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    let size = std::fs::metadata(folder.path().join("1.mp3"))?.len();

    engine.execute(Command::Select(0));

    let summary = summary(engine.inspection())?;
    assert_eq!(summary.count, 1);
    assert_eq!(summary.heading.as_deref(), Some("Paper Satellites"));
    assert_eq!(summary.title, same("Paper Satellites"));
    assert_eq!(summary.album_artist, same("Various Artists"));
    assert_eq!(summary.year, Shared::Same(2019));
    assert_eq!(summary.track, Shared::Same(3));
    assert_eq!(summary.track_total, Shared::Same(12));
    assert_eq!(summary.comment, same("Recorded in one take."));
    assert_eq!(
        summary.audio,
        Shared::Same(AudioLine {
            bitrate: 64,
            sample_rate: 44_100,
            mode: Some(BitrateMode::Constant),
        })
    );
    assert_eq!(
        summary.formats,
        Shared::Same(vec![TagFormat::Id3v2(Id3v2Version::V2_3)])
    );
    assert_eq!(summary.size, size);
    Ok(())
}

#[test]
fn a_track_without_a_title_is_headed_by_its_file_name() -> TestResult {
    let folder = folder_with_fixtures(&[("no_tag.mp3", "07 Paper Satellites.mp3")])?;
    let mut engine = engine_reading(&folder)?;

    engine.execute(Command::Select(0));

    let summary = summary(engine.inspection())?;
    assert_eq!(summary.heading.as_deref(), Some("07 Paper Satellites"));
    assert_eq!(summary.title, Shared::Empty);
    Ok(())
}

#[test]
fn several_tracks_share_what_they_have_in_common() -> TestResult {
    let folder = folder_with_fixtures(&[
        ("v23_full.mp3", "1.mp3"),
        ("v24_full.mp3", "2.mp3"),
        ("v24_unicode.mp3", "3.mp3"),
    ])?;
    let mut engine = engine_reading(&folder)?;

    engine.execute(Command::Select(0));
    engine.execute(Command::SelectRange(1));
    let two = summary(engine.inspection())?;
    engine.execute(Command::SelectAll);
    let three = summary(engine.inspection())?;

    assert_eq!(two.count, 2);
    assert_eq!(two.heading, None);
    assert_eq!(two.title, same("Paper Satellites"));
    assert_eq!(two.formats, Shared::Mixed);
    assert_eq!(three.title, Shared::Mixed);
    assert_eq!(three.album_artist, Shared::Mixed);
    assert_eq!(three.genre, Shared::Mixed);
    Ok(())
}

#[test]
fn a_single_unreadable_track_shows_its_error() -> TestResult {
    let folder = folder_with_fixtures(&[("tiny_tag.mp3", "broken.mp3")])?;
    let mut engine = engine_reading(&folder)?;

    engine.execute(Command::Select(0));

    assert!(matches!(
        engine.inspection(),
        Inspection::Unreadable {
            error: ReadError::Damaged(_),
            ..
        }
    ));
    Ok(())
}

#[test]
fn unreadable_tracks_among_others_are_counted() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3"), ("tiny_tag.mp3", "2.mp3")])?;
    let mut engine = engine_reading(&folder)?;

    engine.execute(Command::SelectAll);

    let summary = summary(engine.inspection())?;
    assert_eq!(summary.count, 2);
    assert_eq!(summary.unreadable, 1);
    assert_eq!(summary.title, same("Paper Satellites"));
    Ok(())
}
