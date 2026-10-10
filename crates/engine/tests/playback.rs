mod common;

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration;

use colophon_engine::{Command, Engine, Output, PlayError, SortColumn};
use tempfile::TempDir;

use common::{TestResult, folder_with, poll_until_done};

/// What the fake output was asked, and what it says.
#[derive(Debug, Default)]
struct Speakers {
    playing: Option<PathBuf>,
    paused: bool,
    position: Duration,
    finished: bool,
    volume: f32,
    /// Files that fail to play.
    broken: Vec<PathBuf>,
}

#[derive(Debug, Clone, Default)]
struct Fake(Rc<RefCell<Speakers>>);

impl Output for Fake {
    fn play(&mut self, path: &Path) -> Result<(), PlayError> {
        let mut speakers = self.0.borrow_mut();
        if speakers.broken.iter().any(|broken| broken == path) {
            return Err(PlayError::Decode("not audio".into()));
        }
        speakers.playing = Some(path.to_path_buf());
        speakers.paused = false;
        speakers.position = Duration::ZERO;
        speakers.finished = false;
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
        self.0.borrow().finished
    }

    fn set_volume(&mut self, volume: f32) {
        self.0.borrow_mut().volume = volume;
    }
}

/// An engine playing through a fake output, over a.mp3, b.mp3 and c.mp3.
fn engine() -> Result<(TempDir, Engine, Fake), Box<dyn std::error::Error>> {
    let folder = folder_with(&["a.mp3", "b.mp3", "c.mp3"])?;
    let fake = Fake::default();
    let mut engine = Engine::with_output(fake.clone());
    engine.execute(Command::OpenFolder(folder.path().to_path_buf()));
    poll_until_done(&mut engine)?;
    Ok((folder, engine, fake))
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
fn a_track_plays_pauses_and_resumes() -> TestResult {
    let (_folder, mut engine, fake) = engine()?;

    engine.execute(Command::Play(1));
    assert_eq!(playing(&fake).as_deref(), Some("b.mp3"));
    assert!(engine.playback().playing());

    engine.execute(Command::PlayPause);
    assert!(fake.0.borrow().paused);
    assert!(!engine.playback().playing());

    engine.execute(Command::PlayPause);
    assert!(!fake.0.borrow().paused);
    Ok(())
}

#[test]
fn play_pause_with_nothing_playing_plays_the_focused_track() -> TestResult {
    let (_folder, mut engine, fake) = engine()?;
    engine.execute(Command::Select(2));

    engine.execute(Command::PlayPause);

    assert_eq!(playing(&fake).as_deref(), Some("c.mp3"));
    Ok(())
}

#[test]
fn the_next_track_is_the_next_the_table_lists() -> TestResult {
    let (_folder, mut engine, fake) = engine()?;
    engine.execute(Command::SortBy(SortColumn::File));
    engine.execute(Command::SortBy(SortColumn::File));
    engine.execute(Command::Play(2));

    engine.execute(Command::PlayNext);
    assert_eq!(playing(&fake).as_deref(), Some("b.mp3"));

    fake.0.borrow_mut().finished = true;
    engine.poll();
    assert_eq!(playing(&fake).as_deref(), Some("a.mp3"));

    fake.0.borrow_mut().finished = true;
    engine.poll();
    assert_eq!(playing(&fake), None);
    assert_eq!(engine.playback().track, None);
    Ok(())
}

#[test]
fn previous_starts_the_track_again_once_it_has_played_a_while() -> TestResult {
    let (_folder, mut engine, fake) = engine()?;
    engine.execute(Command::Play(1));

    engine.execute(Command::Seek(Duration::from_secs(10)));
    engine.execute(Command::PlayPrevious);
    assert_eq!(playing(&fake).as_deref(), Some("b.mp3"));
    assert_eq!(engine.position(), Duration::ZERO);

    engine.execute(Command::PlayPrevious);
    assert_eq!(playing(&fake).as_deref(), Some("a.mp3"));
    Ok(())
}

#[test]
fn a_track_that_cannot_play_is_reported() -> TestResult {
    let (folder, mut engine, fake) = engine()?;
    fake.0.borrow_mut().broken.push(folder.path().join("a.mp3"));

    engine.execute(Command::Play(0));

    assert_eq!(engine.playback().track, None);
    assert_eq!(engine.play_failure().map(|failure| failure.track), Some(0));
    Ok(())
}

#[test]
fn the_volume_reaches_the_output() -> TestResult {
    let (_folder, mut engine, fake) = engine()?;

    engine.execute(Command::SetVolume(25));
    engine.execute(Command::Play(0));

    assert!((fake.0.borrow().volume - 0.25).abs() < f32::EPSILON);
    Ok(())
}

#[test]
fn without_an_output_nothing_plays() -> TestResult {
    let folder = folder_with(&["a.mp3"])?;
    let mut engine = Engine::new();
    engine.execute(Command::OpenFolder(folder.path().to_path_buf()));
    poll_until_done(&mut engine)?;

    engine.execute(Command::Play(0));

    assert_eq!(engine.playback().track, None);
    Ok(())
}
