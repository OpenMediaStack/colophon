mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use colophon_engine::Engine;
use colophon_engine::tags::read;
use colophon_ui::{AppWindow, ComponentHandle};
use i_slint_backend_testing::{AccessibleRole, ElementHandle};
use slint::LogicalPosition;
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, double_click, find, input, press, shows, type_text, wait_until};

/// The main window in English with `count` copies of "Paper Satellites" by Marlowe Kite, from
/// 2019, the first one selected.
fn window_with(count: usize) -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/v23_full.mp3");
    for number in 1..=count {
        fs::copy(&fixture, folder.path().join(format!("{number}.mp3")))?;
    }
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    let tracks = if count == 1 { "track" } else { "tracks" };
    common::wait_until_shown(&window, &format!("{count} {tracks}"))?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    // Long enough for the next click to start a double click of its own.
    i_slint_backend_testing::mock_elapsed_time(Duration::from_secs(1));
    Ok((window, folder))
}

fn center(element: &ElementHandle) -> LogicalPosition {
    let position = element.absolute_position();
    let size = element.size();
    LogicalPosition::new(
        position.x + size.width / 2.0,
        position.y + size.height / 2.0,
    )
}

/// Double-clicks the first cell of the table that shows `text`.
fn double_click_cell(window: &AppWindow, text: &str) -> TestResult {
    double_click(window, center(&find(window, text)?));
    Ok(())
}

/// The cell being edited, if one is.
fn cell_editor(window: &AppWindow) -> Option<ElementHandle> {
    ElementHandle::find_by_element_type_name(window, "CellEditor")
        .next()?
        .query_descendants()
        .match_accessible_role(AccessibleRole::TextInput)
        .find_first()
}

fn editor_value(window: &AppWindow) -> Result<String, String> {
    Ok(cell_editor(window)
        .ok_or("no cell is being edited")?
        .accessible_value()
        .unwrap_or_default()
        .to_string())
}

#[test]
fn a_double_click_edits_a_cell() -> TestResult {
    let (window, _folder) = window_with(1)?;

    double_click_cell(&window, "Marlowe Kite")?;
    assert_eq!(editor_value(&window)?, "Marlowe Kite");
    type_text(&window, "Cassette Bloom");
    press(&window, &[], Key::Return);

    assert!(cell_editor(&window).is_none());
    assert!(shows(&window, "Cassette Bloom"));
    assert_eq!(window.get_modified_count(), 1);
    assert_eq!(
        input(&window, "Artist")?.accessible_value().as_deref(),
        Some("Cassette Bloom")
    );
    Ok(())
}

#[test]
fn a_double_click_in_a_selection_edits_every_selected_track() -> TestResult {
    let (window, _folder) = window_with(3)?;
    press(&window, &[Key::Control], "a");

    double_click_cell(&window, "Marlowe Kite")?;
    type_text(&window, "Cassette Bloom");
    press(&window, &[], Key::Return);

    assert_eq!(window.get_selected_count(), 3);
    assert_eq!(window.get_modified_count(), 3);
    assert!(!shows(&window, "Marlowe Kite"));
    Ok(())
}

#[test]
fn a_click_in_a_selection_keeps_it_while_a_double_click_may_follow() -> TestResult {
    let (window, _folder) = window_with(3)?;
    press(&window, &[Key::Control], "a");

    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    assert_eq!(window.get_selected_count(), 3);

    i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(600));
    assert_eq!(window.get_selected_count(), 1);
    Ok(())
}

#[test]
fn another_click_cancels_the_pending_shrink() -> TestResult {
    let (window, _folder) = window_with(3)?;
    press(&window, &[Key::Control], "a");

    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    common::click_holding(&window, &[Key::Control], "Marlowe Kite")?;
    i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(600));

    assert_eq!(window.get_selected_count(), 2);
    Ok(())
}

