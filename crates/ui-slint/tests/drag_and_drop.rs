mod common;

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle, DropTarget, Theme};
use slint::platform::PointerEventButton;
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, shows};

/// A folder with two albums of one track each, and a cover image beside them.
fn folders() -> Result<TempDir, Box<dyn Error>> {
    let root = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for album in ["Small Hours", "Analog Hearts"] {
        fs::create_dir(root.path().join(album))?;
    }
    fs::copy(
        fixtures.join("v23_full.mp3"),
        root.path().join("Small Hours/1.mp3"),
    )?;
    fs::copy(
        fixtures.join("v24_full.mp3"),
        root.path().join("Analog Hearts/1.mp3"),
    )?;
    image::RgbaImage::new(2, 2).save(root.path().join("cover.png"))?;
    fs::write(root.path().join("notes.txt"), "not music")?;
    Ok(root)
}

/// A window in English with nothing open.
fn empty_window() -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = colophon_ui::main_window(Engine::new(), || None)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    Ok(window)
}

fn hover(window: &AppWindow, path: &Path) {
    window.invoke_file_hovered(path.to_string_lossy().as_ref().into());
}

fn drop(window: &AppWindow, path: &Path) {
    window.invoke_file_dropped(path.to_string_lossy().as_ref().into());
}

/// Lets the drop timer take in what was dropped.
fn settle() {
    i_slint_backend_testing::mock_elapsed_time(std::time::Duration::from_millis(16));
}

#[test]
fn folders_and_files_dropped_together_open_together() -> TestResult {
    let root = folders()?;
    let window = empty_window()?;

    hover(&window, &root.path().join("Small Hours"));
    hover(&window, &root.path().join("Analog Hearts/1.mp3"));
    assert_eq!(window.get_drop_target(), DropTarget::Library);
    assert!(shows(&window, "Drop to open these folders and files"));
    drop(&window, &root.path().join("Small Hours"));
    drop(&window, &root.path().join("Analog Hearts/1.mp3"));
    settle();

    assert_eq!(window.get_drop_target(), DropTarget::None);
    common::wait_until_shown(&window, "2 tracks")?;
    Ok(())
}

#[test]
fn an_image_dropped_becomes_the_cover_of_the_selection() -> TestResult {
    let root = folders()?;
    let window = empty_window()?;
    drop(&window, &root.path().join("Small Hours"));
    settle();
    common::wait_until_shown(&window, "1 track")?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);

    hover(&window, &root.path().join("cover.png"));
    assert_eq!(window.get_drop_target(), DropTarget::Cover);
    drop(&window, &root.path().join("cover.png"));
    settle();

    assert_eq!(window.get_modified_count(), 1);
    assert!(window.get_inspected_tracks().cover_modified);
    Ok(())
}

#[test]
fn an_image_without_a_selection_does_nothing() -> TestResult {
    let root = folders()?;
    let window = empty_window()?;

    hover(&window, &root.path().join("cover.png"));
    assert_eq!(window.get_drop_target(), DropTarget::None);
    drop(&window, &root.path().join("cover.png"));
    settle();

    assert!(shows(&window, "Open your music folder"));
    Ok(())
}

#[test]
fn a_drag_that_leaves_the_window_shows_nothing() -> TestResult {
    let root = folders()?;
    let window = empty_window()?;

    hover(&window, &root.path().join("Small Hours"));
    window.invoke_file_hover_ended();

    assert_eq!(window.get_drop_target(), DropTarget::None);
    hover(&window, &root.path().join("notes.txt"));
    assert_eq!(window.get_drop_target(), DropTarget::None);
    Ok(())
}

#[test]
fn the_drop_overlay_matches_its_references() -> TestResult {
    let root = folders()?;
    for (dark, theme) in [(true, "dark"), (false, "light")] {
        let window = empty_window()?;
        window.global::<Theme>().set_dark(dark);
        hover(&window, &root.path().join("Small Hours"));
        assert_matches_reference(&window, &format!("drop-{theme}.png"))?;
    }
    Ok(())
}
