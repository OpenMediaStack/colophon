mod common;

use std::cell::RefCell;
use std::error::Error;
use std::fs;
use std::path::PathBuf;
use std::rc::Rc;

use colophon_engine::Engine;
use colophon_engine::tags::{Id3v1Policy as Policy, Id3v2Version, TagFormat, WritePolicy, read};
use colophon_ui::{AppWindow, ComponentHandle, Id3v1Policy, ScanState, Theme, WindowCommand};
use i_slint_backend_testing::{AccessibleRole, ElementHandle};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, press, retype, shows};

/// The write policies a window hands over to keep.
type Kept = Rc<RefCell<Vec<WritePolicy>>>;

/// The main window in English with a copy of `fixture` selected, and the write policies it
/// keeps.
fn window_with_a_selected(fixture: &str) -> Result<(AppWindow, TempDir, Kept), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::copy(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata")
            .join(fixture),
        folder.path().join("1.mp3"),
    )?;
    let path = folder.path().to_path_buf();
    let kept = Kept::default();
    let window = colophon_ui::main_window_keeping(Engine::new(), move || Some(path.clone()), {
        let kept = Rc::clone(&kept);
        move |preferences: &colophon_engine::Preferences| {
            kept.borrow_mut().push(preferences.writing);
        }
    })?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    press(&window, &[Key::Control], "a");
    Ok((window, folder, kept))
}

/// A choice of a segmented control of the settings.
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

#[test]
fn the_settings_choose_how_tags_are_written() -> TestResult {
    let (window, _folder, kept) = window_with_a_selected("v24_unicode.mp3")?;
    window.set_settings_open(true);

    segment(&window, "ID3v2 version", "2.3")?.invoke_accessible_default_action();
    segment(&window, "ID3v1 tag", "Always")?.invoke_accessible_default_action();

    assert!(window.get_id3v2_3());
    assert_eq!(window.get_id3v1_policy(), Id3v1Policy::Always);
    assert_eq!(
        kept.borrow().last(),
        Some(&WritePolicy {
            id3v2: Id3v2Version::V2_3,
            id3v1: Policy::Always,
        })
    );
    Ok(())
}

#[test]
fn developer_mode_is_a_setting() -> TestResult {
    let (window, _folder, _kept) = window_with_a_selected("v24_unicode.mp3")?;
    window.set_settings_open(true);

    find(&window, "Developer mode")?.invoke_accessible_default_action();
    assert!(window.get_developer_mode());

    find(&window, "Done")?.invoke_accessible_default_action();
    assert!(!window.get_settings_open());
    Ok(())
}

#[test]
fn saving_while_never_writing_id3v1_asks_first() -> TestResult {
    let (window, folder, _kept) = window_with_a_selected("v23_v1_long_title.mp3")?;
    window.set_settings_open(true);
    segment(&window, "ID3v1 tag", "Never")?.invoke_accessible_default_action();
    press(&window, &[], Key::Escape);
    retype(&window, "Album", "Analog Hearts")?;
    press(&window, &[], Key::Return);

    window.invoke_run(WindowCommand::Save);
    assert!(shows(&window, "Remove the ID3v1 tag from 1 file?"));
    find(&window, "Keep ID3v1")?.mock_single_click(PointerEventButton::Left);
    common::wait_until(&window, "the save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })?;

    let formats = read(&folder.path().join("1.mp3"))?.formats;
    assert!(
        formats
            .iter()
            .any(|format| matches!(format, TagFormat::Id3v1(_)))
    );
    Ok(())
}

#[test]
fn the_settings_match_their_references() -> TestResult {
    for (dark, theme) in [(true, "dark"), (false, "light")] {
        common::use_testing_backend()?;
        let window = AppWindow::new()?;
        common::prepare(&window, 1440.0, 900.0)?;
        window.set_folder_open(true);
        window.set_scan_state(ScanState::Completed);
        window.set_id3v1_policy(Id3v1Policy::Keep);
        window.set_settings_open(true);
        window.global::<Theme>().set_dark(dark);
        window.show()?;
        assert_matches_reference(&window, &format!("settings-{theme}.png"))?;
    }
    Ok(())
}
