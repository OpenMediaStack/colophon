mod common;

use std::error::Error;

use colophon_engine::Engine;
use colophon_ui::{AppWindow, ComponentHandle, Notice, Palette, PaletteAction, Theme};
use slint::language::ColorScheme;
use slint::platform::{Key, PointerEventButton};
use slint::{Model, ModelRc, VecModel};

use common::{TestResult, assert_matches_reference, find, press, shows};

/// A window in English with nothing open.
fn window() -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = colophon_ui::main_window(Engine::new(), || None)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    Ok(window)
}

/// Shows the window in a theme, Slint's credit included.
fn theme(window: &AppWindow, dark: bool) {
    window.global::<Theme>().set_dark(dark);
    window.global::<Palette>().set_color_scheme(if dark {
        ColorScheme::Dark
    } else {
        ColorScheme::Light
    });
}

/// A few notices that stay the same when dependencies change, for the captures.
fn notices() -> ModelRc<Notice> {
    let notice = |name: &str, version: &str, license: &str, text: &str| Notice {
        name: name.into(),
        version: version.into(),
        license: license.into(),
        source: format!("https://example.com/{name}").into(),
        text: text.into(),
    };
    ModelRc::new(VecModel::from(vec![
        notice(
            "Inter",
            "",
            "SIL Open Font License 1.1",
            "Copyright 2020 The Inter Project Authors\n\nThis Font Software is licensed under the SIL Open Font License, Version 1.1.",
        ),
        notice(
            "lofty",
            "0.25.4",
            "MIT License",
            "MIT License\n\nCopyright (c) Serial\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software.",
        ),
        notice(
            "symphonia",
            "0.5.5",
            "Mozilla Public License 2.0",
            "Mozilla Public License Version 2.0\n==================================",
        ),
    ]))
}

#[test]
fn about_tells_the_version_and_closes_with_escape() -> TestResult {
    let window = window()?;

    window.invoke_show_about();

    assert!(window.get_about_open());
    assert!(shows(
        &window,
        &format!("Version {}", env!("CARGO_PKG_VERSION"))
    ));
    press(&window, &[], Key::Escape);
    assert!(!window.get_about_open());
    Ok(())
}

#[test]
fn the_palette_opens_about() -> TestResult {
    let window = window()?;

    window.invoke_palette_chosen(PaletteAction::About);

    assert!(window.get_about_open());
    Ok(())
}

#[test]
fn about_waits_for_another_dialog() -> TestResult {
    let window = window()?;
    window.set_settings_open(true);

    window.invoke_show_about();

    assert!(!window.get_about_open());
    Ok(())
}

#[test]
fn the_licenses_list_what_colophon_ships() -> TestResult {
    let window = window()?;
    window.invoke_show_about();

    find(&window, "Third-party licenses")?.mock_single_click(PointerEventButton::Left);

    let notices = window.get_notices();
    assert!(notices.row_count() > 100);
    assert!(notices.iter().any(|notice| notice.name == "slint"));
    let second = notices.row_data(1).ok_or("no second notice")?;
    find(&window, &second.name)?.mock_single_click(PointerEventButton::Left);
    assert!(shows(
        &window,
        &format!("{} {}", second.name, second.version)
    ));
    find(&window, "Back")?.mock_single_click(PointerEventButton::Left);
    assert!(shows(&window, "Colophon"));
    Ok(())
}

#[test]
fn about_matches_its_references() -> TestResult {
    for (dark, name) in [(true, "dark"), (false, "light")] {
        let window = window()?;
        theme(&window, dark);
        window.set_version("1.0.0".into());
        window.set_notices(notices());
        window.invoke_show_about();
        assert_matches_reference(&window, &format!("about-{name}.png"))?;

        find(&window, "Third-party licenses")?.mock_single_click(PointerEventButton::Left);
        find(&window, "lofty")?.mock_single_click(PointerEventButton::Left);
        assert_matches_reference(&window, &format!("licenses-{name}.png"))?;
    }
    Ok(())
}
