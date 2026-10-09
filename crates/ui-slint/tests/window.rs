use std::error::Error;
use std::path::Path;

use colophon_ui::{AppWindow, ComponentHandle, Theme};
use i_slint_backend_testing::{ElementHandle, TestingBackend, TestingBackendOptions};
use slint::LogicalSize;
use slint::platform::SetPlatformError;

type TestResult = Result<(), Box<dyn Error>>;

fn open_window(dark: bool) -> Result<AppWindow, Box<dyn Error>> {
    let backend = TestingBackend::new(TestingBackendOptions {
        mock_time: true,
        renderer_name: Some("software".into()),
        ..Default::default()
    });
    match slint::platform::set_platform(Box::new(backend)) {
        Ok(()) | Err(SetPlatformError::AlreadySet) => {}
        Err(error) => return Err(error.to_string().into()),
    }
    let window = AppWindow::new()?;
    select_language("")?;
    window.global::<Theme>().set_dark(dark);
    window.window().set_size(LogicalSize::new(1280.0, 800.0));
    window.show()?;
    Ok(window)
}

/// The system language would otherwise pick the translation, so tests choose one.
fn select_language(language: &str) -> TestResult {
    slint::select_bundled_translation(language)
        .map_err(|error| format!("{language:?}: {error}").into())
}

fn find(window: &AppWindow, label: &str) -> Result<ElementHandle, String> {
    ElementHandle::find_by_accessible_label(window, label)
        .next()
        .ok_or_else(|| format!("no element labelled {label:?}"))
}

#[test]
fn the_window_speaks_english_by_default() -> TestResult {
    let window = open_window(true)?;

    find(&window, "Open your music folder")?;
    Ok(())
}

#[test]
fn the_window_speaks_french_when_selected() -> TestResult {
    let window = open_window(true)?;

    select_language("fr")?;

    find(&window, "Ouvrez votre dossier de musique")?;
    Ok(())
}

#[test]
fn the_dark_window_matches_its_reference() -> TestResult {
    let window = open_window(true)?;
    assert_matches_reference(&window, "window-dark.png")
}

#[test]
fn the_light_window_matches_its_reference() -> TestResult {
    let window = open_window(false)?;
    assert_matches_reference(&window, "window-light.png")
}

fn assert_matches_reference(window: &AppWindow, name: &str) -> TestResult {
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
