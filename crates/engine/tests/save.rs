mod common;

use std::error::Error;
use std::fs;
use std::path::Path;

use colophon_engine::tags::{Id3v1Version, Id3v2Version, TagFormat, WriteError, read};
use colophon_engine::{Command, Edit, Engine, SaveProgress, VersionChoice};
use tempfile::TempDir;

use common::{TestResult, engine_reading, folder_with_fixtures, poll_until_saved};

fn two_tracks() -> Result<(TempDir, Engine), Box<dyn Error>> {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3"), ("v24_unicode.mp3", "2.mp3")])?;
    let engine = engine_reading(&folder)?;
    Ok((folder, engine))
}

fn album_on_disk(path: &Path) -> Result<Option<String>, Box<dyn Error>> {
    Ok(read(path)?.tags.album)
}

fn title_on_disk(path: &Path) -> Result<Option<String>, Box<dyn Error>> {
    Ok(read(path)?.tags.title)
}

#[test]
fn saving_writes_every_pending_change() -> TestResult {
    let (folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));

    engine.execute(Command::Save);
    assert_eq!(engine.saving(), Some(SaveProgress { done: 0, total: 2 }));
    poll_until_saved(&mut engine)?;

    for name in ["1.mp3", "2.mp3"] {
        assert_eq!(
            album_on_disk(&folder.path().join(name))?.as_deref(),
            Some("Analog Hearts")
        );
    }
    assert_eq!(engine.edits().modified_count(), 0);
    assert!(engine.save_failures().is_empty());
    assert!(engine.edits().can_undo());
    Ok(())
}

#[test]
fn undoing_a_saved_edit_brings_the_old_value_back_to_save() -> TestResult {
    let (folder, mut engine) = two_tracks()?;
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));
    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    engine.execute(Command::Undo);
    assert_eq!(engine.edits().modified_count(), 1);
    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    assert_eq!(
        album_on_disk(&folder.path().join("1.mp3"))?.as_deref(),
        Some("Small Hours")
    );
    assert_eq!(engine.edits().modified_count(), 0);
    Ok(())
}

#[test]
fn a_file_that_cannot_be_written_keeps_its_change() -> TestResult {
    let (folder, mut engine) = two_tracks()?;
    let locked = folder.path().join("2.mp3");
    let mut permissions = fs::metadata(&locked)?.permissions();
    permissions.set_readonly(true);
    fs::set_permissions(&locked, permissions)?;
    engine.execute(Command::SelectAll);
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));

    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    let failures = engine.save_failures();
    assert_eq!(failures.len(), 1);
    assert_eq!(failures[0].track, 1);
    assert!(matches!(failures[0].error, WriteError::ReadOnly));
    assert_eq!(engine.edits().modified_count(), 1);
    assert_eq!(
        album_on_disk(&folder.path().join("1.mp3"))?.as_deref(),
        Some("Analog Hearts")
    );
    Ok(())
}

#[test]
fn a_change_made_while_saving_stays_pending() -> TestResult {
    let (folder, mut engine) = two_tracks()?;
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Title(Some("One".into()))));

    engine.execute(Command::Save);
    engine.execute(Command::Edit(Edit::Title(Some("Two".into()))));
    poll_until_saved(&mut engine)?;

    assert_eq!(
        title_on_disk(&folder.path().join("1.mp3"))?.as_deref(),
        Some("One")
    );
    assert_eq!(
        engine.tags_of(0).and_then(|tags| tags.title.as_deref()),
        Some("Two")
    );
    assert_eq!(engine.edits().modified_count(), 1);
    Ok(())
}

#[test]
fn saving_nothing_does_nothing() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;

    engine.execute(Command::Save);

    assert_eq!(engine.saving(), None);
    Ok(())
}

#[test]
fn saving_writes_the_versions_chosen() -> TestResult {
    let (folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);

    engine.execute(Command::ChooseVersion(VersionChoice::Id3v2(Some(
        Id3v2Version::V2_3,
    ))));
    engine.execute(Command::ChooseVersion(VersionChoice::Id3v1(Some(
        Id3v1Version::V1_0,
    ))));
    assert_eq!(engine.edits().modified_count(), 2);
    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    for name in ["1.mp3", "2.mp3"] {
        assert_eq!(
            read(&folder.path().join(name))?.formats,
            [
                TagFormat::Id3v2(Id3v2Version::V2_3),
                TagFormat::Id3v1(Id3v1Version::V1_0)
            ]
        );
    }
    assert_eq!(engine.edits().modified_count(), 0);
    Ok(())
}
