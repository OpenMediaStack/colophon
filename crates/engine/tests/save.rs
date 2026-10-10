mod common;

use std::error::Error;
use std::fs;
use std::path::Path;

use colophon_engine::tags::{
    Id3v1Policy, Id3v1Version, Id3v2Version, TagFormat, WriteDetails, WriteError, WritePolicy, read,
};
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
fn saving_writes_the_disc_and_the_number_of_discs() -> TestResult {
    let (folder, mut engine) = two_tracks()?;
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Disc(Some(2))));
    engine.execute(Command::Edit(Edit::DiscTotal(Some(3))));

    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    let tags = read(&folder.path().join("1.mp3"))?.tags;
    assert_eq!((tags.disc, tags.disc_total), (Some(2), Some(3)));
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

fn formats_on_disk(path: &Path) -> Result<Vec<TagFormat>, Box<dyn Error>> {
    Ok(read(path)?.formats)
}

/// Whether a file has an ID3v1 tag, which reads as ID3v1.1 when it holds a track number.
fn has_id3v1(path: &Path) -> Result<bool, Box<dyn Error>> {
    Ok(formats_on_disk(path)?
        .iter()
        .any(|format| matches!(format, TagFormat::Id3v1(_))))
}

#[test]
fn the_write_policy_chooses_the_versions_saved() -> TestResult {
    let folder = folder_with_fixtures(&[("v24_unicode.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::SetWritePolicy(WritePolicy {
        id3v2: Id3v2Version::V2_3,
        id3v1: Id3v1Policy::Always,
    }));
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));

    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    let path = folder.path().join("1.mp3");
    assert_eq!(
        formats_on_disk(&path)?[0],
        TagFormat::Id3v2(Id3v2Version::V2_3)
    );
    assert!(has_id3v1(&path)?);
    Ok(())
}

/// A file with an ID3v1 tag, edited while the policy never writes one.
fn edited_while_never_writing_id3v1() -> Result<(TempDir, Engine), Box<dyn Error>> {
    let folder = folder_with_fixtures(&[("v23_v1_long_title.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::SetWritePolicy(WritePolicy {
        id3v1: Id3v1Policy::Never,
        ..WritePolicy::default()
    }));
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));
    Ok((folder, engine))
}

#[test]
fn never_writing_id3v1_strips_it_from_the_files_saved() -> TestResult {
    let (folder, mut engine) = edited_while_never_writing_id3v1()?;
    assert_eq!(engine.losing_id3v1_to_policy(), [0]);

    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    assert_eq!(
        formats_on_disk(&folder.path().join("1.mp3"))?,
        [TagFormat::Id3v2(Id3v2Version::V2_4)]
    );
    Ok(())
}

#[test]
fn a_file_can_keep_the_id3v1_tag_the_policy_would_strip() -> TestResult {
    let (folder, mut engine) = edited_while_never_writing_id3v1()?;

    engine.execute(Command::SaveKeepingId3v1);
    poll_until_saved(&mut engine)?;

    assert!(has_id3v1(&folder.path().join("1.mp3"))?);
    Ok(())
}

fn padding_on_disk(path: &Path) -> Result<Option<u32>, Box<dyn Error>> {
    Ok(colophon_engine::tags::layout(path)?
        .id3v2
        .map(|tag| tag.padding))
}

#[test]
fn a_rewrite_writes_a_file_again_with_the_details_of_developer_mode() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::ToggleDeveloperMode);
    engine.execute(Command::SetWriteDetails(WriteDetails {
        padding: Some(300),
        ..WriteDetails::default()
    }));
    engine.execute(Command::Select(0));

    engine.execute(Command::Rewrite);
    assert_eq!(engine.edits().modified_count(), 1);
    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    assert_eq!(padding_on_disk(&folder.path().join("1.mp3"))?, Some(300));
    assert_eq!(engine.edits().modified_count(), 0);
    Ok(())
}

#[test]
fn the_details_wait_for_developer_mode() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::SetWriteDetails(WriteDetails {
        padding: Some(300),
        ..WriteDetails::default()
    }));
    engine.execute(Command::Select(0));
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));

    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;

    assert_ne!(padding_on_disk(&folder.path().join("1.mp3"))?, Some(300));
    Ok(())
}

#[test]
fn reverting_a_rewrite_leaves_the_file_alone() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::Select(0));

    engine.execute(Command::Rewrite);
    engine.execute(Command::Revert);

    assert_eq!(engine.edits().modified_count(), 0);
    Ok(())
}
