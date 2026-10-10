mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, find, shows};

/// The main window in English, showing three fixtures in this order: "Paper Satellites",
/// "Track seven", "Café". The folder lives as long as the window.
fn window_with_three_tracks() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in [
        ("v23_full.mp3", "1.mp3"),
        ("v1_1_ascii.mp3", "2.mp3"),
        ("v24_unicode.mp3", "3.mp3"),
    ] {
        fs::copy(fixtures.join(fixture), folder.path().join(name))?;
    }
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "3 tracks")?;
    Ok((window, folder))
}

#[test]
fn clicks_select_tracks() -> TestResult {
    let (window, _folder) = window_with_three_tracks()?;

    find(&window, "Track seven")?.mock_single_click(PointerEventButton::Left);
    assert!(shows(&window, "3 tracks · 1 selected"));

    common::click_holding(&window, &[Key::Control], "Café")?;
    assert!(shows(&window, "3 tracks · 2 selected"));

    common::click_holding(&window, &[Key::Shift], "Paper Satellites")?;
    assert!(shows(&window, "3 tracks · 3 selected"));
    Ok(())
}

#[test]
fn the_keyboard_selects_tracks() -> TestResult {
    let (window, _folder) = window_with_three_tracks()?;
    find(&window, "Paper Satellites")?.mock_single_click(PointerEventButton::Left);

    common::press(&window, &[Key::Shift], Key::DownArrow);
    assert!(shows(&window, "3 tracks · 2 selected"));

    common::press(&window, &[], Key::DownArrow);
    assert!(shows(&window, "3 tracks · 1 selected"));

    common::press(&window, &[Key::Control], "a");
    assert!(shows(&window, "3 tracks · 3 selected"));
    Ok(())
}

#[test]
fn the_selection_is_counted_in_french() -> TestResult {
    let (window, _folder) = window_with_three_tracks()?;
    common::select_language("fr")?;

    common::press(&window, &[Key::Control], "a");

    assert!(shows(&window, "3 morceaux · 3 sélectionnés"));
    Ok(())
}
