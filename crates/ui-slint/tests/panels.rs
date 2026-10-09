mod common;

use std::error::Error;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle};
use slint::platform::{Key, PointerEventButton, WindowEvent};

use common::{TestResult, find, shows};

/// The main window, driven by a fresh engine, shown in English at 1440 by 900.
fn open_main_window() -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = colophon_ui::main_window(Engine::new(), || None)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    Ok(window)
}

/// Presses the keys in order, then releases them in reverse, as a person types a shortcut.
fn press_shortcut(window: &AppWindow, keys: &[slint::SharedString]) {
    for key in keys {
        window
            .window()
            .dispatch_event(WindowEvent::KeyPressed { text: key.clone() });
    }
    for key in keys.iter().rev() {
        window
            .window()
            .dispatch_event(WindowEvent::KeyReleased { text: key.clone() });
    }
}

#[test]
fn the_toolbar_button_hides_and_shows_the_sidebar() -> TestResult {
    let window = open_main_window()?;
    let toggle = find(&window, "Toggle sidebar")?;
    assert_eq!(toggle.accessible_checked(), Some(true));

    toggle.invoke_accessible_default_action();
    assert!(!shows(&window, "Sidebar"));
    assert_eq!(toggle.accessible_checked(), Some(false));

    toggle.invoke_accessible_default_action();
    assert!(shows(&window, "Sidebar"));
    Ok(())
}

#[test]
fn the_toolbar_button_hides_the_inspector() -> TestResult {
    let window = open_main_window()?;

    find(&window, "Toggle inspector")?.invoke_accessible_default_action();

    assert!(!shows(&window, "Inspector"));
    assert!(shows(&window, "Sidebar"));
    Ok(())
}

#[test]
fn the_view_menu_hides_the_sidebar_and_then_offers_to_show_it() -> TestResult {
    let window = open_main_window()?;

    find(&window, "View")?.mock_single_click(PointerEventButton::Left);
    find(&window, "Hide Sidebar")?.mock_single_click(PointerEventButton::Left);
    assert!(!shows(&window, "Sidebar"));

    find(&window, "View")?.mock_single_click(PointerEventButton::Left);
    assert!(shows(&window, "Show Sidebar"));
    Ok(())
}

#[test]
fn the_inspector_shortcut_toggles_the_inspector() -> TestResult {
    let window = open_main_window()?;

    press_shortcut(&window, &[Key::Control.into(), Key::Alt.into(), "i".into()]);
    assert!(!shows(&window, "Inspector"));

    press_shortcut(&window, &[Key::Control.into(), Key::Alt.into(), "i".into()]);
    assert!(shows(&window, "Inspector"));
    Ok(())
}

#[test]
fn the_sidebar_shortcut_toggles_the_sidebar() -> TestResult {
    let window = open_main_window()?;

    press_shortcut(&window, &[Key::Control.into(), Key::Alt.into(), "s".into()]);

    assert!(!shows(&window, "Sidebar"));
    Ok(())
}
