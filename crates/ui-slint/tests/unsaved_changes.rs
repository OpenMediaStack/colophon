mod common;

use std::cell::RefCell;
use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};

use colophon_engine::Engine;
use colophon_engine::tags::read;
use colophon_ui::{AppWindow, ComponentHandle, Leaving, ScanState, Theme};
use i_slint_backend_testing::{AccessibleRole, ElementHandle};
use slint::platform::Key;
use slint::{ModelRc, SharedString, VecModel};
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, press, retype, shows, wait_until};

/// The main window in English with `count` copies of a fixture, every track selected. The folder
/// picker then offers `other`.
fn window_with(count: usize, other: &Path) -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/v23_full.mp3");
    for number in 1..=count {
        fs::copy(&fixture, folder.path().join(format!("{number}.mp3")))?;
    }
    let folders = RefCell::new(vec![other.to_path_buf(), folder.path().to_path_buf()]);
    let window = colophon_ui::main_window(Engine::new(), move || folders.borrow_mut().pop())?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    let tracks = if count == 1 { "track" } else { "tracks" };
    common::wait_until_shown(&window, &format!("{count} {tracks}"))?;
    press(&window, &[Key::Control], "a");
    Ok((window, folder))
}

/// The same with one track whose title was changed and not saved.
fn window_with_a_change() -> Result<(AppWindow, TempDir, TempDir), Box<dyn Error>> {
    let other = tempfile::tempdir()?;
    let (window, folder) = window_with(1, other.path())?;
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);
    Ok((window, folder, other))
}

fn title_on_disk(path: &Path) -> Result<Option<String>, Box<dyn Error>> {
    Ok(read(path)?.tags.title)
}

/// A button of the dialog, whose label an inspector button may share.
fn dialog_button(window: &AppWindow, label: &str) -> Result<ElementHandle, String> {
    let dialog = ElementHandle::find_by_element_type_name(window, "UnsavedChanges")
        .next()
        .ok_or("no unsaved changes dialog")?;
    let wanted = label.to_string();
    dialog
        .query_descendants()
        .match_accessible_role(AccessibleRole::Button)
        .match_predicate(move |button| button.accessible_label().is_some_and(|l| l == wanted))
        .find_first()
        .ok_or_else(|| format!("no dialog button labelled {label:?}"))
}

#[test]
fn closing_without_changes_closes_at_once() -> TestResult {
    let other = tempfile::tempdir()?;
    let (window, _folder) = window_with(1, other.path())?;

    assert!(colophon_ui::request_close(&window));
    assert!(!window.window().is_visible());
    Ok(())
}

#[test]
fn closing_with_changes_asks_first() -> TestResult {
    let (window, _folder, _other) = window_with_a_change()?;

    assert!(!colophon_ui::request_close(&window));

    assert!(window.window().is_visible());
    assert!(shows(&window, "Save changes to 1 file before quitting?"));
    assert!(shows(
        &window,
        "Neon Overpass has changes that are not saved yet. Quitting without saving discards them."
    ));
    Ok(())
}

#[test]
fn cancel_and_escape_keep_the_changes() -> TestResult {
    let (window, _folder, _other) = window_with_a_change()?;

    colophon_ui::request_close(&window);
    dialog_button(&window, "Cancel")?.invoke_accessible_default_action();
    assert!(!window.get_asking_to_save());

    colophon_ui::request_close(&window);
    press(&window, &[], Key::Escape);
    assert!(!window.get_asking_to_save());

    assert!(window.window().is_visible());
    assert_eq!(window.get_modified_count(), 1);
    Ok(())
}

#[test]
fn dont_save_closes_without_writing() -> TestResult {
    let (window, folder, _other) = window_with_a_change()?;

    colophon_ui::request_close(&window);
    dialog_button(&window, "Don’t Save")?.invoke_accessible_default_action();

    assert!(!window.window().is_visible());
    assert_eq!(
        title_on_disk(&folder.path().join("1.mp3"))?.as_deref(),
        Some("Paper Satellites")
    );
    Ok(())
}

#[test]
fn save_writes_the_files_then_closes() -> TestResult {
    let (window, folder, _other) = window_with_a_change()?;

    colophon_ui::request_close(&window);
    dialog_button(&window, "Save 1 file")?.invoke_accessible_default_action();
    wait_until(&window, "the window to close", |window| {
        !window.window().is_visible()
    })?;

    assert_eq!(
        title_on_disk(&folder.path().join("1.mp3"))?.as_deref(),
        Some("Neon Overpass")
    );
    Ok(())
}

