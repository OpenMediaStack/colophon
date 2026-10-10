mod common;

use std::cell::RefCell;
use std::error::Error;
use std::rc::Rc;
use std::time::Duration;

use colophon_ui::{
    AppWindow, ComponentHandle, ScanState, Theme, TrackColumnWidths, TrackColumns, TrackRow,
    TrackStatus, WindowCommand,
};
use slint::platform::{Key, PointerEventButton, WindowEvent};
use slint::{LogicalPosition, ModelRc, VecModel};

use common::{TestResult, assert_matches_reference, find, resize_handle, shows};

/// A window in English at the given size, with an opened folder of these tracks.
fn window_with(rows: Vec<TrackRow>, width: f32, height: f32) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let window = AppWindow::new()?;
    common::prepare(&window, width, height)?;
    window.set_track_count(i32::try_from(rows.len())?);
    window.set_tracks(ModelRc::from(Rc::new(VecModel::from(rows))));
    window.set_folder_open(true);
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
fn scrolling_down_shows_the_last_tracks() -> TestResult {
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
    ] {
        assert!(shows(&window, value), "{value} is missing");
    }
    assert!(!shows(&window, "Horizontal scroll bar"));
    Ok(())
}

#[test]
fn the_bitrate_tags_file_and_folder_columns_are_hidden_by_default() -> TestResult {
    let window = window_with_tracks(10, 1440.0, 900.0)?;
    window.show()?;

    assert!(!shows(&window, "Bitrate"));
    assert!(!shows(&window, "ID3v2.3, ID3v1.1"));
    assert!(!shows(&window, "Track 00001.mp3"));
    assert!(!shows(&window, "Disc 1"));
    Ok(())
}

#[test]
fn hidden_columns_show_once_chosen() -> TestResult {
    let window = window_with_tracks(10, 1440.0, 900.0)?;
    window.set_columns(TrackColumns {
        bitrate: true,
        tags: true,
        file: true,
        folder: true,
        ..TrackColumns::default()
    });
    window.show()?;

    assert!(shows(&window, "320"));
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
fn a_narrow_window_scrolls_every_column_sideways() -> TestResult {
    let window = window_with_tracks(100, 960.0, 600.0)?;
    window.show()?;
    assert!(shows(&window, "Horizontal scroll bar"));
    let title = find(&window, "Title")?.absolute_position();
    let album = find(&window, "Album")?.absolute_position();
    let first_title = find(&window, "Track 00001")?.absolute_position();

    find(&window, "Tracks")?.scroll(-100.0, 0.0);
    settle();

    for (name, before) in [
        ("Title", title),
        ("Album", album),
        ("Track 00001", first_title),
    ] {
        let after = find(&window, name)?.absolute_position();
        assert!(
            (after.x - (before.x - 100.0)).abs() < 1.0,
            "{name} at {after:?}"
        );
    }
    Ok(())
}

/// The widths the table asks for, as the engine would receive them.
fn record_resizes(window: &AppWindow) -> Rc<RefCell<Option<TrackColumnWidths>>> {
    let asked = Rc::new(RefCell::new(None));
    window.on_resize_columns({
        let asked = Rc::clone(&asked);
        move |widths| *asked.borrow_mut() = Some(widths)
    });
    asked
}

/// The width of a column, from its name: the cell is 8 pixels of padding wider on each side.
fn column_width(window: &AppWindow, name: &str) -> Result<f32, String> {
    Ok(find(window, name)?.size().width + 16.0)
}

#[test]
fn dragging_a_separator_resizes_its_column_alone() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.show()?;
    let asked = record_resizes(&window);
    let artist = column_width(&window, "Artist")?;
    let album = column_width(&window, "Album")?;
    let handle = resize_handle(&window, "Artist")?;

    common::drag(
        &window,
        handle,
        slint::LogicalPosition::new(handle.x + 100.0, handle.y),
    );

    let widths = asked.borrow().clone().ok_or("no resize asked")?;
    assert!((widths.artist - (artist + 100.0)).abs() < 1.0, "{widths:?}");
    assert!((widths.album - album).abs() < 1.0, "{widths:?}");
    Ok(())
}

#[test]
fn a_column_never_gets_narrower_than_40_pixels() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.show()?;
    let asked = record_resizes(&window);
    let handle = resize_handle(&window, "Artist")?;

    common::drag(
        &window,
        handle,
        slint::LogicalPosition::new(handle.x - 500.0, handle.y),
    );

    let widths = asked.borrow().clone().ok_or("no resize asked")?;
    assert_eq!(widths.artist, 40.0);
    Ok(())
}

