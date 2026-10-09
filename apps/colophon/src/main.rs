use colophon_ui::{AppWindow, ComponentHandle, PlatformError};

fn main() -> Result<(), PlatformError> {
    AppWindow::new()?.run()
}
