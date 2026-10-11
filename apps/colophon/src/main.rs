#[cfg(target_os = "macos")]
mod macos;

use std::cell::RefCell;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process;

use colophon_engine::{Engine, Preferences};
use colophon_ui::{AppWindow, ComponentHandle, Dialogs, PlatformError};
use slint::winit_030::winit::event::WindowEvent;
use slint::winit_030::{EventResult, WinitWindowAccessor};

/// The system's file dialogs, file manager and clipboard.
#[derive(Default)]
struct SystemDialogs {
    /// On Linux, what is copied lasts only as long as the clipboard that copied it.
    clipboard: RefCell<Option<arboard::Clipboard>>,
}

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

    fn reveal(&self, path: &Path) {
        // A file manager that does not start leaves nothing to undo.
        let _ = reveal_command(path).spawn();
    }

    fn copy(&self, text: &str) {
        let mut clipboard = self.clipboard.borrow_mut();
        if clipboard.is_none() {
            *clipboard = arboard::Clipboard::new().ok();
        }
        if let Some(clipboard) = clipboard.as_mut() {
            let _ = clipboard.set_text(text);
        }
    }
}

/// Opens the system's file manager on a file: selected in the Finder and the Explorer, its
/// folder elsewhere.
fn reveal_command(path: &Path) -> process::Command {
    if cfg!(target_os = "macos") {
        let mut command = process::Command::new("open");
        command.arg("-R").arg(path);
        command
    } else if cfg!(target_os = "windows") {
        let mut select = OsString::from("/select,");
        select.push(path);
        let mut command = process::Command::new("explorer");
        command.arg(select);
        command
    } else {
        let mut command = process::Command::new("xdg-open");
        command.arg(path.parent().unwrap_or(path));
        command
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

/// Hands the files dragged from the system over the window to it, one event per file.
fn take_dropped_files(window: &AppWindow) {
    let weak = window.as_weak();
    window.window().on_winit_window_event(move |_, event| {
        let Some(window) = weak.upgrade() else {
            return EventResult::Propagate;
        };
        let path = |path: &Path| path.to_string_lossy().as_ref().into();
        match event {
            WindowEvent::HoveredFile(file) => window.invoke_file_hovered(path(file)),
            WindowEvent::HoveredFileCancelled => window.invoke_file_hover_ended(),
            WindowEvent::DroppedFile(file) => window.invoke_file_dropped(path(file)),
            _ => {}
        }
        EventResult::Propagate
    });
}

fn main() -> Result<(), PlatformError> {
    // Without a sound device, Colophon still edits tags; only playing is out.
    let mut engine =
        colophon_player::Speakers::open().map_or_else(Engine::new, Engine::with_output);
    let path = preferences_path();
    if let Some(path) = &path {
        engine.restore(recall(path));
    }
    let dialogs = SystemDialogs::default();
    let window = colophon_ui::main_window_keeping(engine, dialogs, move |preferences| {
        // Without its preferences, Colophon works the same; it only forgets them.
        if let Some(path) = &path {
            let _ = keep(path, preferences);
        }
    })?;
    take_dropped_files(&window);
    #[cfg(target_os = "macos")]
    {
        macos::show_icon();
        macos::ask_window_before_terminating(&window);
        macos::show_about_from_app_menu(&window);
    }
    window.run()
}
