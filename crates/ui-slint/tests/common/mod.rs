// Each test file uses only part of these helpers.
#![allow(dead_code)]

use std::error::Error;
use std::path::Path;

use colophon_ui::{AppWindow, ComponentHandle};
use i_slint_backend_testing::{ElementHandle, TestingBackend, TestingBackendOptions};
use slint::LogicalSize;
use slint::platform::SetPlatformError;

pub type TestResult = Result<(), Box<dyn Error>>;

/// Runs Slint on its testing backend: no window on screen, mocked time, and the software renderer for captures.
pub fn use_testing_backend() -> TestResult {
    let backend = TestingBackend::new(TestingBackendOptions {
        mock_time: true,
        renderer_name: Some("software".into()),
        ..Default::default()
    });
    match slint::platform::set_platform(Box::new(backend)) {
        Ok(()) | Err(SetPlatformError::AlreadySet) => Ok(()),
        Err(error) => Err(error.to_string().into()),
    }
}

/// Sets a window in English, with macOS shortcuts, at the given size, before it is shown.
pub fn prepare(window: &AppWindow, width: f32, height: f32) -> TestResult {
    select_language("")?;
    window.set_mac_shortcuts(true);
    window.window().set_size(LogicalSize::new(width, height));
    Ok(())
}

/// The system language would otherwise pick the translation, so tests choose one.
pub fn select_language(language: &str) -> TestResult {
    slint::select_bundled_translation(language)
        .map_err(|error| format!("{language:?}: {error}").into())
}

pub fn find(window: &AppWindow, label: &str) -> Result<ElementHandle, String> {
    ElementHandle::find_by_accessible_label(window, label)
        .next()
        .ok_or_else(|| format!("no element labelled {label:?}"))
}

pub fn shows(window: &AppWindow, label: &str) -> bool {
    ElementHandle::find_by_accessible_label(window, label)
        .next()
        .is_some()
}

pub fn assert_matches_reference(window: &AppWindow, name: &str) -> TestResult {
    let snapshot = window.window().take_snapshot()?;
    let actual = image::RgbaImage::from_raw(
        snapshot.width(),
        snapshot.height(),
        snapshot.as_bytes().to_vec(),
    )
    .ok_or("the snapshot's size does not match its pixels")?;
    let references = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/references");
    let reference = references.join(name);

    if std::env::var_os("UPDATE_REFERENCES").is_some() {
        std::fs::create_dir_all(&references)?;
        actual.save(&reference)?;
        return Ok(());
    }

    let expected = image::open(&reference)
        .map_err(|error| {
            format!(
                "{}: {error}, run with UPDATE_REFERENCES=1 to create it",
                reference.display()
            )
        })?
        .to_rgba8();
    if expected != actual {
        let actual_path = std::env::temp_dir().join(name);
        actual.save(&actual_path)?;
        return Err(format!(
            "{name} differs from its reference, see {}",
            actual_path.display()
        )
        .into());
    }
    Ok(())
}
