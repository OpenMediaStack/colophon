mod common;

use std::cell::RefCell;
use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle, Dialogs};
use slint::platform::PointerEventButton;
use tempfile::TempDir;

use common::{TestResult, find};

/// What the window asked of the desktop.
#[derive(Debug, Default)]
struct Asked {
    revealed: Vec<PathBuf>,
    copied: Vec<String>,
}

type SharedAsked = Rc<RefCell<Asked>>;

/// A desktop that opens a folder and remembers what it was asked.
struct Desktop {
    folder: PathBuf,
    asked: SharedAsked,
}

impl Dialogs for Desktop {
    fn pick_folder(&self) -> Option<PathBuf> {
        Some(self.folder.clone())
    }

    fn reveal(&self, path: &Path) {
        self.asked.borrow_mut().revealed.push(path.to_path_buf());
    }

    fn copy(&self, text: &str) {
        self.asked.borrow_mut().copied.push(text.to_owned());
    }
}

/// The main window in English with one file that only starts like an MP3, selected.
fn window_with_an_unreadable_file() -> Result<(AppWindow, TempDir, SharedAsked), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    fs::write(folder.path().join("track07.mp3"), b"ID3")?;
    let asked = SharedAsked::default();
    let desktop = Desktop {
        folder: folder.path().to_path_buf(),
        asked: Rc::clone(&asked),
    };
    let window = colophon_ui::main_window(Engine::new(), desktop)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "1 track")?;
    find(&window, "track07")?.mock_single_click(PointerEventButton::Left);
    Ok((window, folder, asked))
}

#[test]
fn an_unreadable_file_shows_in_the_file_manager() -> TestResult {
    let (window, folder, asked) = window_with_an_unreadable_file()?;

    find(&window, "Show in Finder")?.invoke_accessible_default_action();

    assert_eq!(asked.borrow().revealed, [folder.path().join("track07.mp3")]);
    Ok(())
}

#[test]
fn the_details_of_an_unreadable_file_go_to_the_clipboard() -> TestResult {
    let (window, folder, asked) = window_with_an_unreadable_file()?;

    find(&window, "Copy details")?.invoke_accessible_default_action();

    let copied = asked.borrow().copied.concat();
    let path = folder.path().join("track07.mp3");
    assert!(
        copied.contains(&format!("File: {}", path.display())),
        "{copied}"
    );
    assert!(copied.contains("Size: 3 bytes"), "{copied}");
    assert!(copied.contains("Error: "), "{copied}");
    Ok(())
}
