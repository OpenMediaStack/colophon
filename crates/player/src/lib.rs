//! Colophon's sound: the system's default output device, through rodio.

use std::fmt;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::time::Duration;

use colophon_engine::{Output, PlayError};
use rodio::{Decoder, DeviceSinkBuilder, MixerDeviceSink, Player};

/// The system's default output device, playing one file at a time.
pub struct Speakers {
    /// The sound stops when the device goes.
    _device: MixerDeviceSink,
    player: Player,
}

impl Speakers {
    /// The default output device, if the system has one.
    pub fn open() -> Option<Self> {
        let mut device = DeviceSinkBuilder::open_default_sink().ok()?;
        device.log_on_drop(false);
        let player = Player::connect_new(device.mixer());
        Some(Self {
            _device: device,
            player,
        })
    }
}

/// A decoder of an MP3 that can move to any position.
fn decoder(path: &Path) -> Result<Decoder<BufReader<File>>, PlayError> {
    let file = File::open(path).map_err(PlayError::Open)?;
    let length = file.metadata().map_err(PlayError::Open)?.len();
    Decoder::builder()
        .with_data(BufReader::new(file))
        .with_byte_len(length)
        .with_seekable(true)
        .with_hint("mp3")
        .build()
        .map_err(|error| PlayError::Decode(error.to_string()))
}

impl fmt::Debug for Speakers {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.debug_struct("Speakers").finish_non_exhaustive()
    }
}

impl Output for Speakers {
    fn play(&mut self, path: &Path) -> Result<(), PlayError> {
        let decoder = decoder(path)?;
        self.player.clear();
        self.player.append(decoder);
        self.player.play();
        Ok(())
    }

    fn pause(&mut self) {
        self.player.pause();
    }

    fn resume(&mut self) {
        self.player.play();
    }

    fn stop(&mut self) {
        self.player.clear();
    }

    fn seek(&mut self, position: Duration) -> Result<(), PlayError> {
        self.player
            .try_seek(position)
            .map_err(|error| PlayError::Seek(error.to_string()))
    }

    fn position(&self) -> Duration {
        self.player.get_pos()
    }

    fn finished(&self) -> bool {
        self.player.empty()
    }

    fn set_volume(&mut self, volume: f32) {
        self.player.set_volume(volume);
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use rodio::Source;

    use super::*;

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../testdata")
            .join(name)
    }

    #[test]
    fn an_mp3_decodes_and_moves_to_a_position() -> Result<(), PlayError> {
        let mut decoder = decoder(&fixture("cbr_stereo.mp3"))?;

        assert!(
            decoder
                .total_duration()
                .is_some_and(|total| total > Duration::ZERO)
        );
        decoder
            .try_seek(Duration::from_millis(500))
            .map_err(|error| PlayError::Seek(error.to_string()))?;
        assert!(decoder.next().is_some());
        Ok(())
    }

    #[test]
    fn a_file_that_is_no_audio_is_refused() {
        assert!(matches!(
            decoder(&fixture("tiny_tag.mp3")),
            Err(PlayError::Decode(_))
        ));
        assert!(matches!(
            decoder(&fixture("missing.mp3")),
            Err(PlayError::Open(_))
        ));
    }
}
