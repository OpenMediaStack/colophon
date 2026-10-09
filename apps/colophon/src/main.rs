use colophon_engine::Engine;
use colophon_ui::{ComponentHandle, PlatformError};

fn main() -> Result<(), PlatformError> {
    colophon_ui::main_window(Engine::new(), || rfd::FileDialog::new().pick_folder())?.run()
}
