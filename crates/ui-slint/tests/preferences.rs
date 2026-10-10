mod common;

use std::cell::RefCell;
use std::error::Error;
use std::rc::Rc;

use colophon_engine::{Engine, Preferences, ViewState, WindowSize};
use colophon_ui::{AppWindow, ComponentHandle, WindowCommand};

use common::TestResult;

type Kept = Rc<RefCell<Vec<Preferences>>>;

/// The main window at 1280 by 720, from `engine`, and the preferences it hands over.
fn window_keeping(engine: Engine) -> Result<(AppWindow, Kept), Box<dyn Error>> {
    common::use_testing_backend()?;
    let kept = Kept::default();
    let window = colophon_ui::main_window_keeping(engine, || None, {
        let kept = Rc::clone(&kept);
        move |preferences: &Preferences| kept.borrow_mut().push(*preferences)
    })?;
    common::prepare(&window, 1280.0, 720.0)?;
    window.show()?;
    Ok((window, kept))
}

#[test]
fn a_change_of_the_preferences_is_kept() -> TestResult {
    let (window, kept) = window_keeping(Engine::new())?;
    assert!(kept.borrow().is_empty());

    window.invoke_run(WindowCommand::ToggleSidebar);

    let last = kept.borrow().last().copied().ok_or("nothing kept")?;
    assert!(!last.view.sidebar_visible);
    Ok(())
}

#[test]
fn closing_the_window_keeps_its_size() -> TestResult {
    let (window, kept) = window_keeping(Engine::new())?;

    assert!(colophon_ui::request_close(&window));

    let last = kept.borrow().last().copied().ok_or("nothing kept")?;
    assert_eq!(
        last.view.window_size,
        Some(WindowSize {
            width: 1280,
            height: 720,
        })
    );
    Ok(())
}

#[test]
fn the_window_opens_at_the_size_it_had() -> TestResult {
    common::use_testing_backend()?;
    let mut engine = Engine::new();
    engine.restore(Preferences {
        view: ViewState {
            window_size: Some(WindowSize {
                width: 1100,
                height: 700,
            }),
            ..ViewState::default()
        },
        ..Preferences::default()
    });

    let window = colophon_ui::main_window(engine, || None)?;

    let window = window.window();
    let size = window.size().to_logical(window.scale_factor());
    assert_eq!((size.width, size.height), (1100.0, 700.0));
    Ok(())
}
