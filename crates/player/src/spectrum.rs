//! How loud each frequency of a track is over its length, and the highest frequency it holds: an
//! MP3 encoded from another lossy file stops well below where its own encoder would.

use std::path::Path;

use colophon_engine::PlayError;
use rodio::Source;
use rustfft::FftPlanner;
use rustfft::num_complex::Complex;

use crate::decoder;

/// The samples of each analysis, and how far below the loudest a level fades to nothing.
const WINDOW: usize = 2048;
const FLOOR_DB: f32 = -120.0;
/// A track holds sound when its loudest frequency is at least this loud on average, and holds
/// the frequencies at most this far below that one: the window spreads a little of each
/// frequency to its neighbours, far quieter.
const HELD_DB: f32 = -90.0;
const HELD_RANGE_DB: f32 = 60.0;

/// Loudness from 0, silent, to 1, as loud as a sample can be, row by row from the lowest
/// frequency up, column by column from the start.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Spectrum {
    pub columns: usize,
    pub rows: usize,
    pub levels: Vec<f32>,
    /// Half the sample rate, the highest frequency the file can hold, in hertz.
    pub nyquist: u32,
    /// The highest frequency the track holds, in hertz.
    pub highest: Option<u32>,
}

impl Spectrum {
    /// Decodes a whole file to read its spectrum.
    pub fn read(path: &Path, columns: usize, rows: usize) -> Result<Self, PlayError> {
        let decoder = decoder(path)?;
        let channels = usize::from(decoder.channels().get());
        let rate = decoder.sample_rate().get();
        Ok(Self::from_samples(decoder, channels, rate, columns, rows))
    }

    /// The spectrum of interleaved samples of `channels` channels, all channels mixed.
    pub fn from_samples(
        samples: impl IntoIterator<Item = f32>,
        channels: usize,
        rate: u32,
        columns: usize,
        rows: usize,
    ) -> Self {
        let channels = channels.max(1);
        let mut mono = Vec::new();
        let mut frame = Vec::with_capacity(channels);
        for sample in samples {
            frame.push(sample);
            if frame.len() == channels {
                mono.push(frame.iter().sum::<f32>() / channels as f32);
                frame.clear();
            }
        }
        let nyquist = rate / 2;
        if mono.is_empty() || columns == 0 || rows == 0 {
            return Self {
                columns,
                rows,
                levels: vec![0.0; columns * rows],
                nyquist,
                highest: None,
            };
        }

        let fft = FftPlanner::new().plan_fft_forward(WINDOW);
        let hann: Vec<f32> = (0..WINDOW)
            .map(|at| {
                let phase = std::f32::consts::TAU * at as f32 / (WINDOW - 1) as f32;
                0.5 - 0.5 * phase.cos()
            })
            .collect();
        let bins = WINDOW / 2;
        let mut levels = vec![0.0; columns * rows];
        let mut sums = vec![0.0_f64; rows];
        let mut buffer = vec![Complex::default(); WINDOW];
        for column in 0..columns {
            let start = (column * mono.len() / columns).min(mono.len().saturating_sub(WINDOW));
            for (at, slot) in buffer.iter_mut().enumerate() {
                let sample = mono.get(start + at).copied().unwrap_or_default();
                *slot = Complex::new(sample * hann[at], 0.0);
            }
            fft.process(&mut buffer);
            for row in 0..rows {
                let first = row * bins / rows;
                let last = ((row + 1) * bins / rows).max(first + 1);
                // A sine as loud as a sample can be peaks at a quarter of the window, Hann's gain.
                let loudest = buffer[first..last.min(bins)]
                    .iter()
                    .map(|bin| bin.norm() / (WINDOW as f32 / 4.0))
                    .fold(0.0_f32, f32::max);
                let decibels = 20.0 * loudest.max(1e-9).log10();
                sums[row] += f64::from(decibels.max(FLOOR_DB));
                levels[row * columns + column] = (1.0 - decibels / FLOOR_DB).clamp(0.0, 1.0);
            }
        }
        let means: Vec<f32> = sums
            .iter()
            .map(|sum| (sum / columns as f64) as f32)
            .collect();
        let loudest = means.iter().copied().fold(FLOOR_DB, f32::max);
        let highest = (loudest > HELD_DB)
            .then(|| {
                means
                    .iter()
                    .rposition(|mean| *mean > loudest - HELD_RANGE_DB)
            })
            .flatten()
            .map(|row| u32::try_from((row + 1) * nyquist as usize / rows).unwrap_or(nyquist));
        Self {
            columns,
            rows,
            levels,
            nyquist,
            highest,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(frequency: f32, rate: u32) -> impl Iterator<Item = f32> {
        (0..rate).map(move |at| {
            0.5 * (std::f32::consts::TAU * frequency * at as f32 / rate as f32).sin()
        })
    }

    #[test]
    fn a_sine_is_the_highest_frequency_held() {
        let spectrum = Spectrum::from_samples(sine(1000.0, 44_100), 1, 44_100, 50, 220);

        let highest = spectrum.highest.unwrap_or_default();
        assert!((900..=1300).contains(&highest), "{highest}");
        assert_eq!(spectrum.nyquist, 22_050);
        assert_eq!(spectrum.levels.len(), 50 * 220);
    }

    #[test]
    fn the_sine_is_loud_where_it_is_and_quiet_above() {
        let spectrum = Spectrum::from_samples(sine(5000.0, 44_100), 1, 44_100, 10, 100);
        let level = |row: usize| spectrum.levels[row * spectrum.columns + 5];

        let row_of_sine = 5000 * 100 / 22_050;
        assert!(level(row_of_sine) > 0.8);
        assert!(level(90) < 0.3);
    }

    #[test]
    fn silence_holds_no_frequency() {
        let spectrum = Spectrum::from_samples(vec![0.0; 44_100], 1, 44_100, 10, 10);

        assert_eq!(spectrum.highest, None);
    }

    #[test]
    fn a_fixture_reads() -> Result<(), PlayError> {
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata/cbr_stereo.mp3");

        let spectrum = Spectrum::read(&path, 40, 64)?;

        assert_eq!(spectrum.levels.len(), 40 * 64);
        assert_eq!(spectrum.nyquist, 22_050);
        Ok(())
    }
}
