mod common;

use std::cell::RefCell;
use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration;

use colophon_engine::{Engine, Output, PlayError};
use colophon_ui::{AppWindow, ComponentHandle};
use slint::Model;
use slint::platform::PointerEventButton;
use tempfile::TempDir;

use common::{TestResult, find, press};

#[derive(Debug, Default)]
struct Speakers {
    playing: Option<PathBuf>,
    paused: bool,
    position: Duration,
    volume: f32,
}

/// An output that remembers what it was asked.
#[derive(Debug, Clone, Default)]
struct Fake(Rc<RefCell<Speakers>>);

impl Output for Fake {
    fn play(&mut self, path: &Path) -> Result<(), PlayError> {
        let mut speakers = self.0.borrow_mut();
        speakers.playing = Some(path.to_path_buf());
        speakers.paused = false;
        Ok(())
    }

    fn pause(&mut self) {
        self.0.borrow_mut().paused = true;
    }

    fn resume(&mut self) {
        self.0.borrow_mut().paused = false;
    }

    fn stop(&mut self) {
        self.0.borrow_mut().playing = None;
    }

    fn seek(&mut self, position: Duration) -> Result<(), PlayError> {
        self.0.borrow_mut().position = position;
        Ok(())
    }

    fn position(&self) -> Duration {
        self.0.borrow().position
    }

    fn finished(&self) -> bool {
        false
    }

    fn set_volume(&mut self, volume: f32) {
        self.0.borrow_mut().volume = volume;
    }
}

/// The main window in English playing through a fake output, over "Paper Satellites" and
/// "Café", the first selected.
fn window_playing() -> Result<(AppWindow, TempDir, Fake), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    fs::copy(fixtures.join("v23_full.mp3"), folder.path().join("1.mp3"))?;
    fs::copy(
        fixtures.join("v23_unicode.mp3"),
        folder.path().join("2.mp3"),
    )?;
    let fake = Fake::default();
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::with_output(fake.clone()), move || {
        Some(path.clone())
    })?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "2 tracks")?;
    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);
    Ok((window, folder, fake))
}

fn playing(fake: &Fake) -> Option<String> {
    fake.0
        .borrow()
        .playing
        .as_deref()
        .and_then(Path::file_name)
        .map(|name| name.to_string_lossy().into_owned())
}

#[test]
fn space_plays_the_selected_track_and_marks_its_row() -> TestResult {
    let (window, _folder, fake) = window_playing()?;

    press(&window, &[], " ");

    assert_eq!(playing(&fake).as_deref(), Some("1.mp3"));
    assert_eq!(window.get_player_title(), "Paper Satellites");
    assert!(window.get_player_playing());
    assert!(
        window
            .get_tracks()
            .row_data(0)
            .is_some_and(|row| row.playing)
    );
    Ok(())
}

#[test]
fn the_player_pauses_and_moves_to_the_next_track() -> TestResult {
    let (window, _folder, fake) = window_playing()?;
    press(&window, &[], " ");

    find(&window, "Pause")?.invoke_accessible_default_action();
    assert!(fake.0.borrow().paused);
    assert!(!window.get_player_playing());

    find(&window, "Next track")?.invoke_accessible_default_action();
    assert_eq!(playing(&fake).as_deref(), Some("2.mp3"));
    assert_eq!(window.get_player_title(), "Café");
    assert!(
        window
            .get_tracks()
            .row_data(0)
            .is_some_and(|row| !row.playing)
    );
    Ok(())
}

#[test]
fn the_position_and_the_volume_reach_the_output() -> TestResult {
    let (window, _folder, fake) = window_playing()?;
    press(&window, &[], " ");

    window.invoke_player_seek(0.5);
    window.invoke_player_set_volume(0.3);

    assert!(fake.0.borrow().position > Duration::ZERO);
    assert!((fake.0.borrow().volume - 0.3).abs() < 0.01);
    Ok(())
}

#[test]
fn without_a_sound_device_the_player_is_off() -> TestResult {
    common::use_testing_backend()?;
    let window = colophon_ui::main_window(Engine::new(), || None)?;
    window.show()?;

    assert!(!window.get_player_available());
    assert_eq!(find(&window, "Play")?.accessible_enabled(), Some(false));
    Ok(())
}

#[test]
fn the_waveform_shows_once_read() -> TestResult {
    let (window, _folder, _fake) = window_playing()?;

    press(&window, &[], " ");

    common::wait_until(&window, "the waveform", |window| {
        window.get_player_has_waveform()
    })?;
    assert!(window.get_player_waveform().size().width > 0);
    Ok(())
}
