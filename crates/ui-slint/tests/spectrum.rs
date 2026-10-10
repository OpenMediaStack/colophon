mod common;

use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::ComponentHandle;
use slint::platform::PointerEventButton;

use common::{TestResult, find, wait_until};

#[test]
fn a_track_selected_alone_shows_its_spectrum() -> TestResult {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    fs::copy(fixtures.join("v23_full.mp3"), folder.path().join("1.mp3"))?;
    fs::copy(
        fixtures.join("v23_unicode.mp3"),
        folder.path().join("2.mp3"),
    )?;
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "2 tracks")?;

    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    wait_until(&window, "the spectrum", |window| window.get_has_spectrum())?;

    let spectrum = window.get_spectrum();
    assert_eq!(spectrum.image.size().width, 576);
    assert_eq!(spectrum.nyquist.whole, 22);
    assert!(common::shows(&window, "SPECTRUM"));

    common::press(&window, &[slint::platform::Key::Control], "a");
    assert!(!window.get_has_spectrum());
    Ok(())
}
