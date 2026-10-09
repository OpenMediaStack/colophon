// Each test file uses only part of these helpers.
#![allow(dead_code)]

use std::error::Error;
use std::path::PathBuf;

pub type TestResult = Result<(), Box<dyn Error>>;

/// A file of `testdata/`, made by `testdata/make.sh`, which documents what each one holds.
pub fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata")
        .join(name)
}

pub fn fixtures_dir() -> PathBuf {
    fixture("")
}
