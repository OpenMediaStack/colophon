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
