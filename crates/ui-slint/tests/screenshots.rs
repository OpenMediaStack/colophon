//! The screenshots of the README, written to `docs/assets` by
//! `cargo test -p colophon-ui --test screenshots -- --ignored`.

mod common;

use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use colophon_engine::Engine;
use colophon_engine::tags::{self, Cover, Id3v2Version, TagVersions, Tags};
use colophon_ui::{AppWindow, ComponentHandle, Theme};
use image::{Rgb, RgbImage};
use slint::platform::{Key, PointerEventButton, WindowEvent};
use slint::{ModelRc, VecModel};

use common::{TestResult, find};

/// An album of the library shown: its artist, title, year, genre, cover colours and tracks,
/// each with its length in seconds.
struct Album {
    artist: &'static str,
    title: &'static str,
    year: u16,
    genre: &'static str,
    colours: [[u8; 3]; 3],
    tracks: &'static [(&'static str, u32)],
}

const ALBUMS: [Album; 3] = [
    Album {
        artist: "Cassette Bloom",
        title: "Analog Hearts",
        year: 2021,
        genre: "Synthpop",
        colours: [[0x2E, 0x10, 0x4F], [0xD9, 0x46, 0x8A], [0xF8, 0xC8, 0x6B]],
        tracks: &[
            ("Neon Weather", 216),
            ("Rewind", 192),
            ("Analog Hearts", 254),
            ("Static Bloom", 229),
            ("Night Drive", 292),
            ("Afterglow", 238),
        ],
    },
    Album {
        artist: "Juniper Vale",
        title: "Field Notes",
        year: 2016,
        genre: "Folk",
        colours: [[0x16, 0x3B, 0x2E], [0x6F, 0xA2, 0x7C], [0xEE, 0xE6, 0xCF]],
        tracks: &[
            ("Morning Chorus", 178),
            ("Riverstones", 224),
            ("Field Notes", 250),
            ("Hollow Oak", 207),
            ("Wintering", 312),
        ],
    },
    Album {
        artist: "Marlowe Kite",
        title: "Small Hours",
        year: 2019,
        genre: "Indie Pop",
        colours: [[0x10, 0x1A, 0x33], [0x2F, 0x5D, 0x8C], [0xEA, 0xB3, 0x08]],
        tracks: &[
            ("Lanterns at Noon", 222),
            ("Paper Satellites", 245),
            ("The Long Way Down", 198),
            ("Small Hours", 301),
            ("Glasshouse", 235),
            ("Last Ferry Home", 267),
        ],
    },
];

/// Draws an album cover: a gradient between the first two colours, with rings of the third
/// around a point that each album moves.
fn cover(album: &Album, seed: u32) -> Result<Vec<u8>, Box<dyn Error>> {
    const SIZE: u32 = 600;
    let [dark, light, accent] = album.colours;
    let centre = (
        SIZE as f32 * (0.3 + 0.2 * (seed % 3) as f32),
        SIZE as f32 * 0.62,
    );
    let image = RgbImage::from_fn(SIZE, SIZE, |x, y| {
        let along = (x + y) as f32 / (2 * SIZE) as f32;
        let mut pixel: [f32; 3] =
            std::array::from_fn(|c| dark[c] as f32 + (light[c] as f32 - dark[c] as f32) * along);
        let distance = ((x as f32 - centre.0).powi(2) + (y as f32 - centre.1).powi(2)).sqrt();
        let ring = (distance / 26.0).fract();
        if distance < 230.0 && ring < 0.18 {
            let fade = 1.0 - distance / 230.0;
            for c in 0..3 {
                pixel[c] += (accent[c] as f32 - pixel[c]) * fade;
            }
        }
        if distance < 46.0 {
            pixel = accent.map(f32::from);
        }
        Rgb(pixel.map(|value| value.round().clamp(0.0, 255.0) as u8))
    });
    let mut bytes = Vec::new();
    image.write_to(
        &mut std::io::Cursor::new(&mut bytes),
        image::ImageFormat::Jpeg,
    )?;
    Ok(bytes)
}

