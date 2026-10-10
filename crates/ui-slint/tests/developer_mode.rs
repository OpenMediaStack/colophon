mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_engine::tags::{Id3v2Version, TagFormat, read};
use colophon_ui::{AppWindow, ComponentHandle, WindowCommand};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, find, press, shows, wait_until};

/// The main window in English with "Paper Satellites", in ID3v2.3 alone, selected.
fn window_with_an_id3v2_3_track() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/v23_full.mp3"),
        folder.path().join("1.mp3"),
    )?;
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    Ok((window, folder))
}

fn checked(window: &AppWindow, label: &str) -> Result<bool, String> {
    Ok(find(window, label)?.accessible_checked().unwrap_or(false))
}

#[test]
fn the_tag_format_section_shows_in_developer_mode_only() -> TestResult {
    let (window, _folder) = window_with_an_id3v2_3_track()?;
    assert!(!shows(&window, "Write ID3v2"));
    assert!(!shows(&window, "Developer mode"));

    window.invoke_run(WindowCommand::ToggleDeveloperMode);

    assert!(shows(&window, "Write ID3v2"));
    assert!(shows(&window, "Developer mode"));
    assert!(checked(&window, "2.4")?);
    Ok(())
}

#[test]
fn a_version_chosen_is_written_on_save() -> TestResult {
    let (window, folder) = window_with_an_id3v2_3_track()?;
    window.invoke_run(WindowCommand::ToggleDeveloperMode);

    find(&window, "2.2")?.invoke_accessible_default_action();
    assert!(checked(&window, "2.2")?);
    assert!(shows(
        &window,
        "Saving converts 1 file from ID3v2.3 to ID3v2.2."
    ));
    press(&window, &[Key::Control], "s");
    wait_until(&window, "the save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })?;

    assert_eq!(
        read(&folder.path().join("1.mp3"))?.formats,
        [TagFormat::Id3v2(Id3v2Version::V2_2)]
    );
    Ok(())
}

#[test]
fn undo_takes_a_version_back() -> TestResult {
    let (window, _folder) = window_with_an_id3v2_3_track()?;
    window.invoke_run(WindowCommand::ToggleDeveloperMode);
    find(&window, "1.1")?.invoke_accessible_default_action();
    assert_eq!(window.get_modified_count(), 1);

    press(&window, &[Key::Control], "z");

    assert_eq!(window.get_modified_count(), 0);
    assert!(checked(&window, "2.4")?);
    Ok(())
}
