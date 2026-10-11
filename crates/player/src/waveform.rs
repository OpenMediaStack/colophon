//! How loud a track is over its length: the lowest and highest sample of each slice, and how
//! loud it sounds, at several resolutions, so that a waveform of any width draws at once.

use std::path::Path;
use std::time::Duration;

use colophon_engine::PlayError;
use rodio::Source;

use crate::decoder;

/// The frames of a slice of the finest resolution.
const FRAMES_PER_PEAK: usize = 256;

/// The lowest and the highest sample of a slice, from -1 to 1, and what tells how loud it sounds.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Peak {
    pub low: f32,
    pub high: f32,
    /// The sum of the squares of its samples, and how many there are.
    squares: f64,
    frames: u32,
}

impl Peak {
    fn of(sample: f32) -> Peak {
        Peak {
            low: sample,
            high: sample,
            squares: f64::from(sample) * f64::from(sample),
            frames: 1,
        }
    }

    fn merge(self, other: Peak) -> Peak {
        Peak {
            low: self.low.min(other.low),
            high: self.high.max(other.high),
            squares: self.squares + other.squares,
            frames: self.frames.saturating_add(other.frames),
        }
    }

    /// How loud the slice sounds: the root mean square of its samples, from 0 to 1.
    pub fn loudness(self) -> f32 {
        if self.frames == 0 {
            return 0.0;
        }
        (self.squares / f64::from(self.frames)).sqrt() as f32
    }
}

/// A track's peaks, finest first, each level half as many as the one before.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Waveform {
    levels: Vec<Vec<Peak>>,
    /// How many frames the peaks cover.
    frames: u64,
    pub duration: Duration,
}

impl Waveform {
    /// Decodes a whole file to read its peaks.
    pub fn read(path: &Path) -> Result<Self, PlayError> {
        let decoder = decoder(path)?;
        let channels = usize::from(decoder.channels().get());
        let rate = decoder.sample_rate().get();
        Ok(Self::from_samples(decoder, channels, rate))
    }

    /// The peaks of interleaved samples of `channels` channels, all channels mixed.
    pub fn from_samples(
        samples: impl IntoIterator<Item = f32>,
        channels: usize,
        rate: u32,
    ) -> Self {
        let channels = channels.max(1);
        let mut finest = Vec::new();
        let mut current: Option<Peak> = None;
        let mut frames = 0;
        let mut sum = 0.0;
        let mut in_frame = 0;
        let mut total_frames: u64 = 0;
        for sample in samples {
            sum += sample;
            in_frame += 1;
            if in_frame < channels {
                continue;
            }
            let value = sum / channels as f32;
            sum = 0.0;
            in_frame = 0;
            total_frames += 1;
            let peak = Peak::of(value);
            current = Some(current.map_or(peak, |current| current.merge(peak)));
            frames += 1;
            if frames == FRAMES_PER_PEAK {
                finest.extend(current.take());
                frames = 0;
            }
        }
        finest.extend(current);
        let mut levels = vec![finest];
        while levels.last().is_some_and(|level| level.len() > 1) {
            let coarser = levels
                .last()
                .map(|level| {
                    level
                        .chunks(2)
                        .map(|pair| pair.iter().copied().fold(pair[0], Peak::merge))
                        .collect()
                })
                .unwrap_or_default();
            levels.push(coarser);
        }
        Self {
            levels,
            frames: total_frames,
            duration: Duration::from_secs_f64(total_frames as f64 / f64::from(rate.max(1))),
        }
    }

