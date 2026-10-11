mod common;

use std::error::Error;

use colophon_ui::{AppWindow, ComponentHandle, Theme};
use slint::LogicalSize;

use common::{TestResult, assert_matches_reference, select_language, shows};

/// What a fresh window shows: the first launch screen and the inspector, without the sidebar
/// until something is open, nor the player until a track plays.
const REGIONS: [&str; 4] = [
    "Filter",
    "Open your music folder",
    "Inspector",
    "No folder open",
];

/// A window of the given size, in English, not shown yet so that a test can set it up first.
fn new_window(width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = AppWindow::new()?;
    common::prepare(&window, width, height)?;
    Ok(window)
}

#[test]
fn a_large_window_shows_every_region() -> TestResult {
    let window = new_window(1440.0, 900.0)?;
    window.show()?;

    for region in REGIONS {
        assert!(shows(&window, region), "{region} is missing");
    }
    Ok(())
}

/// A window of the given size with a folder open, so that the sidebar has something to show.
fn window_with_a_folder(width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
    let window = new_window(width, height)?;
    window.set_folder_open(true);
    Ok(window)
}

#[test]
fn the_sidebar_waits_for_something_open() -> TestResult {
    let window = new_window(1440.0, 900.0)?;
    window.show()?;
    assert!(!shows(&window, "Sidebar"));

    window.set_folder_open(true);

    assert!(shows(&window, "Sidebar"));
    Ok(())
}

#[test]
fn the_sidebar_gives_way_in_a_small_window() -> TestResult {
    let window = window_with_a_folder(960.0, 600.0)?;
    window.show()?;

    assert!(!shows(&window, "Sidebar"));
    assert!(shows(&window, "Inspector"));
    Ok(())
}

#[test]
fn the_sidebar_comes_back_when_the_window_grows() -> TestResult {
    let window = window_with_a_folder(960.0, 600.0)?;
    window.show()?;
    assert!(!shows(&window, "Sidebar"));

    window.window().set_size(LogicalSize::new(1440.0, 900.0));
    i_slint_backend_testing::mock_elapsed_time(std::time::Duration::from_millis(16));

    assert!(shows(&window, "Sidebar"));
    Ok(())
}

#[test]
fn hiding_the_inspector_makes_room_for_the_sidebar() -> TestResult {
    let window = window_with_a_folder(960.0, 600.0)?;
    window.set_inspector_visible(false);
    window.show()?;

    assert!(shows(&window, "Sidebar"));
    assert!(!shows(&window, "Inspector"));
    Ok(())
}

#[test]
fn hidden_panels_are_not_shown() -> TestResult {
    let window = window_with_a_folder(1440.0, 900.0)?;
    window.set_sidebar_visible(false);
    window.set_inspector_visible(false);
    window.show()?;

    assert!(!shows(&window, "Sidebar"));
    assert!(!shows(&window, "Inspector"));
    Ok(())
}

#[test]
fn the_regions_are_named_in_french_when_selected() -> TestResult {
    let window = new_window(1440.0, 900.0)?;
    select_language("fr")?;
    window.show()?;

    assert!(shows(&window, "Ouvrez votre dossier de musique"));
    assert!(shows(&window, "Inspecteur"));
    Ok(())
}

#[test]
fn the_layout_matches_its_references() -> TestResult {
    for (width, height) in [(1440, 900), (1280, 720), (960, 600)] {
        for (dark, theme) in [(true, "dark"), (false, "light")] {
            let window = new_window(width as f32, height as f32)?;
            window.global::<Theme>().set_dark(dark);
            window.show()?;
            assert_matches_reference(&window, &format!("layout-{theme}-{width}x{height}.png"))?;
        }
    }
    Ok(())
}
