mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_engine::tags::read;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::Model;
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, find, input, press, retype, type_text, wait_until};

/// The main window in English over "Paper Satellites" by Marlowe Kite and "Café" by 坂本龍一.
fn window_with_two_tracks() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    fs::copy(fixtures.join("v23_full.mp3"), folder.path().join("1.mp3"))?;
    fs::copy(
        fixtures.join("v23_unicode.mp3"),
        folder.path().join("2.mp3"),
    )?;
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "2 tracks")?;
    Ok((window, folder))
}

fn listed(window: &AppWindow) -> usize {
    window.get_tracks().row_count()
}

#[test]
fn the_filter_narrows_the_table_and_escape_empties_it() -> TestResult {
    let (window, _folder) = window_with_two_tracks()?;

    input(&window, "Filter")?.mock_single_click(PointerEventButton::Left);
    type_text(&window, "marlowe");
    assert_eq!(listed(&window), 1);

    press(&window, &[], Key::Escape);
    assert_eq!(listed(&window), 2);
    Ok(())
}

#[test]
fn command_f_reaches_the_filter() -> TestResult {
    let (window, _folder) = window_with_two_tracks()?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);

    press(&window, &[Key::Control], "f");
    type_text(&window, "café");

    assert_eq!(listed(&window), 1);
    Ok(())
}

#[test]
fn the_save_button_saves_and_undo_takes_back() -> TestResult {
    let (window, folder) = window_with_two_tracks()?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);
    assert_eq!(find(&window, "Undo")?.accessible_enabled(), Some(true));

    find(&window, "Undo")?.invoke_accessible_default_action();
    assert_eq!(window.get_modified_count(), 0);
    find(&window, "Redo")?.invoke_accessible_default_action();
    find(&window, "Save 1 file")?.invoke_accessible_default_action();
    wait_until(&window, "the save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })?;

    assert_eq!(
        read(&folder.path().join("1.mp3"))?.tags.title.as_deref(),
        Some("Neon Overpass")
    );
    assert_eq!(find(&window, "Save")?.accessible_enabled(), Some(false));
    Ok(())
}
