mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{
    AppWindow, ComponentHandle, RemovedTag, ScanState, TagRemoval, Theme, WindowCommand,
};
use i_slint_backend_testing::{AccessibleRole, ElementHandle};
use slint::platform::{Key, PointerEventButton};
use slint::{ModelRc, SharedString, VecModel};
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, press, shows};

/// The main window in English, in developer mode, with one copy of `fixture` selected.
fn window_with_a_selected(fixture: &str) -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata")
            .join(fixture),
        folder.path().join("02 Glass Avenue.mp3"),
    )?;
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    press(&window, &[Key::Control], "a");
    window.invoke_run(WindowCommand::ToggleDeveloperMode);
    Ok((window, folder))
}

/// A choice of the Tag format section: its segments share their labels, None above all.
fn segment(window: &AppWindow, control: &str, label: &str) -> Result<ElementHandle, String> {
    let wanted = label.to_string();
    ElementHandle::find_by_accessible_label(window, control)
        .find(|element| element.accessible_role() == Some(AccessibleRole::RadioGroup))
        .ok_or_else(|| format!("no {control:?} control"))?
        .query_descendants()
        .match_predicate(move |element| element.accessible_label().is_some_and(|l| l == wanted))
        .find_first()
        .ok_or_else(|| format!("no {label:?} in {control:?}"))
}

fn checked(window: &AppWindow, control: &str, label: &str) -> Result<bool, String> {
    Ok(segment(window, control, label)?
        .accessible_checked()
        .unwrap_or(false))
}

#[test]
fn removing_id3v1_asks_first_and_keeping_it_changes_nothing() -> TestResult {
    let (window, _folder) = window_with_a_selected("v23_v1_long_title.mp3")?;

    segment(&window, "Write ID3v1", "None")?.invoke_accessible_default_action();
    assert!(shows(&window, "Remove the ID3v1 tag from 1 file?"));
    assert!(shows(&window, "02 Glass Avenue.mp3"));

    find(&window, "Keep ID3v1")?.invoke_accessible_default_action();

    assert!(!window.get_confirming_removal());
    assert_eq!(window.get_modified_count(), 0);
    assert!(checked(&window, "Write ID3v1", "1.1")?);
    Ok(())
}

#[test]
fn removing_id3v1_once_confirmed_waits_to_be_saved() -> TestResult {
    let (window, _folder) = window_with_a_selected("v23_v1_long_title.mp3")?;

    segment(&window, "Write ID3v1", "None")?.invoke_accessible_default_action();
    find(&window, "Remove ID3v1")?.invoke_accessible_default_action();

    assert!(!window.get_confirming_removal());
    assert_eq!(window.get_modified_count(), 1);
    assert!(checked(&window, "Write ID3v1", "None")?);
    Ok(())
}

#[test]
fn escape_keeps_the_tag_and_return_does_not_remove_it() -> TestResult {
    let (window, _folder) = window_with_a_selected("v23_v1_long_title.mp3")?;

    segment(&window, "Write ID3v2", "None")?.invoke_accessible_default_action();
    assert!(shows(&window, "Remove the ID3v2 tag from 1 file?"));
    press(&window, &[], Key::Return);
    assert!(window.get_confirming_removal());
    press(&window, &[], Key::Escape);

    assert!(!window.get_confirming_removal());
    assert_eq!(window.get_modified_count(), 0);
    Ok(())
}

#[test]
fn a_file_without_the_tag_is_not_asked_about() -> TestResult {
    let (window, _folder) = window_with_a_selected("v23_full.mp3")?;

    segment(&window, "Write ID3v1", "None")?.invoke_accessible_default_action();

    assert!(!window.get_confirming_removal());
    assert!(checked(&window, "Write ID3v1", "None")?);
    Ok(())
}

#[test]
fn the_dialog_matches_its_references() -> TestResult {
    for (dark, theme) in [(true, "dark"), (false, "light")] {
        common::use_testing_backend()?;
        let window = AppWindow::new()?;
        common::prepare(&window, 1440.0, 900.0)?;
        window.set_folder_open(true);
        window.set_scan_state(ScanState::Completed);
        let files: Vec<SharedString> = [
            "02 Glass Avenue.mp3",
            "03 Midnight Lithography.mp3",
            "04 Paper Satellites.mp3",
        ]
        .map(SharedString::from)
        .to_vec();
        window.set_removal(TagRemoval {
            tag: RemovedTag::Id3v1,
            count: 3,
            files: ModelRc::new(VecModel::from(files)),
            others: 0,
        });
        window.set_confirming_removal(true);
        window.global::<Theme>().set_dark(dark);
        window.show()?;
        assert_matches_reference(&window, &format!("tag-removal-{theme}.png"))?;
    }
    Ok(())
}

#[test]
fn a_click_outside_the_dialog_does_nothing() -> TestResult {
    let (window, _folder) = window_with_a_selected("v23_v1_long_title.mp3")?;
    segment(&window, "Write ID3v1", "None")?.invoke_accessible_default_action();

    find(&window, "Open folder")?.mock_single_click(PointerEventButton::Left);

    assert!(window.get_confirming_removal());
    // Opening the folder again would have emptied the selection.
    assert_eq!(window.get_selected_count(), 1);
    Ok(())
}