#[test]
fn return_saves() -> TestResult {
    let (window, folder, _other) = window_with_a_change()?;

    colophon_ui::request_close(&window);
    press(&window, &[], Key::Return);
    wait_until(&window, "the window to close", |window| {
        !window.window().is_visible()
    })?;

    assert_eq!(
        title_on_disk(&folder.path().join("1.mp3"))?.as_deref(),
        Some("Neon Overpass")
    );
    Ok(())
}

#[test]
fn a_file_that_cannot_be_saved_keeps_the_window_open() -> TestResult {
    let (window, folder, _other) = window_with_a_change()?;
    let path = folder.path().join("1.mp3");
    let mut permissions = fs::metadata(&path)?.permissions();
    permissions.set_readonly(true);
    fs::set_permissions(&path, permissions)?;

    colophon_ui::request_close(&window);
    dialog_button(&window, "Save 1 file")?.invoke_accessible_default_action();
    wait_until(&window, "the save", |window| !window.get_saving())?;
    i_slint_backend_testing::mock_elapsed_time(std::time::Duration::from_millis(60));

    assert!(window.window().is_visible());
    assert!(!window.get_asking_to_save());
    assert!(shows(&window, "1 file could not be saved"));
    Ok(())
}

#[test]
fn opening_another_folder_asks_first() -> TestResult {
    let (window, _folder, other) = window_with_a_change()?;
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/v24_full.mp3"),
        other.path().join("a.mp3"),
    )?;

    find(&window, "Open folder")?.invoke_accessible_default_action();
    assert!(shows(
        &window,
        "Save changes to 1 file before opening another folder?"
    ));
    dialog_button(&window, "Don’t Save")?.invoke_accessible_default_action();
    wait_until(&window, "the other folder", |window| {
        window.get_scan_state() == ScanState::Completed && window.get_track_count() == 1
    })?;

    assert_eq!(window.get_modified_count(), 0);
    assert!(
        window.get_folder().ends_with(
            other
                .path()
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .unwrap_or_default()
                .as_str()
        )
    );
    Ok(())
}

#[test]
fn the_dialog_names_three_tracks_and_counts_the_others() -> TestResult {
    let other = tempfile::tempdir()?;
    let (window, _folder) = window_with(5, other.path())?;
    retype(&window, "Title", "Neon Overpass")?;
    press(&window, &[], Key::Return);

    colophon_ui::request_close(&window);

    assert!(shows(
        &window,
        "Neon Overpass, Neon Overpass and 3 other files have changes that are not saved yet. \
         Quitting without saving discards them."
    ));
    Ok(())
}

/// A window over an opened folder, asking about the three tracks of the mockup.
fn window_asking(leaving: Leaving, windows: bool) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = AppWindow::new()?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.set_windows_buttons(windows);
    window.set_folder_open(true);
    window.set_folder("~/Music".into());
    window.set_scan_state(ScanState::Completed);
    window.set_modified_count(3);
    let titles: Vec<SharedString> = ["Glass Avenue", "Midnight Lithography", "Paper Satellites"]
        .map(SharedString::from)
        .to_vec();
    window.set_unsaved_titles(ModelRc::new(VecModel::from(titles)));
    window.set_leaving(leaving);
    window.set_asking_to_save(true);
    Ok(window)
}

fn x_of(window: &AppWindow, label: &str) -> Result<f32, String> {
    Ok(dialog_button(window, label)?.absolute_position().x)
}

#[test]
fn the_buttons_follow_the_platform_order() -> TestResult {
    let mac = window_asking(Leaving::Quit, false)?;
    mac.show()?;
    assert!(x_of(&mac, "Don’t Save")? < x_of(&mac, "Cancel")?);
    assert!(x_of(&mac, "Cancel")? < x_of(&mac, "Save 3 files")?);

    let windows = window_asking(Leaving::Quit, true)?;
    windows.show()?;
    assert!(x_of(&windows, "Save 3 files")? < x_of(&windows, "Don’t Save")?);
    assert!(x_of(&windows, "Don’t Save")? < x_of(&windows, "Cancel")?);
    Ok(())
}

#[test]
fn the_dialog_speaks_french() -> TestResult {
    let window = window_asking(Leaving::OpenFolder, false)?;
    common::select_language("fr")?;
    window.show()?;

    assert!(shows(
        &window,
        "Enregistrer les modifications de 3 fichiers avant d’ouvrir un autre dossier\u{a0}?"
    ));
    assert!(shows(&window, "Ne pas enregistrer"));
    Ok(())
}

#[test]
fn the_dialog_matches_its_references() -> TestResult {
    for (dark, theme) in [(true, "dark"), (false, "light")] {
        let window = window_asking(Leaving::Quit, false)?;
        window.global::<Theme>().set_dark(dark);
        window.show()?;
        assert_matches_reference(&window, &format!("unsaved-changes-{theme}.png"))?;
    }
    Ok(())
}
