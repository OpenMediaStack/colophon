mod common;

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use colophon_engine::{Engine, Output, PlayError};
use colophon_ui::{AppWindow, ComponentHandle, Dialogs, Theme, Toast, ToastMessage, WindowCommand};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, press, retype, shows};

/// A desktop that opens a folder and picks an image.
struct Desktop {
    folder: PathBuf,
    image: PathBuf,
}

impl Dialogs for Desktop {
    fn pick_folder(&self) -> Option<PathBuf> {
        Some(self.folder.clone())
    }

    fn pick_image(&self) -> Option<PathBuf> {
        Some(self.image.clone())
    }
}

/// An output whose files never play.
#[derive(Debug)]
struct Broken;

impl Output for Broken {
    fn play(&mut self, _: &Path) -> Result<(), PlayError> {
        Err(PlayError::Decode("no frames".into()))
    }
    fn pause(&mut self) {}
    fn resume(&mut self) {}
    fn stop(&mut self) {}
    fn seek(&mut self, _: Duration) -> Result<(), PlayError> {
        Ok(())
    }
    fn position(&self) -> Duration {
        Duration::ZERO
    }
    fn finished(&self) -> bool {
        false
    }
    fn set_volume(&mut self, _: f32) {}
}

/// The main window in English from `engine`, with "Paper Satellites" selected.
fn window_with_a_track(engine: Engine) -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/v23_full.mp3"),
        folder.path().join("1.mp3"),
    )?;
    fs::write(folder.path().join("notes.txt"), "not an image")?;
    let desktop = Desktop {
        folder: folder.path().to_path_buf(),
        image: folder.path().join("notes.txt"),
    };
    let window = colophon_ui::main_window(engine, desktop)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    Ok((window, folder))
}

fn edit_and_save(window: &AppWindow) -> TestResult {
    retype(window, "Album", "Analog Hearts")?;
    press(window, &[], Key::Return);
    window.invoke_run(WindowCommand::Save);
    common::wait_until(window, "the save", |window| !window.get_saving())
}

fn set_read_only(path: &Path, read_only: bool) -> TestResult {
    let mut permissions = fs::metadata(path)?.permissions();
    permissions.set_readonly(read_only);
    fs::set_permissions(path, permissions)?;
    Ok(())
}

#[test]
fn a_save_says_it_saved_then_the_toast_goes() -> TestResult {
    let (window, _folder) = window_with_a_track(Engine::new())?;

    edit_and_save(&window)?;
    assert!(shows(&window, "Saved 1 file"));

    i_slint_backend_testing::mock_elapsed_time(Duration::from_secs(5));
    assert!(!shows(&window, "Saved 1 file"));
    Ok(())
}

#[test]
fn a_failed_save_can_be_retried_from_its_toast() -> TestResult {
    let (window, folder) = window_with_a_track(Engine::new())?;
    let path = folder.path().join("1.mp3");
    set_read_only(&path, true)?;

    edit_and_save(&window)?;
    assert!(shows(&window, "1 file could not be saved"));

    set_read_only(&path, false)?;
    find(&window, "Retry")?.invoke_accessible_default_action();
    common::wait_until(&window, "the second save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })?;
    assert!(shows(&window, "Saved 1 file"));
    Ok(())
}

#[test]
fn an_image_that_cannot_be_read_is_told() -> TestResult {
    let (window, _folder) = window_with_a_track(Engine::new())?;

    window.invoke_replace_cover();

    assert!(shows(&window, "“notes.txt” is not a JPEG or PNG image"));
    assert_eq!(window.get_modified_count(), 0);
    Ok(())
}

#[test]
fn a_track_that_cannot_play_is_told() -> TestResult {
    let (window, _folder) = window_with_a_track(Engine::with_output(Broken))?;

    press(&window, &[], " ");

    assert!(shows(&window, "Could not play “Paper Satellites”"));
    find(&window, "Close")?.invoke_accessible_default_action();
    assert!(!shows(&window, "Could not play “Paper Satellites”"));
    Ok(())
}

#[test]
fn a_toast_matches_its_references() -> TestResult {
    for (dark, theme) in [(true, "dark"), (false, "light")] {
        common::use_testing_backend()?;
        let window = AppWindow::new()?;
        common::prepare(&window, 1440.0, 900.0)?;
        window.global::<Theme>().set_dark(dark);
        window.set_toast(Toast {
            message: ToastMessage::SaveFailed,
            count: 2,
            name: "".into(),
        });
        window.set_toast_shown(true);
        window.show()?;
        assert_matches_reference(&window, &format!("toast-{theme}.png"))?;
    }
    Ok(())
}