    /// `count` peaks across the whole track, each from the frames of its share of the track, read
    /// from the coarsest level whose peaks are no longer than an eighth of a share, so that a
    /// share takes in little of its neighbours. Empty for an empty file.
    pub fn peaks(&self, count: usize) -> Vec<Peak> {
        if count == 0 || self.frames == 0 {
            return Vec::new();
        }
        let share = self.frames / count as u64;
        let level = self
            .levels
            .iter()
            .enumerate()
            .rev()
            .find(|(level, _)| (FRAMES_PER_PEAK as u64) << level <= (share / 8).max(1))
            .or_else(|| self.levels.iter().enumerate().next());
        let Some((level, peaks)) = level else {
            return Vec::new();
        };
        let span = (FRAMES_PER_PEAK as u64) << level;
        (0..count as u64)
            .map(|bar| {
                let start = bar * self.frames / count as u64;
                let end = (bar + 1) * self.frames / count as u64;
                let first = usize::try_from(start / span).unwrap_or(usize::MAX);
                let last = usize::try_from(end.div_ceil(span)).unwrap_or(usize::MAX);
                peaks
                    .get(
                        first.min(peaks.len().saturating_sub(1))
                            ..last.clamp(first + 1, peaks.len()),
                    )
                    .unwrap_or_default()
                    .iter()
                    .copied()
                    .reduce(Peak::merge)
                    .unwrap_or_default()
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_sine_peaks_at_its_amplitude_whatever_the_width() {
        let samples = (0..44_100).map(|index| 0.5 * (index as f32 * 0.5).sin());
        let waveform = Waveform::from_samples(samples, 1, 44_100);

        for count in [1, 7, 100, 1000] {
            let peaks = waveform.peaks(count);
            assert_eq!(peaks.len(), count);
            assert!(
                peaks
                    .iter()
                    .all(|peak| peak.high > 0.45 && peak.low < -0.45)
            );
        }
        assert_eq!(waveform.duration, Duration::from_secs(1));
    }

    #[test]
    fn channels_are_mixed_and_silence_stays_flat() {
        let left_and_right = [0.8, -0.8].repeat(1000);
        let waveform = Waveform::from_samples(left_and_right, 2, 1000);

        let peaks = waveform.peaks(4);
        assert!(
            peaks
                .iter()
                .all(|peak| peak.high.abs() < 1e-6 && peak.low.abs() < 1e-6)
        );
        assert_eq!(waveform.duration, Duration::from_secs(1));
    }

    #[test]
    fn a_loud_moment_shows_where_it_is() {
        let samples = (0..10_000).map(|index| {
            if (5000..5100).contains(&index) {
                1.0
            } else {
                0.0
            }
        });
        let waveform = Waveform::from_samples(samples, 1, 10_000);

        let peaks = waveform.peaks(10);
        let loudest = peaks
            .iter()
            .enumerate()
            .max_by(|(_, one), (_, other)| one.high.total_cmp(&other.high))
            .map(|(bar, _)| bar);
        assert_eq!(loudest, Some(5));
    }

    #[test]
    fn loudness_is_the_root_mean_square() {
        let sine = (0..44_100)
            .map(|at| 0.5 * (std::f32::consts::TAU * 440.0 * at as f32 / 44_100.0).sin());
        let silence = std::iter::repeat_n(0.0, 44_100);
        let waveform = Waveform::from_samples(sine.chain(silence), 1, 44_100);

        let halves = waveform.peaks(2);

        // A sine's root mean square is its amplitude over the square root of two.
        assert!((halves[0].loudness() - 0.5 / 2_f32.sqrt()).abs() < 0.01);
        // The slice that straddles the middle lends the silence a little of the sine.
        assert!(halves[1].loudness() < 0.1);
    }

    #[test]
    fn nothing_to_read_gives_no_peaks() {
        let waveform = Waveform::from_samples(std::iter::empty(), 2, 44_100);

        assert!(waveform.peaks(100).is_empty());
    }

    #[test]
    fn a_fixture_reads_with_its_length() -> Result<(), PlayError> {
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata/cbr_stereo.mp3");

        let waveform = Waveform::read(&path)?;

        assert!(waveform.duration > Duration::ZERO);
        assert_eq!(waveform.peaks(50).len(), 50);
        Ok(())
    }
}