#[test]
fn a_double_click_on_a_separator_fits_the_column_to_its_longest_value() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.set_longest(TrackRow {
        artist: "Bloom".into(),
        album: "An album whose name goes on and on and on, far beyond any sensible width"
            .repeat(4)
            .into(),
        ..TrackRow::default()
    });
    window.show()?;
    let asked = record_resizes(&window);
    let artist = column_width(&window, "Artist")?;

    common::double_click(&window, resize_handle(&window, "Artist")?);
    let short = asked.borrow().clone().ok_or("no resize asked")?;
    common::double_click(&window, resize_handle(&window, "Album")?);
    let long = asked.borrow().clone().ok_or("no resize asked")?;

    assert!(short.artist < artist && short.artist > 40.0, "{short:?}");
    assert_eq!(long.album, 600.0);
    Ok(())
}

#[test]
fn resized_columns_wider_than_the_window_scroll_sideways() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    let narrow = TrackColumnWidths {
        title: 200.0,
        artist: 100.0,
        album: 100.0,
        year: 56.0,
        genre: 96.0,
        time: 56.0,
        bitrate: 72.0,
        tags: 132.0,
        file: 180.0,
        folder: 180.0,
    };
    window.set_columns_sized(true);
    window.set_column_widths(narrow.clone());
    window.show()?;
    assert!(!shows(&window, "Horizontal scroll bar"));

    window.set_column_widths(TrackColumnWidths {
        artist: 600.0,
        ..narrow
    });

    assert!(shows(&window, "Horizontal scroll bar"));
    Ok(())
}

/// The rows the table asks to select, with Command and Shift.
fn record_presses(window: &AppWindow) -> Rc<RefCell<Vec<(i32, bool, bool)>>> {
    let presses = Rc::new(RefCell::new(Vec::new()));
    window.on_track_pressed({
        let presses = Rc::clone(&presses);
        move |row, toggle, extend| presses.borrow_mut().push((row, toggle, extend))
    });
    presses
}

#[test]
fn a_click_on_a_row_asks_to_select_it_with_its_keys() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.show()?;
    let presses = record_presses(&window);

    find(&window, "Artist 00003")?.mock_single_click(PointerEventButton::Left);
    common::click_holding(&window, &[Key::Control], "Track 00005")?;
    common::click_holding(&window, &[Key::Shift], "Album 1")?;

    assert_eq!(
        *presses.borrow(),
        [(2, false, false), (4, true, false), (0, false, true)]
    );
    Ok(())
}

#[test]
fn the_keyboard_moves_and_extends_the_selection() -> TestResult {
    let window = window_with_tracks(100, 1440.0, 900.0)?;
    window.show()?;
    let commands = Rc::new(RefCell::new(Vec::new()));
    window.on_run({
        let commands = Rc::clone(&commands);
        move |command| commands.borrow_mut().push(command)
    });

    common::press(&window, &[], Key::DownArrow);
    common::press(&window, &[], Key::UpArrow);
    common::press(&window, &[Key::Shift], Key::DownArrow);
    common::press(&window, &[Key::Shift], Key::UpArrow);
    common::press(&window, &[Key::Control], "a");

    assert_eq!(
        *commands.borrow(),
        [
            WindowCommand::SelectNext,
            WindowCommand::SelectPrevious,
            WindowCommand::ExtendSelectionDown,
            WindowCommand::ExtendSelectionUp,
            WindowCommand::SelectAll
        ]
    );
    Ok(())
}

#[test]
fn the_focused_row_scrolls_into_view() -> TestResult {
    let window = window_with_tracks(10_000, 1440.0, 900.0)?;
    window.show()?;
    assert!(!shows(&window, "Track 05001"));

    window.set_focused_row(5000);
    settle();

    assert!(shows(&window, "Track 05001"));
    Ok(())
}

#[test]
fn the_headers_are_named_in_french_when_selected() -> TestResult {
    let window = window_with_tracks(10, 1440.0, 900.0)?;
    common::select_language("fr")?;
    window.show()?;

    for header in ["Titre", "Artiste", "Année", "Durée"] {
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
            rows[4].status = TrackStatus::Modified;
            rows[5] = TrackRow {
                status: TrackStatus::Unreadable,
                title: "06 Damaged file".into(),
                ..TrackRow::default()
            };
            for (index, row) in rows.iter_mut().enumerate() {
                let selected = |index: usize| matches!(index, 7..=9 | 12);
                row.selected = selected(index);
                row.selected_above = row.selected && index > 0 && selected(index - 1);
                row.selected_below = row.selected && selected(index + 1);
            }
            let window = window_with(rows, width as f32, height as f32)?;
            window.global::<Theme>().set_dark(dark);
            window.show()?;
            if sideways != 0.0 {
                find(&window, "Tracks")?.scroll(sideways, 0.0);
                settle();
                window.window().dispatch_event(WindowEvent::PointerExited);
            }
            assert_matches_reference(&window, &format!("tracks-{theme}-{width}x{height}.png"))?;
        }
    }
    Ok(())
}
