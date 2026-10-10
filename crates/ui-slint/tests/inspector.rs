mod common;

use std::error::Error;
use std::fs;
use std::path::PathBuf;

use colophon_engine::Engine;
use colophon_ui::{
    AppWindow, BitrateMode, ByteSize, ComponentHandle, InspectedTracks, InspectorField,
    InspectorState, ReadProblem, ScanState, SizeUnit, Theme, UnreadableFile,
};
use slint::platform::{Key, PointerEventButton};
use tempfile::TempDir;

use common::{TestResult, assert_matches_reference, find, shows};

/// The main window in English, showing these fixtures under these names, in this order.
fn window_with(copies: &[(&str, &str)]) -> Result<(AppWindow, TempDir), Box<dyn Error>> {
    common::use_testing_backend()?;
    let folder = tempfile::tempdir()?;
    let fixtures = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata");
    for (fixture, name) in copies {
        fs::copy(fixtures.join(fixture), folder.path().join(name))?;
    }
    let path = folder.path().to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    let tracks = if copies.len() == 1 {
        "1 track".to_string()
    } else {
        format!("{} tracks", copies.len())
    };
    common::wait_until_shown(&window, &tracks)?;
    Ok((window, folder))
}

#[test]
fn the_inspector_is_empty_until_a_folder_opens() -> TestResult {
    common::use_testing_backend()?;
    let window = colophon_ui::main_window(Engine::new(), || None)?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.show()?;

    assert!(shows(&window, "Inspector"));
    assert!(!shows(&window, "Select tracks to see their tags"));
    Ok(())
}

#[test]
fn the_inspector_asks_for_a_selection() -> TestResult {
    let (window, _folder) = window_with(&[("v23_full.mp3", "1.mp3")])?;

    assert!(shows(&window, "Select tracks to see their tags"));
    assert!(shows(&window, "⌘A selects every track"));
    Ok(())
}

#[test]
fn one_track_shows_its_tags_and_its_file() -> TestResult {
    let (window, _folder) = window_with(&[("v23_full.mp3", "1.mp3")])?;

    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);

    for value in [
        "Small Hours · Marlowe Kite",
        "MP3 · 64\u{a0}kbps\u{a0}CBR · 44.1\u{a0}kHz",
        "1\u{a0}KB",
        "ID3v2.3",
    ] {
        assert!(shows(&window, value), "{value} is missing");
    }
    for (field, value) in [
        ("Album artist", "Various Artists"),
        ("Year", "2019"),
        ("Track", "3"),
        ("Track total", "12"),
        ("Comment", "Recorded in one take."),
    ] {
        let shown = common::input(&window, field)?.accessible_value();
        assert_eq!(shown.as_deref(), Some(value), "{field}");
    }
    Ok(())
}

#[test]
fn several_tracks_show_what_they_share() -> TestResult {
    let (window, _folder) =
        window_with(&[("v23_full.mp3", "1.mp3"), ("v24_unicode.mp3", "2.mp3")])?;

    common::press(&window, &[Key::Control], "a");

    assert!(shows(&window, "2 tracks selected"));
    assert!(shows(&window, "Multiple values"));
    assert!(shows(&window, "2\u{a0}KB total"));
    Ok(())
}

#[test]
fn an_unreadable_track_explains_why() -> TestResult {
    let (window, _folder) = window_with(&[("tiny_tag.mp3", "broken.mp3")])?;

    find(&window, "broken")?.mock_single_click(PointerEventButton::Left);

    assert!(shows(&window, "Could not read this file"));
    assert!(shows(
        &window,
        "This file is damaged, or it is not an MP3: Colophon could not make sense of it."
    ));
    assert!(shows(&window, "3\u{a0}bytes"));
    Ok(())
}

#[test]
fn the_inspector_writes_numbers_in_french() -> TestResult {
    let (window, _folder) = window_with(&[("v23_full.mp3", "1.mp3")])?;
    common::select_language("fr")?;

    find(&window, "Marlowe Kite")?.mock_single_click(PointerEventButton::Left);

    assert!(shows(
        &window,
        "MP3 · 64\u{a0}kbit/s\u{a0}CBR · 44,1\u{a0}kHz"
    ));
    assert!(shows(&window, "1\u{a0}Ko"));
    Ok(())
}

fn text(value: &str) -> InspectorField {
    InspectorField {
        text: value.into(),
        ..InspectorField::default()
    }
}

fn modified(value: &str) -> InspectorField {
    InspectorField {
        modified: true,
        ..text(value)
    }
}

fn mixed() -> InspectorField {
    InspectorField {
        mixed: true,
        ..InspectorField::default()
    }
}

/// A window with an opened folder, showing these inspected tracks or this unreadable file.
fn window_inspecting(
    state: InspectorState,
    tracks: InspectedTracks,
    unreadable: UnreadableFile,
) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = AppWindow::new()?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.set_folder_open(true);
    window.set_folder("~/Music".into());
    window.set_scan_state(ScanState::Completed);
    window.set_inspector_state(state);
    window.set_inspected_tracks(tracks);
    window.set_unreadable_file(unreadable);
    Ok(window)
}

#[test]
fn the_inspector_matches_its_references() -> TestResult {
    let tracks = InspectedTracks {
        count: 3,
        title: mixed(),
        artist: text("Cassette Bloom"),
        album_artist: text("Cassette Bloom"),
        album: text("Analog Hearts"),
        year: modified("2024"),
        track: mixed(),
        track_total: text("8"),
        genre: modified("Synthwave"),
        comment: text("Remastered from the original tapes, 2025 reissue."),
        audio_shared: true,
        bitrate: 320,
        bitrate_mode: BitrateMode::Constant,
        sample_rate_whole: 44,
        sample_rate_tenth: 1,
        formats: text("ID3v2.3, ID3v1.1"),
        size: ByteSize {
            whole: 25,
            tenth: 4,
            unit: SizeUnit::Megabytes,
        },
        ..InspectedTracks::default()
    };
    let unreadable = UnreadableFile {
        path: "~/Music/Marlowe Kite/Small Hours/track07.mp3".into(),
        problem: ReadProblem::Damaged,
        size: ByteSize {
            whole: 1,
            tenth: 0,
            unit: SizeUnit::Kilobytes,
        },
    };
    for (state, name) in [
        (InspectorState::Tracks, "tracks"),
        (InspectorState::Unreadable, "unreadable"),
    ] {
        for (dark, theme) in [(true, "dark"), (false, "light")] {
            let window = window_inspecting(state, tracks.clone(), unreadable.clone())?;
            window.global::<Theme>().set_dark(dark);
            window.show()?;
            assert_matches_reference(&window, &format!("inspector-{name}-{theme}.png"))?;
        }
    }
    Ok(())
}
