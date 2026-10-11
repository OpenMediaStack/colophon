mod common;

use std::error::Error;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle, TrackColumn};
use slint::platform::PointerEventButton;
use slint::{LogicalPosition, Model};
use tempfile::TempDir;

use common::{TestResult, find, menu_item, resize_handle, shows};

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

fn header_x(window: &AppWindow, name: &str) -> Result<f32, String> {
    Ok(find(window, name)?.absolute_position().x)
}

#[test]
fn resizing_a_column_widens_the_table_rather_than_squeezing_the_others() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    let album = header_x(&window, "Album")?;
    let year = header_x(&window, "Year")?;
    let handle = resize_handle(&window, "Artist")?;

    common::drag(
        &window,
        handle,
        slint::LogicalPosition::new(handle.x + 200.0, handle.y),
    );

    assert!((header_x(&window, "Album")? - (album + 200.0)).abs() < 1.0);
    assert!((header_x(&window, "Year")? - (year + 200.0)).abs() < 1.0);
    assert!(shows(&window, "Horizontal scroll bar"));
    Ok(())
}

#[test]
fn a_double_click_on_a_separator_fits_the_column_to_its_content() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    let album = header_x(&window, "Album")?;

    common::double_click(&window, resize_handle(&window, "Artist")?);

    // "Marlowe Kite" needs much less room than the share the artist had.
    assert!(header_x(&window, "Album")? < album - 20.0);
    Ok(())
}

#[test]
fn resetting_the_columns_brings_back_the_shared_widths() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    let album = header_x(&window, "Album")?;
    let handle = resize_handle(&window, "Artist")?;
    common::drag(
        &window,
        handle,
        slint::LogicalPosition::new(handle.x + 200.0, handle.y),
    );

    choose(&window, "Reset to default columns")?;

    assert_eq!(header_x(&window, "Album")?, album);
    assert!(!shows(&window, "Horizontal scroll bar"));
    Ok(())
}

/// Where a column's name sits, by the left edge and the middle of its header cell.
fn header(window: &AppWindow, name: &str) -> Result<(f32, f32, f32), String> {
    let cell = find(window, &format!("Sort by {name}"))?;
    let (position, size) = (cell.absolute_position(), cell.size());
    Ok((
        position.x,
        position.x + size.width / 2.0,
        position.y + size.height / 2.0,
    ))
}

#[test]
fn dragging_a_column_by_its_name_moves_it() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    let (_, year, y) = header(&window, "Year")?;
    let (title_left, _, _) = header(&window, "Title")?;

    common::drag(
        &window,
        LogicalPosition::new(year, y),
        LogicalPosition::new(title_left + 4.0, y),
    );

    assert_eq!(
        window.get_column_order().row_data(0),
        Some(TrackColumn::Year)
    );
    assert!(!window.get_sorted());
    let (year_left, _, _) = header(&window, "Year")?;
    let (title_left, _, _) = header(&window, "Title")?;
    assert!(year_left < title_left);
    Ok(())
}

#[test]
fn reset_puts_the_columns_back_in_order() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    let (_, year, y) = header(&window, "Year")?;
    let (title_left, _, _) = header(&window, "Title")?;
    common::drag(
        &window,
        LogicalPosition::new(year, y),
        LogicalPosition::new(title_left + 4.0, y),
    );

    choose(&window, "Reset to default columns")?;

    assert_eq!(
        window.get_column_order().row_data(0),
        Some(TrackColumn::Title)
    );
    Ok(())
}

#[test]
fn a_column_dropped_where_it_was_neither_moves_nor_sorts() -> TestResult {
    let (window, _folder) = window_with_a_track()?;
    let (_, year, y) = header(&window, "Year")?;

    common::drag(
        &window,
        LogicalPosition::new(year, y),
        LogicalPosition::new(year + 8.0, y),
    );

    assert_eq!(
        window.get_column_order().row_data(3),
        Some(TrackColumn::Year)
    );
    assert!(!window.get_sorted());
    Ok(())
}
