#[cfg(target_os = "macos")]
mod macos;

use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{ComponentHandle, Dialogs, PlatformError};

/// The system's file dialogs.
struct SystemDialogs;

impl Dialogs for SystemDialogs {
    fn pick_folder(&self) -> Option<PathBuf> {
        rfd::FileDialog::new().pick_folder()
    }

    fn pick_files(&self) -> Vec<PathBuf> {
        rfd::FileDialog::new()
            .add_filter("MP3", colophon_engine::AUDIO_EXTENSIONS)
            .pick_files()
            .unwrap_or_default()
    }
}

fn main() -> Result<(), PlatformError> {
    let window = colophon_ui::main_window(Engine::new(), SystemDialogs)?;
    #[cfg(target_os = "macos")]
    macos::ask_window_before_terminating(&window);
    window.run()
}
