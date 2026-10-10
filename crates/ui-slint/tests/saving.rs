mod common;

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};

use colophon_engine::Engine;
use colophon_engine::tags::read;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::Key;
use tempfile::TempDir;

use common::{TestResult, find, press, retype, shows, wait_until};

/// The main window in English with one copy of a fixture, its only track selected.
fn window_with_a_selected(fixture: &str) -> Result<(AppWindow, TempDir, PathBuf), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let path = folder.path().join("1.mp3");
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata")
            .join(fixture),
        &path,
    )?;
    let opened = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(opened.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    press(&window, &[Key::Control], "a");
    Ok((window, folder, path))
}

fn title_on_disk(path: &Path) -> Result<Option<String>, Box<dyn Error>> {
    Ok(read(path)?.tags.title)
}

fn saved(window: &AppWindow) -> TestResult {
    wait_until(window, "the save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })
}

#[test]
fn command_s_saves_what_was_typed_even_without_enter() -> TestResult {
    let (window, _folder, path) = window_with_a_selected("v23_full.mp3")?;

    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[Key::Control], "s");
    saved(&window)?;

    assert_eq!(title_on_disk(&path)?.as_deref(), Some("Neon Overpass"));
    assert!(!shows(&window, "1 file with unsaved changes"));
    Ok(())
}

#[test]
fn the_save_button_saves() -> TestResult {
    let (window, _folder, path) = window_with_a_selected("v23_full.mp3")?;
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    find(&window, "Save 1 file")?.invoke_accessible_default_action();
    saved(&window)?;

    assert_eq!(title_on_disk(&path)?.as_deref(), Some("Neon Overpass"));
    Ok(())
}

#[test]
fn undo_and_redo_take_back_a_whole_word() -> TestResult {
    let (window, _folder, _path) = window_with_a_selected("v23_full.mp3")?;
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    press(&window, &[Key::Control], "z");
    assert!(shows(&window, "Paper Satellites"));
    assert!(!window.get_can_undo());

    press(&window, &[Key::Control, Key::Shift], "z");
    assert!(shows(&window, "Neon Overpass"));
    Ok(())
}

#[test]
fn escape_leaves_nothing_to_undo() -> TestResult {
    let (window, _folder, _path) = window_with_a_selected("v23_full.mp3")?;

    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Escape);

    assert!(shows(&window, "Paper Satellites"));
    assert_eq!(window.get_modified_count(), 0);
    assert!(!window.get_can_undo());
    Ok(())
}

#[test]
fn revert_drops_the_changes_of_the_selection() -> TestResult {
    let (window, _folder, _path) = window_with_a_selected("v23_full.mp3")?;
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    find(&window, "Revert")?.invoke_accessible_default_action();

    assert!(shows(&window, "Paper Satellites"));
    assert_eq!(window.get_modified_count(), 0);
    Ok(())
}

#[test]
fn the_inspector_says_how_the_file_will_be_saved() -> TestResult {
    let (window, _folder, _path) = window_with_a_selected("v23_v1_long_title.mp3")?;

    retype(
        &window,
        "Title",
        "A brand new title, well over thirty characters",
    )?;
    press(&window, &[], Key::Return);

    assert!(shows(&window, "ID3v2.4, ID3v1.1"));
    assert!(shows(&window, "ID3v1 will keep only part of: Title"));
    Ok(())
}

#[test]
fn a_file_that_cannot_be_saved_is_reported() -> TestResult {
    let (window, _folder, path) = window_with_a_selected("v23_full.mp3")?;
    let mut permissions = fs::metadata(&path)?.permissions();
    permissions.set_readonly(true);
    fs::set_permissions(&path, permissions)?;
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    press(&window, &[Key::Control], "s");
    wait_until(&window, "the save", |window| !window.get_saving())?;

    assert!(shows(&window, "1 file could not be saved"));
    assert!(shows(&window, "1 file with unsaved changes"));
    Ok(())
}