#[test]
fn return_edits_the_title_of_the_selected_track() -> TestResult {
    let (window, _folder) = window_with(1)?;

    press(&window, &[], Key::Return);
    assert_eq!(editor_value(&window)?, "Paper Satellites");
    type_text(&window, "Neon Overpass");
    press(&window, &[], Key::Return);

    assert!(shows(&window, "Neon Overpass"));
    assert!(!shows(&window, "Paper Satellites"));
    Ok(())
}

#[test]
fn escape_puts_the_cell_back() -> TestResult {
    let (window, _folder) = window_with(1)?;

    double_click_cell(&window, "Marlowe Kite")?;
    type_text(&window, "Cassette Bloom");
    press(&window, &[], Key::Escape);

    assert!(cell_editor(&window).is_none());
    assert!(shows(&window, "Marlowe Kite"));
    assert_eq!(window.get_modified_count(), 0);
    assert!(!window.get_can_undo());
    Ok(())
}

#[test]
fn a_year_cell_refuses_letters() -> TestResult {
    let (window, _folder) = window_with(1)?;

    double_click_cell(&window, "2019")?;
    type_text(&window, "20x4");
    press(&window, &[], Key::Return);

    assert_eq!(editor_value(&window)?, "20x4");
    assert_eq!(window.get_modified_count(), 0);
    Ok(())
}

#[test]
fn the_time_cell_is_not_a_tag() -> TestResult {
    let (window, _folder) = window_with(1)?;
    let row = center(&find(&window, "Marlowe Kite")?);
    let time = center(&find(&window, "Time")?);

    double_click(&window, LogicalPosition::new(time.x, row.y));

    assert!(cell_editor(&window).is_none());
    Ok(())
}

#[test]
fn command_s_saves_what_is_typed_in_a_cell() -> TestResult {
    let (window, folder) = window_with(1)?;

    double_click_cell(&window, "Paper Satellites")?;
    type_text(&window, "Neon Overpass");
    press(&window, &[Key::Control], "s");
    wait_until(&window, "the save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })?;

    assert_eq!(
        read(&folder.path().join("1.mp3"))?.tags.title.as_deref(),
        Some("Neon Overpass")
    );
    Ok(())
}

#[test]
fn the_arrow_keys_move_the_selection_again_after_an_edit() -> TestResult {
    let (window, _folder) = window_with(2)?;

    press(&window, &[], Key::Return);
    type_text(&window, "Neon Overpass");
    press(&window, &[], Key::Return);
    press(&window, &[], Key::DownArrow);

    assert_eq!(window.get_focused_row(), 1);
    assert_eq!(window.get_selected_count(), 1);
    Ok(())
}

#[test]
fn clicking_another_track_ends_the_edit() -> TestResult {
    let (window, _folder) = window_with(2)?;

    press(&window, &[], Key::Return);
    type_text(&window, "Neon Overpass");
    find(&window, "Paper Satellites")?.mock_single_click(PointerEventButton::Left);
    i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(200));

    assert!(cell_editor(&window).is_none());
    assert_eq!(window.get_focused_row(), 1);
    assert!(shows(&window, "Neon Overpass"));
    Ok(())
}

#[test]
fn a_moved_column_edits_where_it_shows() -> TestResult {
    let (window, _folder) = window_with(1)?;
    let year = center(&find(&window, "Sort by Year")?);
    let title = find(&window, "Sort by Title")?.absolute_position();
    common::drag(&window, year, LogicalPosition::new(title.x + 4.0, year.y));
    i_slint_backend_testing::mock_elapsed_time(Duration::from_secs(1));

    double_click_cell(&window, "2019")?;

    assert_eq!(editor_value(&window)?, "2019");
    let editor = cell_editor(&window).ok_or("no cell is being edited")?;
    let cell = find(&window, "2019")?;
    assert!((editor.absolute_position().x - cell.absolute_position().x).abs() < 12.0);
    Ok(())
}
