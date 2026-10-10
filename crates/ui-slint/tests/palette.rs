mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle, Theme, WindowCommand};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, press, shows, type_text};

/// The main window in English with three tracks, all selected.
fn window_with_tracks() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in [
        ("v23_full.mp3", "02 Glass Avenue.mp3"),
        ("v24_unicode.mp3", "03 Midnight Lithography.mp3"),
        ("v23_v1_long_title.mp3", "04 Paper Satellites.mp3"),
    ] {
        fs::copy(fixtures.join(fixture), folder.path().join(name))?;
    }
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "3 tracks")?;
    press(&window, &[Key::Control], "a");
    Ok((window, folder))
}

fn open_palette(window: &AppWindow) -> TestResult {
    find(window, "Command palette")?.mock_single_click(PointerEventButton::Left);
    assert!(window.get_palette_open());
    Ok(())
}

#[test]
fn a_command_typed_runs_with_return() -> TestResult {
    let (window, _folder) = window_with_tracks()?;
    open_palette(&window)?;

    type_text(&window, "sidebar");
    assert!(shows(&window, "Hide Sidebar"));
    press(&window, &[], Key::Return);

    assert!(!window.get_palette_open());
    assert!(!window.get_sidebar_visible());
    Ok(())
}

#[test]
fn the_arrow_keys_choose_among_the_commands() -> TestResult {
    let (window, _folder) = window_with_tracks()?;
    open_palette(&window)?;

    type_text(&window, "inspector");
    press(&window, &[], Key::DownArrow);
    press(&window, &[], Key::UpArrow);
    press(&window, &[], Key::Return);

    assert!(!window.get_inspector_visible());
    Ok(())
}

#[test]
fn a_click_runs_a_command() -> TestResult {
    let (window, _folder) = window_with_tracks()?;
    open_palette(&window)?;

    type_text(&window, "tags col");
    find(&window, "Show the Tags column (ID3 versions)")?
        .mock_single_click(PointerEventButton::Left);

    assert!(window.get_columns().tags);
    Ok(())
}

#[test]
fn escape_closes_the_palette_and_runs_nothing() -> TestResult {
    let (window, _folder) = window_with_tracks()?;
    open_palette(&window)?;

    type_text(&window, "sidebar");
    press(&window, &[], Key::Escape);

    assert!(!window.get_palette_open());
    assert!(window.get_sidebar_visible());
    Ok(())
}

#[test]
fn commands_that_cannot_run_are_not_offered() -> TestResult {
    let (window, _folder) = window_with_tracks()?;
    open_palette(&window)?;

    type_text(&window, "id3v2.4");

    assert!(!shows(&window, "Write ID3v2.4 to the selected files"));
    assert!(shows(&window, "No command holds “id3v2.4”"));
    Ok(())
}

#[test]
fn the_palette_matches_its_references() -> TestResult {
    for (dark, theme) in [(true, "dark"), (false, "light")] {
        let (window, _folder) = window_with_tracks()?;
        window.invoke_run(WindowCommand::ToggleDeveloperMode);
        window.global::<Theme>().set_dark(dark);
        open_palette(&window)?;
        type_text(&window, "id3");
        assert_matches_reference(&window, &format!("palette-{theme}.png"))?;
    }
    Ok(())
}
