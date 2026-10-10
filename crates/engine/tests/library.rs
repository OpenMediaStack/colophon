mod common;

use std::path::PathBuf;

use colophon_engine::{Command, Engine, ScanStatus};

use common::{TestResult, folder_with, poll_until_done};

fn file_names(engine: &Engine) -> Vec<String> {
    engine
        .library()
        .tracks
        .iter()
        .filter_map(|track| track.path.file_name())
        .map(|name| name.to_string_lossy().into_owned())
        .collect()
}

#[test]
fn nothing_is_open_at_start() {
    let engine = Engine::new();

    assert!(engine.library().roots.is_empty());
    assert!(engine.library().tracks.is_empty());
    assert_eq!(engine.library().status, ScanStatus::Idle);
}

#[test]
fn opening_a_folder_lists_its_mp3_files() -> TestResult {
    let folder = folder_with(&["a.mp3", "Album/b.mp3", "cover.jpg"])?;
    let mut engine = Engine::new();

    engine.execute(Command::OpenFolder(folder.path().to_path_buf()));
    assert_eq!(engine.library().status, ScanStatus::Scanning);
    poll_until_done(&mut engine)?;

    assert_eq!(engine.library().roots, [folder.path()]);
    assert_eq!(file_names(&engine), ["b.mp3", "a.mp3"]);
    assert_eq!(engine.library().status, ScanStatus::Completed);
    Ok(())
}

#[test]
fn opening_another_folder_adds_its_tracks() -> TestResult {
    let first = folder_with(&["first.mp3"])?;
    let second = folder_with(&["second.mp3"])?;
    let mut engine = Engine::new();

    engine.execute(Command::OpenFolder(first.path().to_path_buf()));
    poll_until_done(&mut engine)?;
    engine.execute(Command::OpenFolder(second.path().to_path_buf()));
    poll_until_done(&mut engine)?;

    assert_eq!(file_names(&engine), ["first.mp3", "second.mp3"]);
    assert_eq!(engine.library().roots.len(), 2);
    Ok(())
}

#[test]
fn two_folders_opened_at_once_are_both_read() -> TestResult {
    let first = folder_with(&["first.mp3"])?;
    let second = folder_with(&["second.mp3"])?;
    let mut engine = Engine::new();

    engine.execute(Command::OpenFolder(first.path().to_path_buf()));
    engine.execute(Command::OpenFolder(second.path().to_path_buf()));
    poll_until_done(&mut engine)?;

    let mut names = file_names(&engine);
    names.sort();
    assert_eq!(names, ["first.mp3", "second.mp3"]);
    assert_eq!(engine.library().status, ScanStatus::Completed);
    Ok(())
}

#[test]
fn opening_a_folder_again_lists_its_tracks_once() -> TestResult {
    let folder = folder_with(&["a.mp3", "Album/b.mp3"])?;
    let mut engine = Engine::new();

    engine.execute(Command::OpenFolder(folder.path().join("Album")));
    poll_until_done(&mut engine)?;
    engine.execute(Command::OpenFolder(folder.path().to_path_buf()));
    poll_until_done(&mut engine)?;

    assert_eq!(file_names(&engine), ["b.mp3", "a.mp3"]);
    assert_eq!(engine.library().roots, [folder.path()]);
    Ok(())
}

#[test]
fn opening_files_lists_them_and_their_folders() -> TestResult {
    let folder = folder_with(&["One/a.mp3", "One/b.mp3", "Two/c.mp3"])?;
    let mut engine = Engine::new();

    engine.execute(Command::OpenFiles(vec![
        folder.path().join("One/a.mp3"),
        folder.path().join("Two/c.mp3"),
    ]));
    poll_until_done(&mut engine)?;

    assert_eq!(file_names(&engine), ["a.mp3", "c.mp3"]);
    assert_eq!(
        engine.library().roots,
        [folder.path().join("One"), folder.path().join("Two")]
    );
    Ok(())
}

#[test]
fn stopping_the_scan_ends_it_at_once() -> TestResult {
    let folder = folder_with(&["a.mp3"])?;
    let mut engine = Engine::new();

    engine.execute(Command::OpenFolder(folder.path().to_path_buf()));
    engine.execute(Command::StopScan);

    assert_eq!(engine.library().status, ScanStatus::Stopped);
    assert!(!engine.poll(), "nothing arrives once the scan is stopped");
    Ok(())
}

#[test]
fn stopping_without_a_scan_changes_nothing() {
    let mut engine = Engine::new();

    engine.execute(Command::StopScan);

    assert_eq!(engine.library().status, ScanStatus::Idle);
}

#[test]
fn a_missing_folder_is_reported_as_unreadable() -> TestResult {
    let mut engine = Engine::new();

    engine.execute(Command::OpenFolder(PathBuf::from(
        "/this/folder/does/not/exist",
    )));
    poll_until_done(&mut engine)?;

    assert!(engine.library().tracks.is_empty());
    assert_eq!(engine.library().unreadable.len(), 1);
    assert_eq!(engine.library().status, ScanStatus::Completed);
    Ok(())
}

#[test]
fn polling_without_a_scan_reports_no_change() {
    let mut engine = Engine::new();

    assert!(!engine.poll());
}
