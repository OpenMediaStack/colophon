use std::env;
use std::process::ExitCode;

const HELP: &str = "\
Colophon, the audio tag editor, on the command line.

Usage: colophon-cli [OPTIONS]

Options:
  -h, --help     Print help
  -V, --version  Print version
";

#[derive(Debug, PartialEq, Eq)]
enum Request {
    Help,
    Version,
}

fn parse(args: &[String]) -> Result<Request, String> {
    match args {
        [] => Ok(Request::Help),
        [flag] => match flag.as_str() {
            "-h" | "--help" => Ok(Request::Help),
            "-V" | "--version" => Ok(Request::Version),
            other => Err(format!("unexpected argument '{other}'")),
        },
        [_, extra, ..] => Err(format!("unexpected argument '{extra}'")),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args_os()
        .skip(1)
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect();
    match parse(&args) {
        Ok(Request::Help) => {
            print!("{HELP}");
            ExitCode::SUCCESS
        }
        Ok(Request::Version) => {
            println!("{} {}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprint!("error: {error}\n\n{HELP}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(ToString::to_string).collect()
    }

    #[test]
    fn no_argument_asks_for_help() {
        assert_eq!(parse(&[]), Ok(Request::Help));
    }

    #[test]
    fn short_and_long_flags_are_recognised() {
        assert_eq!(parse(&args(&["-h"])), Ok(Request::Help));
        assert_eq!(parse(&args(&["--help"])), Ok(Request::Help));
        assert_eq!(parse(&args(&["-V"])), Ok(Request::Version));
        assert_eq!(parse(&args(&["--version"])), Ok(Request::Version));
    }

    #[test]
    fn an_unknown_argument_is_reported() {
        assert_eq!(
            parse(&args(&["--frobnicate"])),
            Err("unexpected argument '--frobnicate'".to_string())
        );
    }

    #[test]
    fn the_first_extra_argument_is_reported() {
        assert_eq!(
            parse(&args(&["--version", "now"])),
            Err("unexpected argument 'now'".to_string())
        );
    }
}
