mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::{AlbumKey, Command, Edit, Engine, SortColumn, Source, Step};
use tempfile::TempDir;

use common::{TestResult, engine_reading, poll_until_saved};

/// A library of four tracks: two by Marlowe Kite and 坂本龍一 in `a/`, a plain ASCII one and a
/// damaged one in `b/`.
fn library() -> Result<(TempDir, Engine), Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in [
        ("v23_full.mp3", "a/1.mp3"),
        ("v23_unicode.mp3", "a/2.mp3"),
        ("v1_1_ascii.mp3", "b/3.mp3"),
        ("tiny_tag.mp3", "b/4.mp3"),
    ] {
        let path = folder.path().join(name);
        fs::create_dir_all(path.parent().ok_or("no folder")?)?;
        fs::copy(fixtures.join(fixture), path)?;
    }
    let engine = engine_reading(&folder)?;
    Ok((folder, engine))
}

fn names(engine: &Engine) -> Vec<String> {
    engine
        .listed()
        .iter()
        .filter_map(|track| engine.library().tracks.get(*track))
        .filter_map(|track| track.path.file_name())
        .map(|name| name.to_string_lossy().into_owned())
        .collect()
}

#[test]
fn every_track_is_listed_in_library_order_at_first() -> TestResult {
    let (_folder, engine) = library()?;

    assert_eq!(names(&engine), ["1.mp3", "2.mp3", "3.mp3", "4.mp3"]);
    Ok(())
}

#[test]
fn the_filter_matches_titles_artists_albums_and_file_names() -> TestResult {
    let (_folder, mut engine) = library()?;

    engine.execute(Command::Filter("MARLOWE".into()));
    assert_eq!(names(&engine), ["1.mp3"]);

    engine.execute(Command::Filter("ελληνικά".into()));
    assert_eq!(names(&engine), ["2.mp3"]);

    engine.execute(Command::Filter("4.mp3".into()));
    assert_eq!(names(&engine), ["4.mp3"]);

    engine.execute(Command::Filter(String::new()));
    assert_eq!(names(&engine).len(), 4);
    Ok(())
}

#[test]
fn a_column_sorts_up_then_down() -> TestResult {
    let (_folder, mut engine) = library()?;

    engine.execute(Command::SortBy(SortColumn::Title));
    assert_eq!(names(&engine), ["4.mp3", "2.mp3", "1.mp3", "3.mp3"]);

    engine.execute(Command::SortBy(SortColumn::Title));
    assert_eq!(names(&engine), ["3.mp3", "1.mp3", "2.mp3", "4.mp3"]);
    Ok(())
}

#[test]
fn a_missing_value_sorts_last() -> TestResult {
    let (_folder, mut engine) = library()?;

    engine.execute(Command::SortBy(SortColumn::Album));

    assert_eq!(names(&engine).last().map(String::as_str), Some("4.mp3"));
    Ok(())
}

#[test]
fn sources_list_a_folder_an_album_an_artist_or_the_unreadable_tracks() -> TestResult {
    let (folder, mut engine) = library()?;

    engine.execute(Command::ShowSource(Source::Folder(folder.path().join("b"))));
    assert_eq!(names(&engine), ["3.mp3", "4.mp3"]);

    engine.execute(Command::ShowSource(Source::Album(AlbumKey {
        title: "Small Hours".into(),
        artist: Some("Various Artists".into()),
    })));
    assert_eq!(names(&engine), ["1.mp3"]);

    engine.execute(Command::ShowSource(Source::Artist("坂本龍一".into())));
    assert_eq!(names(&engine), ["2.mp3"]);

    engine.execute(Command::ShowSource(Source::Unreadable));
    assert_eq!(names(&engine), ["4.mp3"]);
    Ok(())
}

#[test]
fn recently_changed_lists_pending_then_saved_tracks() -> TestResult {
    let (_folder, mut engine) = library()?;
    engine.execute(Command::Select(1));
    engine.execute(Command::Edit(Edit::Genre(Some("Ambient".into()))));

    engine.execute(Command::ShowSource(Source::RecentlyChanged));
    assert_eq!(names(&engine), ["2.mp3"]);

    engine.execute(Command::Save);
    poll_until_saved(&mut engine)?;
    assert_eq!(names(&engine), ["2.mp3"]);
    Ok(())
}

#[test]
fn the_library_groups_its_tracks_by_album_and_artist() -> TestResult {
    let (_folder, engine) = library()?;

    let groups = engine.groups();

    let albums: Vec<&str> = groups
        .albums
        .iter()
        .map(|(album, _)| album.title.as_str())
        .collect();
    assert!(albums.contains(&"Small Hours"));
    assert!(groups.artists.contains(&("Marlowe Kite".to_string(), 1)));
    Ok(())
}

#[test]
fn select_all_and_the_arrows_follow_the_table() -> TestResult {
    let (_folder, mut engine) = library()?;
    engine.execute(Command::SortBy(SortColumn::Title));
    engine.execute(Command::Filter(".mp3".into()));

    engine.execute(Command::MoveSelection(Step::Down));
    assert_eq!(engine.selection().iter().collect::<Vec<_>>(), [3]);

    engine.execute(Command::Filter("a/".into()));
    engine.execute(Command::SelectAll);
    assert_eq!(engine.selection().len(), engine.listed().len());
    Ok(())
}
