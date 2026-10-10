#[cfg(target_os = "macos")]
mod macos;

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use colophon_engine::{Engine, Preferences};
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

/// Where Colophon keeps its preferences, in the system's folder for application settings.
fn preferences_path() -> Option<PathBuf> {
    let folder = if cfg!(target_os = "linux") {
        "colophon"
    } else {
        "Colophon"
    };
    Some(dirs::config_dir()?.join(folder).join("preferences.toml"))
}

fn recall(path: &Path) -> Preferences {
    fs::read_to_string(path).map_or_else(
        |_| Preferences::default(),
        |text| Preferences::from_toml(&text),
    )
}

/// Writes the preferences next to their file, then moves them over it, so that quitting
/// halfway never leaves half a file.
fn keep(path: &Path, preferences: &Preferences) -> io::Result<()> {
    if let Some(folder) = path.parent() {
        fs::create_dir_all(folder)?;
    }
    let written = path.with_extension("toml.new");
    fs::write(&written, preferences.to_toml())?;
    fs::rename(&written, path)
}

fn main() -> Result<(), PlatformError> {
    // Without a sound device, Colophon still edits tags; only playing is out.
    let mut engine =
        colophon_player::Speakers::open().map_or_else(Engine::new, Engine::with_output);
    let path = preferences_path();
    if let Some(path) = &path {
        engine.restore(recall(path));
    }
    let window = colophon_ui::main_window_keeping(engine, SystemDialogs, move |preferences| {
        // Without its preferences, Colophon works the same; it only forgets them.
        if let Some(path) = &path {
            let _ = keep(path, preferences);
        }
    })?;
    #[cfg(target_os = "macos")]
    macos::ask_window_before_terminating(&window);
    window.run()
}
