mod common;

use std::error::Error;
use std::rc::Rc;
use std::time::Duration;

use colophon_ui::{
    AppWindow, ComponentHandle, ScanState, Theme, TrackColumns, TrackRow, TrackStatus,
};
use slint::platform::PointerEventButton;
use slint::{LogicalPosition, ModelRc, VecModel};

use common::{TestResult, assert_matches_reference, find, shows};

/// A window in English at the given size, with an opened folder of these tracks.
fn window_with(rows: Vec<TrackRow>, width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = AppWindow::new()?;
    common::prepare(&window, width, height)?;
    window.set_track_count(i32::try_from(rows.len())?);
    window.set_tracks(ModelRc::from(Rc::new(VecModel::from(rows))));
    window.set_folder_open(true);
    window.set_folder("~/Music".into());
    window.set_scan_state(ScanState::Completed);
    Ok(window)
}

fn window_with_tracks(count: usize, width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
    window_with(tracks(count), width, height)
}

/// Albums of twelve tracks, whose artist names the track, so that each side of a row can be found.
fn tracks(count: usize) -> Vec<TrackRow> {
    (1..=count)
        .map(|number| TrackRow {
            number: format!("{:02}", (number - 1) % 12 + 1).into(),
            title: format!("Track {number:05}").into(),
            artist: format!("Artist {number:05}").into(),
            album: format!("Album {}", (number - 1) / 12 + 1).into(),
            year: "2019".into(),
            genre: "Folk".into(),
            time: "3:41".into(),
            bitrate: "320".into(),
            tags: "ID3v2.3, ID3v1.1".into(),
            file: format!("Track {number:05}.mp3").into(),
            folder: format!("Disc {}", number / 1000 + 1).into(),
            ..TrackRow::default()
        })
        .collect()
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

    assert!(shows(&window, "Artist 10000"));
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
    assert!(shows(&window, "Artist 10000"));
    Ok(())
}

#[test]
fn clicking_the_middle_of_the_scroll_bar_shows_the_middle_of_the_tracks() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;

    find(&window, "Vertical scroll bar")?.mock_single_click(PointerEventButton::Left);
    settle();

    assert!(shows(&window, "Track 05000"));
    assert!(shows(&window, "Artist 05000"));
    Ok(())
}

#[test]
fn fewer_tracks_show_from_the_top() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;
    find(&window, "Tracks")?.scroll(0.0, -1_000_000.0);
    settle();

    window.set_tracks(ModelRc::from(Rc::new(VecModel::from(tracks(10)))));
    settle();

    assert!(shows(&window, "Track 00001"));
    assert!(shows(&window, "Artist 00001"));
    Ok(())
}

#[test]
fn dragging_inside_the_table_does_not_scroll_it() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;
    let row = find(&window, "Artist 00010")?;
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
fn a_wide_window_shows_the_default_columns_without_scrolling() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.show()?;

    for value in [
        "03",
        "Track 00003",
        "Artist 00003",
        "Album 1",
        "2019",
        "Folk",
        "3:41",
        "320",
    ] {
        assert!(shows(&window, value), "{value} is missing");
    }
    assert!(!shows(&window, "Horizontal scroll bar"));
    Ok(())
}

#[test]
fn the_tags_file_and_folder_columns_are_hidden_by_default() -> TestResult {
    let window = window_with_tracks(10, 1440.0, 900.0)?;
    window.show()?;

    assert!(!shows(&window, "ID3v2.3, ID3v1.1"));
    assert!(!shows(&window, "Track 00001.mp3"));
    assert!(!shows(&window, "Disc 1"));
    Ok(())
}

#[test]
fn hidden_columns_show_once_chosen() -> TestResult {
    let window = window_with_tracks(10, 1440.0, 900.0)?;
    window.set_columns(TrackColumns {
        tags: true,
        file: true,
        folder: true,
        ..TrackColumns::default()
    });
    window.show()?;

    assert!(shows(&window, "ID3v2.3, ID3v1.1"));
    assert!(shows(&window, "Track 00001.mp3"));
    assert!(shows(&window, "Disc 1"));
    assert!(!shows(&window, "Artist 00001"));
    Ok(())
}

#[test]
fn an_unreadable_track_is_marked() -> TestResult {
    let mut rows = tracks(3);
    rows[1] = TrackRow {
        status: TrackStatus::Unreadable,
        title: "broken".into(),
        ..TrackRow::default()
    };
    let window = window_with(rows, 1440.0, 900.0)?;
    window.show()?;

    assert!(shows(&window, "Unreadable"));
    assert!(shows(&window, "broken"));
    Ok(())
}

#[test]
fn a_narrow_window_scrolls_the_columns_sideways_but_not_the_titles() -> TestResult {
    let window = window_with_tracks(100, 960.0, 600.0)?;
    window.show()?;
    assert!(shows(&window, "Horizontal scroll bar"));
    let title = find(&window, "Title")?.absolute_position();
    let album = find(&window, "Album")?.absolute_position();
    let first_title = find(&window, "Track 00001")?.absolute_position();

    find(&window, "Tracks")?.scroll(-100.0, 0.0);
    settle();

    assert!(find(&window, "Album")?.absolute_position().x < album.x);
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

    for header in ["Titre", "Artiste", "Année", "Durée", "Débit"] {
        assert!(shows(&window, header), "{header} is missing");
    }
    Ok(())
}

#[test]
fn the_table_matches_its_references() -> TestResult {
    for (width, height, sideways) in [(1440, 900, 0.0), (960, 600, -120.0)] {
        for (dark, theme) in [(true, "dark"), (false, "light")] {
            let mut rows = tracks(40);
            rows[3].title = "04 Track without a title tag".into();
            rows[3].untitled = true;
            rows[5] = TrackRow {
                status: TrackStatus::Unreadable,
                title: "06 Damaged file".into(),
                ..TrackRow::default()
            };
            let window = window_with(rows, width as f32, height as f32)?;
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
