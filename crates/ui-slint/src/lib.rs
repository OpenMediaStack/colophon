//! Colophon's user interface, written in Slint, and its bridge to the engine.

use std::cell::RefCell;

use colophon_engine::{Engine, ViewState};

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

pub use generated::{AppWindow, Theme};
pub use slint::{ComponentHandle, PlatformError};

impl From<generated::Command> for colophon_engine::Command {
    fn from(command: generated::Command) -> Self {
        match command {
            generated::Command::ToggleSidebar => Self::ToggleSidebar,
            generated::Command::ToggleInspector => Self::ToggleInspector,
        }
    }
}

/// Creates the main window and hands its user actions to the engine, which then drives what it shows.
pub fn main_window(engine: Engine) -> Result<AppWindow, PlatformError> {
    let window = AppWindow::new()?;
    show_view(&window, engine.view());

    let engine = RefCell::new(engine);
    let weak_window = window.as_weak();
    window.on_run(move |command| {
        let mut engine = engine.borrow_mut();
        engine.execute(command.into());
        if let Some(window) = weak_window.upgrade() {
            show_view(&window, engine.view());
        }
    });

    Ok(window)
}

fn show_view(window: &AppWindow, view: &ViewState) {
    window.set_sidebar_visible(view.sidebar_visible);
    window.set_inspector_visible(view.inspector_visible);
}
