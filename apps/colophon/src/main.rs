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

    fn pick_image(&self) -> Option<PathBuf> {
        rfd::FileDialog::new()
            .add_filter("JPEG, PNG", &["jpg", "jpeg", "png"])
            .pick_file()
    }

    fn pick_save_path(&self, suggested: &str) -> Option<PathBuf> {
        rfd::FileDialog::new().set_file_name(suggested).save_file()
    }
}

fn main() -> Result<(), PlatformError> {
    // Without a sound device, Colophon still edits tags; only playing is out.
    let engine = colophon_player::Speakers::open().map_or_else(Engine::new, Engine::with_output);
    let window = colophon_ui::main_window(engine, SystemDialogs)?;
    #[cfg(target_os = "macos")]
    macos::ask_window_before_terminating(&window);
    window.run()
}
