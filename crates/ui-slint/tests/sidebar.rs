mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::Model;
use tempfile::TempDir;

use common::{TestResult, find, shows};

/// The main window in English over a library of three tracks, two of Small Hours by Marlowe
/// Kite and one by 坂本龍一, and a damaged file.
fn window_with_a_library() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in [
        ("v23_full.mp3", "1.mp3"),
        ("v23_full.mp3", "2.mp3"),
        ("v23_unicode.mp3", "3.mp3"),
        ("tiny_tag.mp3", "4.mp3"),
    ] {
        fs::copy(fixtures.join(fixture), folder.path().join(name))?;
    }
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "4 tracks")?;
    Ok((window, folder))
}

fn listed(window: &AppWindow) -> usize {
    slint::Model::row_count(&window.get_tracks())
}

#[test]
fn the_sidebar_lists_the_library_its_folder_and_albums() -> TestResult {
    let (window, _folder) = window_with_a_library()?;

    assert!(shows(&window, "All tracks"));
    assert!(shows(&window, "Unreadable files"));
    assert!(shows(&window, "Small Hours"));
    assert!(shows(&window, "Ελληνικά"));
    assert_eq!(window.get_folder_sources().row_count(), 1);
    Ok(())
}

#[test]
fn an_album_lists_its_tracks_alone_and_titles_the_window() -> TestResult {
    let (window, _folder) = window_with_a_library()?;

    find(&window, "Small Hours")?.invoke_accessible_default_action();

    assert_eq!(listed(&window), 2);
    assert_eq!(window.get_window_title(), "Colophon · Small Hours");

    find(&window, "All tracks")?.invoke_accessible_default_action();
    assert_eq!(listed(&window), 4);
    assert_eq!(window.get_window_title(), "Colophon · All tracks");
    Ok(())
}

#[test]
fn the_unreadable_files_are_one_click_away() -> TestResult {
    let (window, _folder) = window_with_a_library()?;

    find(&window, "Unreadable files")?.invoke_accessible_default_action();

    assert_eq!(listed(&window), 1);
    Ok(())
}

#[test]
fn the_artists_show_once_unfolded() -> TestResult {
    let (window, _folder) = window_with_a_library()?;

    find(&window, "Artists")?.invoke_accessible_default_action();
    find(&window, "坂本龍一")?.invoke_accessible_default_action();

    assert_eq!(listed(&window), 1);
    Ok(())
}
