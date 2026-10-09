use std::error::Error;
use std::process::{Command, Output};

type TestResult = Result<(), Box<dyn Error>>;

fn colophon_cli(args: &[&str]) -> std::io::Result<Output> {
    Command::new(env!("CARGO_BIN_EXE_colophon-cli"))
        .args(args)
        .output()
}

#[test]
fn version_prints_the_name_and_the_version() -> TestResult {
    let output = colophon_cli(&["--version"])?;

    assert!(output.status.success());
    assert_eq!(
        String::from_utf8(output.stdout)?,
        format!("colophon-cli {}\n", env!("CARGO_PKG_VERSION"))
    );
    Ok(())
}

#[test]
fn an_unknown_argument_fails_with_a_usage_error() -> TestResult {
    let output = colophon_cli(&["--frobnicate"])?;

    assert_eq!(output.status.code(), Some(2));
    assert!(
        String::from_utf8(output.stderr)?.starts_with("error: unexpected argument '--frobnicate'")
    );
    Ok(())
}
