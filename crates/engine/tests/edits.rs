mod common;

use std::collections::BTreeSet;

use colophon_engine::tags::{Id3v1Loss, Id3v1Version, Id3v2Version, TagFormat};
use colophon_engine::{Command, Edit, Engine, Field, Inspection, Shared, Summary};

use common::{TestResult, engine_reading, folder_with_fixtures};

fn summary(engine: &Engine) -> Result<Summary, String> {
    match engine.inspection() {
        Inspection::Tracks(summary) => Ok(*summary),
        other => Err(format!("not a summary: {other:?}")),
    }
}

fn title(engine: &Engine, track: usize) -> Option<String> {
    engine.tags_of(track).and_then(|tags| tags.title.clone())
}

fn two_tracks() -> Result<(tempfile::TempDir, Engine), Box<dyn std::error::Error>> {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3"), ("v24_unicode.mp3", "2.mp3")])?;
    let engine = engine_reading(&folder)?;
    Ok((folder, engine))
}

#[test]
fn an_edit_shows_in_the_tracks_and_the_inspector() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);

    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));

    let summary = summary(&engine)?;
    assert_eq!(summary.album, Shared::Same("Analog Hearts".to_string()));
    assert_eq!(summary.modified, BTreeSet::from([Field::Album]));
    assert_eq!(engine.edits().modified_count(), 2);
    assert_eq!(title(&engine, 1).as_deref(), Some("Café"));
    Ok(())
}

#[test]
fn undo_redo_and_revert_go_through_the_engine() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Title(Some("New".into()))));

    engine.execute(Command::Undo);
    assert_eq!(title(&engine, 0).as_deref(), Some("Paper Satellites"));
    engine.execute(Command::Redo);
    assert_eq!(title(&engine, 0).as_deref(), Some("New"));
    engine.execute(Command::Revert);
    assert_eq!(title(&engine, 0).as_deref(), Some("Paper Satellites"));
    assert_eq!(engine.edits().modified_count(), 0);
    Ok(())
}

#[test]
fn a_single_edited_track_is_headed_by_its_new_title() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::Select(0));

    engine.execute(Command::Edit(Edit::Title(Some("New".into()))));

    assert_eq!(summary(&engine)?.heading.as_deref(), Some("New"));
    Ok(())
}

#[test]
fn opening_another_folder_drops_the_edits() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);
    engine.execute(Command::Edit(Edit::Genre(Some("Folk".into()))));
    let other = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;

    engine.execute(Command::OpenFolder(other.path().to_path_buf()));

    assert_eq!(engine.edits().modified_count(), 0);
    assert!(!engine.edits().can_undo());
    Ok(())
}

#[test]
fn the_inspection_says_what_saving_will_write() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_v1_long_title.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::Select(0));
    assert_eq!(summary(&engine)?.saved_as, Shared::Empty);

    engine.execute(Command::Edit(Edit::Title(Some(
        "A brand new title, well over thirty characters".into(),
    ))));

    let summary = summary(&engine)?;
    assert_eq!(
        summary.saved_as,
        Shared::Same(vec![
            TagFormat::Id3v2(Id3v2Version::V2_4),
            TagFormat::Id3v1(Id3v1Version::V1_1)
        ])
    );
    assert_eq!(summary.id3v1_losses, BTreeSet::from([Id3v1Loss::Title]));
    Ok(())
}
