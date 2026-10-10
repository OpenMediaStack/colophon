#[cfg(target_os = "macos")]
mod macos;

use colophon_engine::Engine;
use colophon_ui::{ComponentHandle, PlatformError};

fn main() -> Result<(), PlatformError> {
    let window = colophon_ui::main_window(Engine::new(), || rfd::FileDialog::new().pick_folder())?;
    #[cfg(target_os = "macos")]
    macos::ask_window_before_terminating(&window);
    window.run()
}
