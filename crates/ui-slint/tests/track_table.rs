mod common;

use std::error::Error;
use std::rc::Rc;
use std::time::Duration;

use colophon_ui::{AppWindow, ComponentHandle, ScanState, Theme, TrackRow};
use slint::platform::PointerEventButton;
use slint::{LogicalPosition, ModelRc, VecModel};

use common::{TestResult, assert_matches_reference, find, shows};

/// A window in English at the given size, with an opened folder of `count` tracks.
fn window_with_tracks(count: usize, width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = AppWindow::new()?;
    common::prepare(&window, width, height)?;
    let tracks: Vec<TrackRow> = (1..=count).map(track).collect();
    window.set_tracks(ModelRc::from(Rc::new(VecModel::from(tracks))));
    window.set_folder_open(true);
    window.set_folder("~/Music".into());
    window.set_scan_state(ScanState::Completed);
    window.set_track_count(i32::try_from(count)?);
    Ok(window)
}

fn track(number: usize) -> TrackRow {
    TrackRow {
        title: format!("Track {number:05}").into(),
        file: format!("Track {number:05}.mp3").into(),
        folder: format!("Disc {}", number / 1000 + 1).into(),
    }
}

/// Lets the lists take in a scroll or a click.
fn settle() {
    i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(500));
}

#[test]
fn only_the_rows_in_view_are_created() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;

    assert!(shows(&window, "Track 00001"));
    assert!(!shows(&window, "Track 10000"));
    Ok(())
}

#[test]
fn scrolling_the_tracks_scrolls_the_pinned_titles_too() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;

    find(&window, "Tracks")?.scroll(0.0, -1_000_000.0);
    settle();

    assert!(shows(&window, "Track 10000.mp3"));
    assert!(shows(&window, "Track 10000"));
    assert!(!shows(&window, "Track 00001"));
    Ok(())
}

#[test]
fn scrolling_the_pinned_titles_scrolls_the_tracks_too() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;

    find(&window, "Track 00001")?.scroll(0.0, -1_000_000.0);
    settle();

    assert!(shows(&window, "Track 10000"));
    assert!(shows(&window, "Track 10000.mp3"));
    Ok(())
}

#[test]
fn clicking_the_middle_of_the_scroll_bar_shows_the_middle_of_the_tracks() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;

    find(&window, "Vertical scroll bar")?.mock_single_click(PointerEventButton::Left);
    settle();

    assert!(shows(&window, "Track 05000"));
    assert!(shows(&window, "Track 05000.mp3"));
    Ok(())
}

#[test]
fn fewer_tracks_show_from_the_top() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Tracks")?.scroll(0.0, -1_000_000.0);
    settle();

    let tracks: Vec<TrackRow> = (1..=10).map(track).collect();
    window.set_tracks(ModelRc::from(Rc::new(VecModel::from(tracks))));
    settle();

    assert!(shows(&window, "Track 00001"));
    assert!(shows(&window, "Track 00001.mp3"));
    Ok(())
}

#[test]
fn dragging_inside_the_table_does_not_scroll_it() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;
    let row = find(&window, "Track 00010.mp3")?;
    let before = row.absolute_position();

    row.mock_drag(
        LogicalPosition::new(before.x, before.y - 200.0),
        PointerEventButton::Left,
    );
    settle();

    assert_eq!(row.absolute_position(), before);
    Ok(())
}

#[test]
fn a_wide_window_shows_every_column() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.show()?;

    assert!(!shows(&window, "Horizontal scroll bar"));
    Ok(())
}

#[test]
fn a_narrow_window_scrolls_the_columns_sideways_but_not_the_titles() -> TestResult {
    let window = window_with_tracks(100, 960.0, 600.0)?;
    window.show()?;
    assert!(shows(&window, "Horizontal scroll bar"));
    let title = find(&window, "Title")?.absolute_position();
    let folder = find(&window, "Folder")?.absolute_position();
    let first_title = find(&window, "Track 00001")?.absolute_position();

    find(&window, "Tracks")?.scroll(-300.0, 0.0);
    settle();

    assert!(find(&window, "Folder")?.absolute_position().x < folder.x);
    assert_eq!(find(&window, "Title")?.absolute_position(), title);
    assert_eq!(
        find(&window, "Track 00001")?.absolute_position(),
        first_title
    );
    Ok(())
}

#[test]
fn the_headers_are_named_in_french_when_selected() -> TestResult {
    let window = window_with_tracks(10, 1440.0, 900.0)?;
    common::select_language("fr")?;
    window.show()?;

    assert!(shows(&window, "Titre"));
    assert!(shows(&window, "Fichier"));
    assert!(shows(&window, "Dossier"));
    Ok(())
}

#[test]
fn the_table_matches_its_references() -> TestResult {
    for (width, height, sideways) in [(1440, 900, 0.0), (960, 600, -120.0)] {
        for (dark, theme) in [(true, "dark"), (false, "light")] {
            let window = window_with_tracks(40, width as f32, height as f32)?;
            window.global::<Theme>().set_dark(dark);
            window.show()?;
            if sideways != 0.0 {
                find(&window, "Tracks")?.scroll(sideways, 0.0);
                settle();
            }
            assert_matches_reference(&window, &format!("tracks-{theme}-{width}x{height}.png"))?;
        }
    }
    Ok(())
}
