use std::error::Error;
use std::path::Path;

use colophon_ui::{AppWindow, ComponentHandle, Theme};
use i_slint_backend_testing::{ElementHandle, TestingBackend, TestingBackendOptions};
use slint::LogicalSize;
use slint::platform::SetPlatformError;

type TestResult = Result<(), Box<dyn Error>>;

const REGIONS: [&str; 6] = [
    "Toolbar",
    "Sidebar",
    "Tracks",
    "Player",
    "Inspector",
    "Status bar",
];

/// A window of the given size, in English, not shown yet so that a test can set it up first.
fn new_window(width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
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
    window.window().set_size(LogicalSize::new(width, height));
    Ok(window)
}

/// The system language would otherwise pick the translation, so tests choose one.
fn select_language(language: &str) -> TestResult {
    slint::select_bundled_translation(language)
        .map_err(|error| format!("{language:?}: {error}").into())
}

fn shows(window: &AppWindow, label: &str) -> bool {
    ElementHandle::find_by_accessible_label(window, label)
        .next()
        .is_some()
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

#[test]
fn the_sidebar_gives_way_in_a_small_window() -> TestResult {
    let window = new_window(960.0, 600.0)?;
    window.show()?;

    assert!(!shows(&window, "Sidebar"));
    assert!(shows(&window, "Tracks"));
    assert!(shows(&window, "Inspector"));
    Ok(())
}

#[test]
fn the_sidebar_comes_back_when_the_window_grows() -> TestResult {
    let window = new_window(960.0, 600.0)?;
    window.show()?;
    assert!(!shows(&window, "Sidebar"));

    window.window().set_size(LogicalSize::new(1440.0, 900.0));
    i_slint_backend_testing::mock_elapsed_time(std::time::Duration::from_millis(16));

    assert!(shows(&window, "Sidebar"));
    Ok(())
}

#[test]
fn hiding_the_inspector_makes_room_for_the_sidebar() -> TestResult {
    let window = new_window(960.0, 600.0)?;
    window.set_inspector_visible(false);
    window.show()?;

    assert!(shows(&window, "Sidebar"));
    assert!(!shows(&window, "Inspector"));
    Ok(())
}

#[test]
fn hidden_panels_are_not_shown() -> TestResult {
    let window = new_window(1440.0, 900.0)?;
    window.set_sidebar_visible(false);
    window.set_inspector_visible(false);
    window.show()?;

    assert!(!shows(&window, "Sidebar"));
    assert!(!shows(&window, "Inspector"));
    assert!(shows(&window, "Tracks"));
    Ok(())
}

#[test]
fn the_regions_are_named_in_french_when_selected() -> TestResult {
    let window = new_window(1440.0, 900.0)?;
    select_language("fr")?;
    window.show()?;

    assert!(shows(&window, "Morceaux"));
    assert!(shows(&window, "Barre latérale"));
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
