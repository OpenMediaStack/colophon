mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::{Key, PointerEventButton, WindowEvent};
use tempfile::TempDir;

use common::{TestResult, find, shows};

/// The main window, in English at 1440 by 900, whose folder dialog answers `chosen`.
fn open_main_window(chosen: Option<PathBuf>) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = colophon_ui::main_window(Engine::new(), move || chosen.clone())?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    Ok(window)
}

fn folder_with_mp3s(count: usize) -> Result<TempDir, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    for index in 0..count {
        fs::write(folder.path().join(format!("{index:02}.mp3")), b"ID3")?;
    }
    Ok(folder)
}

/// Lets the scan thread work and the window's timers fire, until `label` shows or a few seconds pass.
fn wait_until_shown(window: &AppWindow, label: &str) -> TestResult {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !shows(window, label) {
        if Instant::now() > deadline {
            return Err(format!("{label:?} never showed").into());
        }
        thread::sleep(Duration::from_millis(2));
        i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(60));
    }
    Ok(())
}

#[test]
fn a_fresh_window_invites_to_open_a_folder() -> TestResult {
    let window = open_main_window(None)?;

    assert!(shows(&window, "Open your music folder"));
    assert!(shows(&window, "No folder open"));
    Ok(())
}

#[test]
fn opening_a_folder_reads_its_tracks() -> TestResult {
    let folder = folder_with_mp3s(3)?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;

    find(&window, "Open folder…")?.invoke_accessible_default_action();
    wait_until_shown(&window, "3 tracks")?;

    assert!(!shows(&window, "Open your music folder"));
    assert!(shows(&window, "Tracks"));
    Ok(())
}

#[test]
fn cancelling_the_dialog_changes_nothing() -> TestResult {
    let window = open_main_window(None)?;

    find(&window, "Open folder…")?.invoke_accessible_default_action();

    assert!(shows(&window, "Open your music folder"));
    assert!(shows(&window, "No folder open"));
    Ok(())
}

#[test]
fn the_stop_button_stops_reading() -> TestResult {
    let folder = folder_with_mp3s(3)?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;

    find(&window, "Open folder")?.invoke_accessible_default_action();
    assert!(shows(&window, "Reading… 0 tracks found"));
    find(&window, "Stop")?.invoke_accessible_default_action();

    assert!(shows(&window, "Reading stopped, 0 tracks"));
    assert!(!shows(&window, "Stop"));
    Ok(())
}

#[test]
fn the_file_menu_opens_a_folder() -> TestResult {
    let folder = folder_with_mp3s(1)?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;

    find(&window, "File")?.mock_single_click(PointerEventButton::Left);
    find(&window, "Open Folder…")?.mock_single_click(PointerEventButton::Left);

    wait_until_shown(&window, "1 track")?;
    Ok(())
}

#[test]
fn the_shortcut_opens_a_folder() -> TestResult {
    let folder = folder_with_mp3s(2)?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;

    for event in [
        WindowEvent::KeyPressed {
            text: Key::Control.into(),
        },
        WindowEvent::KeyPressed { text: "o".into() },
        WindowEvent::KeyReleased { text: "o".into() },
        WindowEvent::KeyReleased {
            text: Key::Control.into(),
        },
    ] {
        window.window().dispatch_event(event);
    }

    wait_until_shown(&window, "2 tracks")?;
    Ok(())
}

#[test]
fn an_unreadable_folder_is_reported() -> TestResult {
    let window = open_main_window(Some(PathBuf::from("/this/folder/does/not/exist")))?;

    find(&window, "Open folder")?.invoke_accessible_default_action();

    wait_until_shown(&window, "1 file could not be read")?;
    assert!(shows(&window, "0 tracks"));
    Ok(())
}
