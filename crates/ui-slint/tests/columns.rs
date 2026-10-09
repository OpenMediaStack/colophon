mod common;

use std::error::Error;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::PointerEventButton;
use tempfile::TempDir;

use common::{TestResult, find, menu_item, shows};

/// The main window in English, showing the tags of one fixture. The folder lives as long as the window.
fn window_with_a_track() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = common::folder_with_fixture("v23_full.mp3", "Small Hours/07.mp3")?;
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    Ok((window, folder))
}

/// Opens the column chooser with its button and picks `item`.
fn choose(window: &AppWindow, item: &str) -> TestResult {
    find(window, "Choose columns")?.invoke_accessible_default_action();
    menu_item(window, item)?.mock_single_click(PointerEventButton::Left);
    Ok(())
}

#[test]
fn the_chooser_shows_a_hidden_column() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    assert!(!shows(&window, "ID3v2.3"));

    choose(&window, "Tags")?;

    assert!(shows(&window, "ID3v2.3"));
    Ok(())
}

#[test]
fn the_chooser_hides_a_shown_column() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    assert!(shows(&window, "Folk"));

    choose(&window, "Genre")?;

    assert!(!shows(&window, "Folk"));
    assert!(!shows(&window, "Genre"));
    Ok(())
}

#[test]
fn the_title_cannot_be_hidden() -> TestResult {
    let (window, _folder) = window_with_a_track()?;

    choose(&window, "Title")?;

    assert!(shows(&window, "Paper Satellites"));
    Ok(())
}

#[test]
fn resetting_brings_back_the_default_columns() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    choose(&window, "Tags")?;
    choose(&window, "Genre")?;

    choose(&window, "Reset to default columns")?;

    assert!(shows(&window, "Folk"));
    assert!(!shows(&window, "ID3v2.3"));
    Ok(())
}

#[test]
fn a_right_click_on_the_header_opens_the_chooser() -> TestResult {
    let (window, _folder) = window_with_a_track()?;

    find(&window, "Album")?.mock_single_click(PointerEventButton::Right);

    assert!(menu_item(&window, "Reset to default columns").is_ok());
    Ok(())
}

#[test]
fn the_chooser_speaks_french_when_selected() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    common::select_language("fr")?;

    find(&window, "Choisir les colonnes")?.invoke_accessible_default_action();

    assert!(menu_item(&window, "Rétablir les colonnes par défaut").is_ok());
    Ok(())
}
