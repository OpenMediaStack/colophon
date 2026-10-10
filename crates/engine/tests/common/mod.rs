// Each test file uses only part of these helpers.
#![allow(dead_code)]

use std::error::Error;
use std::fs;
use std::thread;
use std::time::{Duration, Instant};

use colophon_engine::{Engine, ScanStatus};
use tempfile::TempDir;

pub type TestResult = Result<(), Box<dyn Error>>;

pub fn folder_with(files: &[&str]) -> Result<TempDir, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    for file in files {
        let path = folder.path().join(file);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, b"ID3")?;
    }
    Ok(folder)
}

/// Polls the engine as the UI does, until the scan ends or a few seconds pass.
pub fn poll_until_done(engine: &mut Engine) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(5);
    while engine.library().status == ScanStatus::Scanning {
        if Instant::now() > deadline {
            return Err("the scan did not finish in time".to_string());
        }
        engine.poll();
        thread::sleep(Duration::from_millis(1));
    }
    Ok(())
}

/// A folder holding copies of fixtures of `testdata/`, each under its new name.
pub fn folder_with_fixtures(copies: &[(&str, &str)]) -> Result<TempDir, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    let fixtures = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in copies {
        fs::copy(fixtures.join(fixture), folder.path().join(name))?;
    }
    Ok(folder)
}

/// An engine that has read the whole folder.
pub fn engine_reading(folder: &TempDir) -> Result<Engine, Box<dyn Error>> {
    let mut engine = Engine::new();
    engine.execute(colophon_engine::Command::OpenFolder(
        folder.path().to_path_buf(),
    ));
    poll_until_done(&mut engine)?;
    Ok(engine)
}

/// Polls the engine as the UI does, until its save ends or a few seconds pass.
pub fn poll_until_saved(engine: &mut Engine) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(10);
    while engine.saving().is_some() {
        if Instant::now() > deadline {
            return Err("the save did not finish in time".to_string());
        }
        engine.poll();
        thread::sleep(Duration::from_millis(1));
    }
    Ok(())
}