/// About a second of MP3 audio at 128 kbit/s, without the Info frame that would give the length
/// of the fixture rather than of its repetitions.
fn second_of_audio() -> Result<Vec<u8>, Box<dyn Error>> {
    let fixture =
        fs::read(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/cbr_stereo.mp3"))?;
    // At 128 kbit/s and 44.1 kHz, an unpadded frame is 417 bytes.
    let audio = fixture.get(417..).ok_or("the fixture is too short")?;
    if !audio.starts_with(&[0xFF, 0xFB]) {
        return Err("no frame after the fixture's Info frame".into());
    }
    Ok(audio.to_vec())
}

/// A music folder in `home`, with a folder per album, its tracks tagged with its cover, and the
/// file of its first track.
fn library(home: &Path) -> Result<(PathBuf, PathBuf), Box<dyn Error>> {
    let music = home.join("Music");
    let second = second_of_audio()?;
    // 128 kbit/s is 16 000 bytes a second.
    let repeats = |seconds: u32| (seconds as usize * 16_000 + second.len() / 2) / second.len();
    let mut first = None;
    for (seed, album) in ALBUMS.iter().enumerate() {
        let folder = music.join(format!("{} - {}", album.artist, album.title));
        fs::create_dir_all(&folder)?;
        let cover = Cover {
            mime: Some("image/jpeg".into()),
            data: Arc::from(cover(album, seed as u32)?),
        };
        for (number, (title, seconds)) in (1..).zip(album.tracks) {
            let path = folder.join(format!("{number:02} {title}.mp3"));
            fs::write(&path, second.repeat(repeats(*seconds)))?;
            let tags = Tags {
                title: Some((*title).into()),
                artist: Some(album.artist.into()),
                album_artist: Some(album.artist.into()),
                album: Some(album.title.into()),
                year: Some(album.year),
                track: Some(number),
                track_total: Some(album.tracks.len() as u32),
                genre: Some(album.genre.into()),
                cover: Some(cover.clone()),
                ..Tags::default()
            };
            let versions = TagVersions {
                id3v2: Some(Id3v2Version::V2_4),
                id3v1: None,
            };
            tags::write(&path, &tags, versions)?;
            first.get_or_insert(path);
        }
    }
    Ok((music, first.ok_or("no track")?))
}

/// A waveform of `count` bars that rises and falls like a song, with some grain.
fn bars(count: i32) -> Vec<f32> {
    let mut grain = 7_u32;
    (0..count)
        .map(|bar| {
            grain = grain.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            let noise = (grain >> 16) as f32 / 65_535.0;
            let place = bar as f32 / count as f32;
            let swell = 0.55 + 0.3 * (place * 9.0).sin() * (place * 2.2).cos();
            (swell + 0.25 * noise).clamp(0.12, 1.0)
        })
        .collect()
}

/// The window on the library, in a theme, at twice the size of its pixels, playing `playing`.
fn window_on(library: &Path, playing: &Path, dark: bool) -> Result<AppWindow, Box<dyn Error>> {
    common::use_testing_backend()?;
    let path = library.to_path_buf();
    let window = colophon_ui::main_window(Engine::new(), move || Some(path.clone()))?;
    common::prepare(&window, 1440.0, 900.0)?;
    window.set_mac_shortcuts(false);
    window.global::<Theme>().set_dark(dark);
    window
        .window()
        .dispatch_event(WindowEvent::ScaleFactorChanged { scale_factor: 2.0 });
    window
        .window()
        .set_size(slint::PhysicalSize::new(2880, 1800));
    window.show()?;
    find(&window, "Open folder")?.invoke_accessible_default_action();
    common::wait_until_shown(&window, "17 tracks")?;
    find(&window, "Static Bloom")?.mock_single_click(PointerEventButton::Left);
    // The covers of the sidebar and the inspector load on timers.
    for _ in 0..40 {
        i_slint_backend_testing::mock_elapsed_time(Duration::from_millis(60));
        std::thread::sleep(Duration::from_millis(5));
    }
    // An edit waits to be saved.
    common::retype(&window, "Title", "Static Bloom (Radio Edit)")?;
    common::press(&window, &[], Key::Return);
    window
        .window()
        .dispatch_event(WindowEvent::WindowActiveChanged(false));
    let metadata = tags::read(playing)?;
    let duration = metadata.audio.duration.ok_or("no duration")?.as_secs();
    let position = duration * 38 / 100;
    window.set_player_available(true);
    window.set_player_has_track(true);
    window.set_player_playing(true);
    window.set_player_title(metadata.tags.title.unwrap_or_default().into());
    window.set_player_artist(metadata.tags.artist.unwrap_or_default().into());
    window.set_player_position(format!("{}:{:02}", position / 60, position % 60).into());
    window.set_player_duration(format!("{}:{:02}", duration / 60, duration % 60).into());
    window.set_player_progress(position as f32 / duration as f32);
    window.set_player_has_waveform(true);
    // The window asks for as many bars as fit, which the bridge would draw from the sound.
    let weak = window.as_weak();
    window.on_player_bars_wanted(move |count| {
        if let Some(window) = weak.upgrade() {
            window.set_player_bars(ModelRc::new(VecModel::from(bars(count))));
        }
    });
    Ok(window)
}

#[test]
#[ignore = "writes the README's screenshots"]
fn readme_screenshots() -> TestResult {
    let home = tempfile::tempdir()?;
    // SAFETY: the test runs alone in its binary, before it starts any thread. The sidebar then
    // shows the library as `~/Music`.
    #[allow(unsafe_code)]
    unsafe {
        std::env::set_var("HOME", home.path());
    }
    let (library, playing) = library(home.path())?;
    let assets = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../docs/assets");
    fs::create_dir_all(&assets)?;
    for (dark, name) in [(false, "light"), (true, "dark")] {
        let window = window_on(&library, &playing, dark)?;
        let snapshot = window.window().take_snapshot()?;
        let image = image::RgbaImage::from_raw(
            snapshot.width(),
            snapshot.height(),
            snapshot.as_bytes().to_vec(),
        )
        .ok_or("the snapshot's size does not match its pixels")?;
        image.save(assets.join(format!("screenshot-{name}.png")))?;
    }
    Ok(())
}
