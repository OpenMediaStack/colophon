mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_engine::tags::read;
use colophon_ui::{AppWindow, ComponentHandle, CoverState, Dialogs};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, find, press, wait_until};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata")
        .join(name)
}

/// Dialogs that open `folder`, pick `image` and save to `saved`.
struct Pick {
    folder: PathBuf,
    image: PathBuf,
    saved: PathBuf,
}

impl Dialogs for Pick {
    fn pick_folder(&self) -> Option<PathBuf> {
        Some(self.folder.clone())
    }

    fn pick_image(&self) -> Option<PathBuf> {
        Some(self.image.clone())
    }

    fn pick_save_path(&self, _suggested: &str) -> Option<PathBuf> {
        Some(self.saved.clone())
    }
}

/// The main window in English over a track with a cover, "With a cover", and one without,
/// "Paper Satellites".
fn window_with_covers() -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::create_dir(folder.path().join("music"))?;
    fs::copy(fixture("v23_cover.mp3"), folder.path().join("music/1.mp3"))?;
    fs::copy(fixture("v23_full.mp3"), folder.path().join("music/2.mp3"))?;
    let cover = read(&fixture("v23_cover.mp3"))?
        .tags
        .cover
        .ok_or("the fixture has a cover")?;
    fs::write(folder.path().join("cover.png"), &*cover.data)?;
    let dialogs = Pick {
        folder: folder.path().join("music"),
        image: folder.path().join("cover.png"),
        saved: folder.path().join("extracted.png"),
    };
    let window = colophon_ui::main_window(Engine::new(), dialogs)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "2 tracks")?;
    Ok((window, folder))
}

fn cover_state(window: &AppWindow) -> CoverState {
    window.get_inspected_tracks().cover_state
}

#[test]
fn a_track_shows_its_cover_and_several_tracks_say_they_differ() -> TestResult {
    let (window, _folder) = window_with_covers()?;

    find(&window, "With a cover")?.mock_single_click(PointerEventButton::Left);
    assert_eq!(cover_state(&window), CoverState::Shared);
    assert!(window.get_inspected_tracks().cover.size().width > 0);

    press(&window, &[Key::Control], "a");
    assert_eq!(cover_state(&window), CoverState::Mixed);
    Ok(())
}

#[test]
fn replacing_the_cover_of_every_selected_track_waits_to_be_saved() -> TestResult {
    let (window, folder) = window_with_covers()?;
    find(&window, "With a cover")?.mock_single_click(PointerEventButton::Left);
    press(&window, &[Key::Control], "a");

    find(&window, "Replace cover…")?.invoke_accessible_default_action();
    assert_eq!(cover_state(&window), CoverState::Shared);
    assert_eq!(window.get_modified_count(), 1);

    press(&window, &[Key::Control], "s");
    wait_until(&window, "the save", |window| {
        !window.get_saving() && window.get_modified_count() == 0
    })?;
    assert!(
        read(&folder.path().join("music/2.mp3"))?
            .tags
            .cover
            .is_some()
    );
    Ok(())
}

#[test]
fn a_cover_is_removed_and_extracted() -> TestResult {
    let (window, folder) = window_with_covers()?;
    find(&window, "With a cover")?.mock_single_click(PointerEventButton::Left);

    window.invoke_extract_cover();
    assert_eq!(
        fs::read(folder.path().join("extracted.png"))?,
        fs::read(folder.path().join("cover.png"))?
    );

    window.invoke_remove_cover();
    assert_eq!(cover_state(&window), CoverState::None);
    assert_eq!(window.get_modified_count(), 1);
    Ok(())
}

#[test]
fn an_album_shows_its_cover_in_the_sidebar_once_drawn() -> TestResult {
    let (window, _folder) = window_with_covers()?;
    find(&window, "Paper Satellites")?.mock_single_click(PointerEventButton::Left);
    find(&window, "Replace cover…")?.invoke_accessible_default_action();
    press(&window, &[Key::Control], "s");

    wait_until(&window, "the album cover", |window| {
        let albums = window.get_album_sources();
        (0..slint::Model::row_count(&albums))
            .any(|row| slint::Model::row_data(&albums, row).is_some_and(|album| album.has_cover))
    })?;
    Ok(())
}
