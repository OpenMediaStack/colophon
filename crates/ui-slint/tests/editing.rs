mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, find, input, press, retype, shows};

/// The main window in English, showing these fixtures under these names, in this order.
fn window_with(copies: &[(&str, &str)]) -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in copies {
        fs::copy(fixtures.join(fixture), folder.path().join(name))?;
    }
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    let tracks = match copies.len() {
        1 => "1 track".to_string(),
        count => format!("{count} tracks"),
    };
    common::wait_until_shown(&window, &tracks)?;
    Ok((window, folder))
}

/// The main window with one track, "Paper Satellites" by Marlowe Kite, selected.
fn window_with_a_selected_track() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    let (window, folder) = window_with(&[("v23_full.mp3", "1.mp3")])?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    Ok((window, folder))
}

fn value(window: &AppWindow, label: &str) -> Result<String, String> {
    Ok(input(window, label)?
        .accessible_value()
        .unwrap_or_default()
        .to_string())
}

#[test]
fn enter_keeps_a_new_title() -> TestResult {
    let (window, _folder) = window_with_a_selected_track()?;

    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    assert!(shows(&window, "Neon Overpass"));
    assert!(shows(&window, "Unsaved changes"));
    assert!(shows(&window, "1 file with unsaved changes"));
    Ok(())
}

#[test]
fn escape_puts_the_value_back() -> TestResult {
    let (window, _folder) = window_with_a_selected_track()?;

    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Escape);

    assert_eq!(value(&window, "Title")?, "Paper Satellites");
    assert!(!shows(&window, "1 file with unsaved changes"));
    Ok(())
}

#[test]
fn leaving_a_field_keeps_what_was_typed() -> TestResult {
    let (window, _folder) = window_with_a_selected_track()?;

    retype(&window, "Genre", "Synthwave")?;
    input(&window, "Album")?.mock_single_click(PointerEventButton::Left);

    assert!(shows(&window, "Synthwave"));
    assert!(shows(&window, "1 file with unsaved changes"));
    Ok(())
}

#[test]
fn a_year_that_is_not_one_is_refused_and_put_back() -> TestResult {
    let (window, _folder) = window_with_a_selected_track()?;

    retype(&window, "Year", "20x4")?;
    press(&window, &[], Key::Return);
    assert_eq!(value(&window, "Year")?, "20x4");
    assert!(!shows(&window, "1 file with unsaved changes"));

    input(&window, "Album")?.mock_single_click(PointerEventButton::Left);
    assert_eq!(value(&window, "Year")?, "2019");
    Ok(())
}

#[test]
fn several_tracks_take_the_same_value() -> TestResult {
    let (window, _folder) =
        window_with(&[("v23_full.mp3", "1.mp3"), ("v24_unicode.mp3", "2.mp3")])?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    press(&window, &[Key::Control], "a");
    assert!(shows(&window, "Multiple values"));

    retype(&window, "Title", "Same title")?;
    press(&window, &[], Key::Return);

    assert!(shows(&window, "2 files with unsaved changes"));
    assert!(!shows(&window, "Café"));
    assert!(!shows(&window, "Paper Satellites"));
    Ok(())
}

#[test]
fn unsaved_changes_are_counted_in_french() -> TestResult {
    let (window, _folder) = window_with_a_selected_track()?;
    common::select_language("fr")?;

    retype(&window, "Titre", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    assert!(shows(
        &window,
        "1 fichier avec des modifications non enregistrées"
    ));
    Ok(())
}
