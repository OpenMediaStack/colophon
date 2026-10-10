mod common;

use std::cell::RefCell;
use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::{Key, PointerEventButton, WindowEvent};
use tempfile::TempDir;

use common::{TestResult, find, folder_with_fixture, shows, wait_until_shown};

/// The main window, in English at 1440 by 900, whose folder dialog answers `chosen`.
fn open_main_window(chosen: Option<PathBuf>) -> Result<AppWindow, Box<dyn Error>> {
    open_main_window_choosing(chosen.into_iter().collect())
}

/// The main window, whose folder dialog answers each folder of `chosen` in turn, then nothing.
fn open_main_window_choosing(chosen: Vec<PathBuf>) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let chosen = RefCell::new(chosen.into_iter());
    let window = colophon_ui::main_window(Engine::new(), move || chosen.borrow_mut().next())?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    Ok(window)
}

fn folder_with_mp3s(count: usize) -> Result<TempDir, Box<dyn Error>> {
    folder_with_files(
        &(0..count)
            .map(|index| format!("{index:02}.mp3"))
            .collect::<Vec<_>>(),
    )
}

/// A folder of files that only start like an MP3, whose tags cannot be read.
fn folder_with_files(names: &[impl AsRef<str>]) -> Result<TempDir, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    for name in names {
        let path = folder.path().join(name.as_ref());
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, b"ID3")?;
    }
    Ok(folder)
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
    for title in ["00", "01", "02"] {
        assert!(shows(&window, title), "{title} is missing");
    }
    Ok(())
}

#[test]
fn a_track_shows_its_tags() -> TestResult {
    let folder = folder_with_fixture("v23_full.mp3", "Small Hours/07.mp3")?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;

    find(&window, "Open folder")?.invoke_accessible_default_action();
    wait_until_shown(&window, "1 track")?;

    for value in [
        "03",
        "Paper Satellites",
        "Marlowe Kite",
        "Small Hours",
        "2019",
        "Folk",
    ] {
        assert!(shows(&window, value), "{value} is missing");
    }
    assert!(!shows(&window, "Unreadable"));
    Ok(())
}

#[test]
fn a_file_whose_tags_cannot_be_read_is_marked() -> TestResult {
    let folder = folder_with_files(&["broken.mp3"])?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;

    find(&window, "Open folder")?.invoke_accessible_default_action();
    wait_until_shown(&window, "1 track")?;

    assert!(shows(&window, "broken"));
    assert!(shows(&window, "Unreadable"));
    Ok(())
}

#[test]
fn opening_another_folder_adds_its_tracks() -> TestResult {
    let first = folder_with_files(&["first.mp3"])?;
    let second = folder_with_files(&["second.mp3"])?;
    let window = open_main_window_choosing(vec![
        first.path().to_path_buf(),
        second.path().to_path_buf(),
    ])?;

    find(&window, "Open folder")?.invoke_accessible_default_action();
    wait_until_shown(&window, "first")?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    wait_until_shown(&window, "second")?;

    assert!(shows(&window, "first"));
    assert!(shows(&window, "2 tracks"));
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

/// Dialogs that pick these files, and no folder.
struct PickFiles(Vec<PathBuf>);

impl colophon_ui::Dialogs for PickFiles {
    fn pick_folder(&self) -> Option<PathBuf> {
        None
    }

    fn pick_files(&self) -> Vec<PathBuf> {
        self.0.clone()
    }
}

#[test]
fn files_open_without_their_folder() -> TestResult {
    let folder = folder_with_mp3s(3)?;
    common::use_testing_backend()?;
    let files = vec![folder.path().join("00.mp3"), folder.path().join("02.mp3")];
    let window = colophon_ui::main_window(Engine::new(), PickFiles(files))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;

    window.invoke_run(colophon_ui::WindowCommand::OpenFiles);
    wait_until_shown(&window, "2 tracks")?;

    assert!(shows(&window, "00"));
    assert!(!shows(&window, "01"));
    Ok(())
}

#[test]
fn a_click_on_a_column_name_sorts_by_it() -> TestResult {
    let folder = folder_with_files(&["b.mp3", "c.mp3", "a.mp3"])?;
    let window = open_main_window(Some(folder.path().to_path_buf()))?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    wait_until_shown(&window, "3 tracks")?;
    let first = |window: &AppWindow| {
        slint::Model::row_data(&window.get_tracks(), 0)
            .map(|row| row.title.to_string())
            .unwrap_or_default()
    };

    find(&window, "Sort by Title")?.invoke_accessible_default_action();
    assert_eq!(first(&window), "a");

    find(&window, "Sort by Title")?.invoke_accessible_default_action();
    assert_eq!(first(&window), "c");
    Ok(())
}

#[test]
fn a_long_folder_path_keeps_the_inspector_in_the_window() -> TestResult {
    let folder = tempfile::tempdir()?;
    let deep = folder
        .path()
        .join("A folder with a long name to widen the table")
        .join("Another folder with a long name to widen it more")
        .join("And a third one, so that the path is long enough");
    fs::create_dir_all(&deep)?;
    fs::write(deep.join("01.mp3"), b"ID3")?;
    let window = open_main_window(Some(deep))?;

    find(&window, "Open folder")?.invoke_accessible_default_action();
    wait_until_shown(&window, "1 track")?;

    let inspector = find(&window, "Inspector")?;
    assert!(inspector.absolute_position().x + inspector.size().width <= 1440.0);
    Ok(())
}
