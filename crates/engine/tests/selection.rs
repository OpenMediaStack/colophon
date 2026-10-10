mod common;

use colophon_engine::{Command, Engine, Step};

use common::{TestResult, folder_with, poll_until_done};

/// An engine whose library holds these files, read to the end.
fn engine_with(files: &[&str]) -> Result<Engine, Box<dyn std::error::Error>> {
    let folder = folder_with(files)?;
    let mut engine = Engine::new();
    engine.execute(Command::OpenFolder(folder.path().to_path_buf()));
    poll_until_done(&mut engine)?;
    Ok(engine)
}

fn selected(engine: &Engine) -> Vec<usize> {
    engine.selection().iter().collect()
}

#[test]
fn nothing_is_selected_at_first() -> TestResult {
    let engine = engine_with(&["a.mp3", "b.mp3"])?;

    assert!(engine.selection().is_empty());
    Ok(())
}

#[test]
fn clicks_and_keys_change_the_selection() -> TestResult {
    let mut engine = engine_with(&["a.mp3", "b.mp3", "c.mp3", "d.mp3"])?;

    engine.execute(Command::Select(1));
    engine.execute(Command::ToggleSelected(3));
    assert_eq!(selected(&engine), [1, 3]);

    engine.execute(Command::SelectRange(0));
    assert_eq!(selected(&engine), [0, 1, 2, 3]);

    engine.execute(Command::MoveSelection(Step::Down));
    engine.execute(Command::ExtendSelection(Step::Down));
    assert_eq!(selected(&engine), [1, 2]);

    engine.execute(Command::SelectAll);
    assert_eq!(selected(&engine), [0, 1, 2, 3]);
    Ok(())
}

#[test]
fn a_track_that_does_not_exist_cannot_be_selected() -> TestResult {
    let mut engine = engine_with(&["a.mp3", "b.mp3"])?;

    engine.execute(Command::Select(2));
    engine.execute(Command::ToggleSelected(7));
    engine.execute(Command::SelectRange(9));

    assert!(engine.selection().is_empty());
    Ok(())
}

#[test]
fn opening_another_folder_clears_the_selection() -> TestResult {
    let mut engine = engine_with(&["a.mp3", "b.mp3"])?;
    engine.execute(Command::SelectAll);
    let other = folder_with(&["c.mp3"])?;

    engine.execute(Command::OpenFolder(other.path().to_path_buf()));

    assert!(engine.selection().is_empty());
    assert_eq!(engine.selection().focus(), None);
    Ok(())
}
