//! Colophon's user interface, written in Slint.

mod generated {
    // Slint's generated code unwraps internally; the lints stay on for our own code.
    #![allow(clippy::unwrap_used, clippy::expect_used)]
    slint::include_modules!();
}

pub use generated::{AppWindow, Theme};
pub use slint::{ComponentHandle, PlatformError};
