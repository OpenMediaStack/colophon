mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use i_slint_backend_testing::{AccessibleRole, ElementHandle};
use slint::LogicalPosition;
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, double_click, find, input, press, retype, shows};

/// The main window in English with "Paper Satellites", of the Folk genre, selected.
fn window_with_a_folk_track() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/v23_full.mp3"),
        folder.path().join("1.mp3"),
    )?;
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    // Long enough for the next click to start a double click of its own.
    i_slint_backend_testing::mock_elapsed_time(Duration::from_secs(1));
    Ok((window, folder))
}

/// The genres the open list suggests, in its order.
fn suggestions(window: &AppWindow) -> Vec<String> {
    let Some(list) = ElementHandle::find_by_accessible_label(window, "Suggestions").next() else {
        return Vec::new();
    };
    list.query_descendants()
        .match_accessible_role(AccessibleRole::ListItem)
        .find_all()
        .iter()
        .filter_map(|item| item.accessible_label().map(|label| label.to_string()))
        .collect()
}

fn genre(window: &AppWindow) -> Result<String, String> {
    Ok(input(window, "Genre")?
        .accessible_value()
        .unwrap_or_default()
        .to_string())
}

#[test]
fn typing_a_genre_suggests_those_that_start_with_it_first() -> TestResult {
    let (window, _folder) = window_with_a_folk_track()?;

    retype(&window, "Genre", "rock")?;

    let suggested = suggestions(&window);
    assert_eq!(suggested.first().map(String::as_str), Some("Rock"));
    assert!(suggested.contains(&"Classic rock".to_string()));
    Ok(())
}

#[test]
fn the_arrow_keys_and_return_pick_a_genre() -> TestResult {
    let (window, _folder) = window_with_a_folk_track()?;

    retype(&window, "Genre", "folk-r")?;
    press(&window, &[], Key::DownArrow);
    press(&window, &[], Key::Return);

    assert!(suggestions(&window).is_empty());
    assert_eq!(genre(&window)?, "Folk-Rock");
    assert_eq!(window.get_modified_count(), 1);
    Ok(())
}

#[test]
fn a_click_picks_a_genre() -> TestResult {
    let (window, _folder) = window_with_a_folk_track()?;

    retype(&window, "Genre", "folk")?;
    find(&window, "Folklore")?.mock_single_click(PointerEventButton::Left);

    assert!(suggestions(&window).is_empty());
    assert_eq!(genre(&window)?, "Folklore");
    Ok(())
}

#[test]
fn escape_closes_the_list_then_puts_the_genre_back() -> TestResult {
    let (window, _folder) = window_with_a_folk_track()?;

    retype(&window, "Genre", "rock")?;
    press(&window, &[], Key::Escape);
    assert!(suggestions(&window).is_empty());
    assert_eq!(genre(&window)?, "rock");

    press(&window, &[], Key::Escape);
    assert_eq!(genre(&window)?, "Folk");
    assert_eq!(window.get_modified_count(), 0);
    Ok(())
}

#[test]
fn the_button_shows_every_genre() -> TestResult {
    let (window, _folder) = window_with_a_folk_track()?;

    find(&window, "Show suggestions")?.invoke_accessible_default_action();

    assert_eq!(
        suggestions(&window).first().map(String::as_str),
        Some("A cappella")
    );
    Ok(())
}

#[test]
fn the_genre_cell_of_the_table_suggests_genres_too() -> TestResult {
    let (window, _folder) = window_with_a_folk_track()?;
    let cell = find(&window, "Folk")?;
    let position = cell.absolute_position();
    let size = cell.size();

    double_click(
        &window,
        LogicalPosition::new(
            position.x + size.width / 2.0,
            position.y + size.height / 2.0,
        ),
    );
    common::type_text(&window, "folk-r");
    assert_eq!(suggestions(&window), ["Folk-Rock"]);
    press(&window, &[], Key::DownArrow);
    press(&window, &[], Key::Return);

    assert!(suggestions(&window).is_empty());
    assert!(shows(&window, "Folk-Rock"));
    assert_eq!(genre(&window)?, "Folk-Rock");
    Ok(())
}
