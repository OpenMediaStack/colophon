mod common;

use std::collections::BTreeSet;

use colophon_engine::tags::{Id3v1Loss, Id3v1Version, Id3v2Version, TagFormat};
use colophon_engine::{
    Command, Edit, Engine, Field, Inspection, Shared, SortColumn, Summary, VersionChoice,
};

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
fn opening_another_folder_keeps_the_edits() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);
    engine.execute(Command::Edit(Edit::Genre(Some("Synthwave".into()))));
    let other = folder_with_fixtures(&[("v23_full.mp3", "1.mp3")])?;

    engine.execute(Command::OpenFolder(other.path().to_path_buf()));
    common::poll_until_done(&mut engine)?;

    assert_eq!(engine.library().tracks.len(), 3);
    assert_eq!(engine.edits().modified_count(), 2);
    assert!(engine.edits().can_undo());
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

#[test]
fn the_genres_to_suggest_are_id3v1_s_and_those_read() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);
    engine.execute(Command::Edit(Edit::Genre(Some("Synthwave".into()))));

    let genres = engine.genres();

    assert!(genres.contains(&"Blues".to_string()));
    assert_eq!(genres.iter().filter(|genre| *genre == "Folk").count(), 1);
    assert!(!genres.contains(&"Synthwave".to_string()));
    let lowercase: Vec<String> = genres.iter().map(|genre| genre.to_lowercase()).collect();
    assert!(lowercase.is_sorted());

    engine.execute(Command::Save);
    common::poll_until_saved(&mut engine)?;
    assert!(engine.genres().contains(&"Synthwave".to_string()));
    Ok(())
}

#[test]
fn the_inspection_says_which_versions_saving_writes() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);
    let Shared::Same(versions) = summary(&engine)?.versions else {
        return Err("the tracks should share Colophon's versions".into());
    };
    assert_eq!(versions.id3v2, Some(Id3v2Version::V2_4));

    engine.execute(Command::Select(0));
    engine.execute(Command::ChooseVersion(VersionChoice::Id3v2(Some(
        Id3v2Version::V2_3,
    ))));
    engine.execute(Command::SelectAll);

    assert_eq!(summary(&engine)?.versions, Shared::Mixed);
    Ok(())
}

#[test]
fn the_inspection_counts_the_files_saving_converts() -> TestResult {
    let (_folder, mut engine) = two_tracks()?;
    engine.execute(Command::SelectAll);

    engine.execute(Command::ChooseVersion(VersionChoice::Id3v2(Some(
        Id3v2Version::V2_3,
    ))));

    let summary = summary(&engine)?;
    assert_eq!(engine.edits().modified_count(), 1);
    assert_eq!(summary.converted, 1);
    Ok(())
}

#[test]
fn a_cover_is_an_edit_like_any_other() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_cover.mp3", "1.mp3"), ("v23_full.mp3", "2.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::SelectAll);
    assert_eq!(summary(&engine)?.cover, Shared::Mixed);

    let cover = engine.tags_of(0).and_then(|tags| tags.cover.clone());
    engine.execute(Command::Edit(Edit::Cover(cover.clone())));

    let summary = summary(&engine)?;
    assert_eq!(summary.cover, cover.map_or(Shared::Empty, Shared::Same));
    assert_eq!(summary.modified, BTreeSet::from([Field::Cover]));
    assert_eq!(engine.edits().modified_count(), 1);
    Ok(())
}

/// The place in the library of the track of this file name.
fn track_named(engine: &Engine, name: &str) -> Result<usize, String> {
    engine
        .library()
        .tracks
        .iter()
        .position(|track| track.path.file_name().is_some_and(|file| file == name))
        .ok_or(format!("no track {name}"))
}

fn number(engine: &Engine, name: &str) -> Result<(Option<u32>, Option<u32>), String> {
    let tags = engine
        .tags_of(track_named(engine, name)?)
        .ok_or(format!("no tags for {name}"))?;
    Ok((tags.track, tags.track_total))
}

#[test]
fn tracks_are_numbered_in_the_table_order_disc_by_disc() -> TestResult {
    let folder = folder_with_fixtures(&[
        ("v23_full.mp3", "1.mp3"),
        ("v24_full.mp3", "2.mp3"),
        ("v24_unicode.mp3", "3.mp3"),
    ])?;
    let mut engine = engine_reading(&folder)?;
    engine.execute(Command::SelectAll);
    engine.execute(Command::Edit(Edit::Disc(Some(1))));
    engine.execute(Command::Select(track_named(&engine, "3.mp3")?));
    engine.execute(Command::Edit(Edit::Disc(Some(2))));
    engine.execute(Command::SortBy(SortColumn::File));
    engine.execute(Command::SortBy(SortColumn::File));
    engine.execute(Command::SelectAll);

    engine.execute(Command::NumberTracks);

    assert_eq!(number(&engine, "2.mp3")?, (Some(1), Some(2)));
    assert_eq!(number(&engine, "1.mp3")?, (Some(2), Some(2)));
    assert_eq!(number(&engine, "3.mp3")?, (Some(1), Some(1)));
    engine.execute(Command::Undo);
    assert_eq!(number(&engine, "1.mp3")?, (Some(3), Some(12)));
    Ok(())
}

#[test]
fn selecting_the_album_selects_every_listed_track_of_it() -> TestResult {
    let folder = folder_with_fixtures(&[
        ("v23_full.mp3", "1.mp3"),
        ("v24_full.mp3", "2.mp3"),
        ("v24_unicode.mp3", "3.mp3"),
    ])?;
    let mut engine = engine_reading(&folder)?;
    let (one, two) = (
        track_named(&engine, "1.mp3")?,
        track_named(&engine, "2.mp3")?,
    );
    engine.execute(Command::Select(one));
    engine.execute(Command::ToggleSelected(two));
    engine.execute(Command::Edit(Edit::Album(Some("Analog Hearts".into()))));
    engine.execute(Command::Edit(Edit::AlbumArtist(Some(
        "Cassette Bloom".into(),
    ))));
    engine.execute(Command::Select(two));

    engine.execute(Command::SelectAlbum);

    let selected: Vec<usize> = engine.selection().iter().collect();
    let mut expected = vec![one, two];
    expected.sort_unstable();
    assert_eq!(selected, expected);
    Ok(())
}

#[test]
fn a_track_unlike_the_rest_of_its_album_is_warned_about() -> TestResult {
    let folder = folder_with_fixtures(&[("v23_full.mp3", "1.mp3"), ("v23_full.mp3", "2.mp3")])?;
    let mut engine = engine_reading(&folder)?;
    assert!(engine.warnings().is_empty());
    let one = track_named(&engine, "1.mp3")?;

    engine.execute(Command::Select(one));
    engine.execute(Command::Edit(Edit::AlbumArtist(Some(
        "Marlowe Kite".into(),
    ))));
    engine.execute(Command::Edit(Edit::Track(None)));

    let warnings = engine.warnings();
    assert_eq!(warnings.keys().copied().collect::<Vec<_>>(), [one]);
    assert!(warnings[&one].missing_number);
    // One album artist each: neither is the usual one.
    assert!(!warnings[&one].odd_album_artist);
    Ok(())
}
