// Each test file uses only part of these helpers.
#![allow(dead_code)]

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

use colophon_ui::{AppWindow, ComponentHandle};
use i_slint_backend_testing::{ElementHandle, TestingBackend, TestingBackendOptions};
use slint::platform::{Key, PointerEventButton, SetPlatformError, WindowEvent};
use slint::{LogicalPosition, LogicalSize, SharedString};
use tempfile::TempDir;

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
            "{name} differs from its reference {}, see {}",
            differing_area(&expected, &actual),
            actual_path.display()
        )
        .into());
    }
    Ok(())
}

/// Where two images differ, to find out from a log what changed.
fn differing_area(expected: &image::RgbaImage, actual: &image::RgbaImage) -> String {
    if expected.dimensions() != actual.dimensions() {
        return format!(
            "in size, {:?} instead of {:?}",
            actual.dimensions(),
            expected.dimensions()
        );
    }
    let differing = expected
        .enumerate_pixels()
        .filter(|(x, y, pixel)| actual.get_pixel(*x, *y) != *pixel);
    let (mut left, mut top, mut right, mut bottom, mut count) = (u32::MAX, u32::MAX, 0, 0, 0);
    for (x, y, _) in differing {
        left = left.min(x);
        top = top.min(y);
        right = right.max(x);
        bottom = bottom.max(y);
        count += 1;
    }
    format!("in {count} pixels from ({left}, {top}) to ({right}, {bottom})")
}

/// A folder holding a copy of `fixture`, a file of `testdata/`, at `name`.
pub fn folder_with_fixture(fixture: &str, name: &str) -> Result<TempDir, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    let path = folder.path().join(name);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    fs::copy(fixtures.join(fixture), path)?;
    Ok(folder)
}

/// Lets the scan thread work and the window's timers fire, until `label` shows or a few seconds pass.
pub fn wait_until_shown(window: &AppWindow, label: &str) -> TestResult {
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

/// An item of the open menu. Its label is a Text, like the header cell of the same name; Slint
/// names the menu's own `MenuItemBase::label`.
pub fn menu_item(window: &AppWindow, label: &str) -> Result<ElementHandle, String> {
    ElementHandle::find_by_accessible_label(window, label)
        .find(|element| element.id().is_some_and(|id| id == "MenuItemBase::label"))
        .ok_or_else(|| format!("no menu item labelled {label:?}"))
}

/// Where a column's resize handle is: the last pixels of its header cell, which ends 8 pixels of
/// padding after its name.
pub fn resize_handle(window: &AppWindow, name: &str) -> Result<LogicalPosition, String> {
    let name = find(window, name)?;
    let position = name.absolute_position();
    let size = name.size();
    Ok(LogicalPosition::new(
        position.x + size.width + 8.0 - 3.0,
        position.y + size.height / 2.0,
    ))
}

/// Drags with the left button through raw pointer events, as a mouse would.
pub fn drag(window: &AppWindow, from: LogicalPosition, to: LogicalPosition) {
    let left = PointerEventButton::Left;
    for event in [
        WindowEvent::PointerMoved { position: from },
        WindowEvent::PointerPressed {
            position: from,
            button: left,
        },
        WindowEvent::PointerMoved { position: to },
        WindowEvent::PointerReleased {
            position: to,
            button: left,
        },
    ] {
        window.window().dispatch_event(event);
    }
}

pub fn double_click(window: &AppWindow, at: LogicalPosition) {
    let left = PointerEventButton::Left;
    window
        .window()
        .dispatch_event(WindowEvent::PointerMoved { position: at });
    for _ in 0..2 {
        window.window().dispatch_event(WindowEvent::PointerPressed {
            position: at,
            button: left,
        });
        window
            .window()
            .dispatch_event(WindowEvent::PointerReleased {
                position: at,
                button: left,
            });
    }
}

/// Presses and releases `key` while holding the `held` keys, as a keyboard would.
pub fn press(window: &AppWindow, held: &[Key], key: impl Into<SharedString>) {
    let key = key.into();
    let window = window.window();
    for modifier in held {
        window.dispatch_event(WindowEvent::KeyPressed {
            text: (*modifier).into(),
        });
    }
    window.dispatch_event(WindowEvent::KeyPressed { text: key.clone() });
    window.dispatch_event(WindowEvent::KeyReleased { text: key });
    for modifier in held.iter().rev() {
        window.dispatch_event(WindowEvent::KeyReleased {
            text: (*modifier).into(),
        });
    }
}

/// Clicks `label` while holding the `held` keys.
pub fn click_holding(window: &AppWindow, held: &[Key], label: &str) -> Result<(), String> {
    let element = find(window, label)?;
    for modifier in held {
        window.window().dispatch_event(WindowEvent::KeyPressed {
            text: (*modifier).into(),
        });
    }
    element.mock_single_click(PointerEventButton::Left);
    for modifier in held.iter().rev() {
        window.window().dispatch_event(WindowEvent::KeyReleased {
            text: (*modifier).into(),
        });
    }
    Ok(())
}

/// The text input of an inspector field, whose label a table header may share.
pub fn input(window: &AppWindow, label: &str) -> Result<ElementHandle, String> {
    ElementHandle::find_by_accessible_label(window, label)
        .find(|element| {
            element.accessible_role() == Some(i_slint_backend_testing::AccessibleRole::TextInput)
        })
        .ok_or_else(|| format!("no text input labelled {label:?}"))
}

/// Types `text` into the focused element, one key after the other.
pub fn type_text(window: &AppWindow, text: &str) {
    for character in text.chars() {
        let key = SharedString::from(character.to_string());
        window
            .window()
            .dispatch_event(WindowEvent::KeyPressed { text: key.clone() });
        window
            .window()
            .dispatch_event(WindowEvent::KeyReleased { text: key });
    }
}

/// Puts `text` in place of what an inspector field holds, without keeping it yet.
pub fn retype(window: &AppWindow, label: &str, text: &str) -> TestResult {
    input(window, label)?.mock_single_click(PointerEventButton::Left);
    press(window, &[Key::Control], "a");
    type_text(window, text);
    Ok(())
}

/// Lets the engine's threads work and the window's timers fire, until `done` holds or a few
/// seconds pass.
pub fn wait_until(window: &AppWindow, what: &str, done: impl Fn(&AppWindow) -> bool) -> TestResult {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !done(window) {
        if Instant::now() > deadline {
            return Err(format!("{what} never happened").into());
        }
        thread::sleep(Duration::from_millis(2));
        i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(60));
    }
    Ok(())
}
