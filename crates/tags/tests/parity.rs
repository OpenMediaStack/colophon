mod common;

use std::collections::HashMap;
use std::error::Error;
use std::fs;
use std::path::Path;

use colophon_tags::Metadata;

use common::{TestResult, fixtures_dir};

/// What ffprobe read in a fixture: its `-of flat` output, saved in `testdata/ffprobe/` by `make.sh`.
fn ffprobe(path: &Path) -> Result<HashMap<String, String>, Box<dyn Error>> {
    let output = String::from_utf8_lossy(&fs::read(path)?).into_owned();
    Ok(output
        .lines()
        .filter_map(|line| line.split_once('='))
        .map(|(key, value)| (key.to_owned(), value.trim_matches('"').to_owned()))
        .collect())
}

/// The differences between Colophon and ffprobe on one fixture.
fn differences(metadata: &Metadata, probe: &HashMap<String, String>) -> Vec<String> {
    let tags = &metadata.tags;
    let audio = &metadata.audio;
    let pair = |number: Option<u32>, total: Option<u32>| match (number, total) {
        (Some(number), Some(total)) => Some(format!("{number}/{total}")),
        (Some(number), None) => Some(number.to_string()),
        _ => None,
    };
    let fields = [
        ("format.tags.title", tags.title.clone()),
        ("format.tags.artist", tags.artist.clone()),
        ("format.tags.album_artist", tags.album_artist.clone()),
        ("format.tags.album", tags.album.clone()),
        ("format.tags.genre", tags.genre.clone()),
        ("format.tags.comment", tags.comment.clone()),
        ("format.tags.date", tags.year.map(|year| year.to_string())),
        ("format.tags.track", pair(tags.track, tags.track_total)),
        ("format.tags.disc", pair(tags.disc, tags.disc_total)),
        (
            "streams.stream.0.sample_rate",
            audio.sample_rate.map(|rate| rate.to_string()),
        ),
        (
            "streams.stream.0.channels",
            audio.channels.map(|channels| channels.to_string()),
        ),
    ];
    let mut differences: Vec<String> = fields
        .into_iter()
        .filter(|(key, ours)| {
            let theirs = probe.get(*key);
            // ffprobe passes ID3v1 bytes through unchanged, so Latin-1 text is not valid UTF-8 there.
            theirs.is_none_or(|theirs| !theirs.contains('\u{fffd}')) && theirs != ours.as_ref()
        })
        .map(|(key, ours)| format!("{key}: ours {ours:?}, ffprobe {:?}", probe.get(key)))
        .collect();

    // ffprobe takes the encoder delay and padding the LAME header gives off the duration, lofty
    // counts every frame: two frames at most, about 50 ms.
    let duration = probe
        .get("format.duration")
        .and_then(|seconds| seconds.parse::<f64>().ok());
    let ours = audio.duration.map(|duration| duration.as_secs_f64());
    if !matches!((ours, duration), (Some(ours), Some(theirs)) if (ours - theirs).abs() < 0.06) {
        differences.push(format!("duration: ours {ours:?}, ffprobe {duration:?}"));
    }

    // lofty divides the stream's size by its duration, the LAME header's frame included, which
    // adds a few percent to the 1 s fixtures and nothing to a whole song.
    let bitrate = probe
        .get("streams.stream.0.bit_rate")
        .and_then(|bits| bits.parse::<f64>().ok())
        .map(|bits| bits / 1000.0);
    let ours = audio.bitrate.map(f64::from);
    if !matches!((ours, bitrate), (Some(ours), Some(theirs)) if (ours - theirs).abs() <= theirs * 0.03)
    {
        differences.push(format!("bitrate: ours {ours:?}, ffprobe {bitrate:?}"));
    }
    differences
}

#[test]
fn colophon_reads_what_ffprobe_reads() -> TestResult {
    let mut probes: Vec<_> = fs::read_dir(fixtures_dir().join("ffprobe"))?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<Result<_, _>>()?;
    probes.retain(|path| path.extension().is_some_and(|extension| extension == "txt"));
    probes.sort();
    assert!(
        !probes.is_empty(),
        "no ffprobe output, run testdata/make.sh"
    );

    let mut report = Vec::new();
    for probe in &probes {
        let name = probe
            .file_stem()
            .ok_or("an ffprobe output without a name")?;
        let metadata = colophon_tags::read(&fixtures_dir().join(name).with_extension("mp3"))?;
        for difference in differences(&metadata, &ffprobe(probe)?) {
            report.push(format!("{}: {difference}", probe.display()));
        }
    }
    assert!(report.is_empty(), "{}", report.join("\n"));
    Ok(())
}
