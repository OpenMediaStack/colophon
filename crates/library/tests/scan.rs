use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use colophon_library::tags::ReadError;
use colophon_library::{AUDIO_EXTENSIONS, ScanEvent, ScanOutcome, Track, scan, spawn_scan};
use tempfile::TempDir;

type TestResult = Result<(), Box<dyn Error>>;

/// A temporary folder holding the given files, each with a few bytes so that sizes differ.
fn folder_with(files: &[&str]) -> Result<TempDir, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    for (index, file) in files.iter().enumerate() {
        let path = folder.path().join(file);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, vec![0_u8; index + 1])?;
    }
    Ok(folder)
}

/// A file of `testdata/`, made by `testdata/make.sh`.
fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata")
        .join(name)
}

/// Runs a scan to the end and returns its events.
fn scan_all(root: &Path) -> Vec<ScanEvent> {
    let mut events = Vec::new();
    scan(root, AUDIO_EXTENSIONS, &AtomicBool::new(false), |event| {
        events.push(event)
    });
    events
}

fn found(events: &[ScanEvent]) -> Vec<&Track> {
    events
        .iter()
        .filter_map(|event| match event {
            ScanEvent::Found(track) => Some(track.as_ref()),
            _ => None,
        })
        .collect()
}

fn relative_paths(root: &Path, events: &[ScanEvent]) -> Vec<PathBuf> {
    found(events)
        .into_iter()
        .filter_map(|track| track.path.strip_prefix(root).ok().map(Path::to_path_buf))
        .collect()
}

fn outcome(events: &[ScanEvent]) -> Option<ScanOutcome> {
    match events.last() {
        Some(ScanEvent::Finished(outcome)) => Some(*outcome),
        _ => None,
    }
}

#[test]
fn finds_mp3_files_in_subfolders_sorted_by_name() -> TestResult {
    let folder = folder_with(&["b.mp3", "a.mp3", "Album/02.mp3", "Album/01.mp3"])?;

    let events = scan_all(folder.path());

    assert_eq!(
        relative_paths(folder.path(), &events),
        ["Album/01.mp3", "Album/02.mp3", "a.mp3", "b.mp3"].map(PathBuf::from)
    );
    assert_eq!(outcome(&events), Some(ScanOutcome::Completed));
    Ok(())
}

#[test]
fn matches_the_extension_whatever_its_case() -> TestResult {
    let folder = folder_with(&["loud.MP3", "mixed.Mp3"])?;

    let events = scan_all(folder.path());

    assert_eq!(found(&events).len(), 2);
    Ok(())
}

#[test]
fn ignores_other_formats_and_hidden_entries() -> TestResult {
    let folder = folder_with(&[
        "song.mp3",
        "cover.jpg",
        "notes.txt",
        "song.flac",
        ".DS_Store",
        "._song.mp3",
        ".Trashes/deleted.mp3",
    ])?;

    let events = scan_all(folder.path());

    assert_eq!(
        relative_paths(folder.path(), &events),
        [PathBuf::from("song.mp3")]
    );
    Ok(())
}

#[test]
fn reports_the_size_and_the_modification_date() -> TestResult {
    let folder = folder_with(&["first.mp3", "second.mp3"])?;

    let events = scan_all(folder.path());
    let tracks = found(&events);

    assert_eq!(
        tracks.iter().map(|track| track.size).collect::<Vec<_>>(),
        [1, 2]
    );
    assert!(tracks.iter().all(|track| track.modified.is_some()));
    Ok(())
}

#[test]
fn stops_when_asked() -> TestResult {
    let folder = folder_with(&["1.mp3", "2.mp3", "3.mp3"])?;
    let stop = AtomicBool::new(false);
    let mut events = Vec::new();

    scan(folder.path(), AUDIO_EXTENSIONS, &stop, |event| {
        if matches!(event, ScanEvent::Found(_)) {
            stop.store(true, Ordering::Relaxed);
        }
        events.push(event);
    });

    assert_eq!(found(&events).len(), 1);
    assert_eq!(outcome(&events), Some(ScanOutcome::Stopped));
    Ok(())
}

#[test]
fn reports_a_missing_folder_and_still_finishes() {
    let events = scan_all(Path::new("/this/folder/does/not/exist"));

    assert!(matches!(events.first(), Some(ScanEvent::Unreadable(_))));
    assert_eq!(outcome(&events), Some(ScanOutcome::Completed));
}

#[cfg(unix)]
#[test]
fn skips_an_unreadable_folder_and_reads_the_others() -> TestResult {
    use std::os::unix::fs::PermissionsExt;

    let folder = folder_with(&["Locked/hidden.mp3", "Open/visible.mp3"])?;
    let locked = folder.path().join("Locked");
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o000))?;

    let events = scan_all(folder.path());
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755))?;

    assert_eq!(
        relative_paths(folder.path(), &events),
        [PathBuf::from("Open/visible.mp3")]
    );
    assert!(events.iter().any(|event| matches!(
        event,
        ScanEvent::Unreadable(error) if error.path == locked
    )));
    assert_eq!(outcome(&events), Some(ScanOutcome::Completed));
    Ok(())
}

#[test]
fn a_spawned_scan_reports_through_its_channel() -> TestResult {
    let folder = folder_with(&["a.mp3", "b.mp3"])?;

    let handle = spawn_scan(folder.path().to_path_buf(), AUDIO_EXTENSIONS)?;
    let events: Vec<ScanEvent> = handle.events().iter().collect();

    assert_eq!(found(&events).len(), 2);
    assert_eq!(outcome(&events), Some(ScanOutcome::Completed));
    Ok(())
}

#[test]
fn a_found_file_carries_its_tags() -> TestResult {
    let folder = tempfile::tempdir()?;
    fs::copy(fixture("v23_full.mp3"), folder.path().join("track.mp3"))?;

    let events = scan_all(folder.path());

    let tracks = found(&events);
    let metadata = tracks
        .first()
        .ok_or("no track found")?
        .metadata
        .as_ref()
        .map_err(ToString::to_string)?;
    assert_eq!(metadata.tags.title.as_deref(), Some("Paper Satellites"));
    assert_eq!(metadata.audio.sample_rate, Some(44_100));
    Ok(())
}

#[test]
fn a_file_whose_tags_cannot_be_read_is_found_all_the_same() -> TestResult {
    let folder = folder_with(&["broken.mp3"])?;

    let events = scan_all(folder.path());

    let tracks = found(&events);
    assert_eq!(tracks.len(), 1);
    assert!(
        matches!(tracks[0].metadata, Err(ReadError::Damaged(_))),
        "{:?}",
        tracks[0].metadata
    );
    Ok(())
}
