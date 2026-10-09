mod common;

use std::error::Error;
use std::fs;
use std::panic;

use colophon_tags::{Id3v2Version, Metadata, ReadError, TagFormat, read};

use common::{TestResult, fixture, fixtures_dir};

const SEED: u64 = 0x00c0_1094_0000_0003;
const MUTATIONS_PER_FIXTURE: usize = 300;

/// SplitMix64, a small pseudo-random generator: with a fixed seed, every run makes the same files.
struct Random(u64);

impl Random {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }

    fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }

    /// An offset that favours the headers: ID3v2 and the first frames at the start, ID3v1 at the end.
    fn offset(&mut self, len: usize) -> usize {
        match self.below(4) {
            0 | 1 => self.below(len.min(256)),
            2 => len - 1 - self.below(len.min(128)),
            _ => self.below(len),
        }
    }

    /// A new value for a byte: one bit flipped, a boundary value, or anything.
    fn byte(&mut self, old: u8) -> u8 {
        match self.below(4) {
            0 => old ^ (1 << self.below(8)),
            1 => 0x00,
            2 => 0xff,
            _ => self.next().to_le_bytes()[0],
        }
    }
}

/// A damaged copy of a fixture, named so that a failure can be replayed by hand.
struct Case {
    name: String,
    bytes: Vec<u8>,
}

struct Fixture {
    name: String,
    bytes: Vec<u8>,
}

fn fixtures() -> Result<Vec<Fixture>, Box<dyn Error>> {
    let mut paths: Vec<_> = fs::read_dir(fixtures_dir())?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<Result<_, _>>()?;
    paths.retain(|path| path.extension().is_some_and(|extension| extension == "mp3"));
    paths.sort();
    paths
        .iter()
        .map(|path| {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            Ok(Fixture {
                name: name.into_owned(),
                bytes: fs::read(path)?,
            })
        })
        .collect()
}

/// Every length in the first 512 bytes, where ID3v2 and the first frames are, and in the last 256,
/// where ID3v1 is, and 64 lengths in between.
fn truncations(name: &str, bytes: &[u8]) -> Vec<Case> {
    let len = bytes.len();
    let mut lengths: Vec<usize> = (0..len.min(512))
        .chain(len.saturating_sub(256)..=len)
        .chain((0..64).map(|step| len * step / 64))
        .collect();
    lengths.sort_unstable();
    lengths.dedup();
    lengths
        .into_iter()
        .map(|cut| Case {
            name: format!("{name} cut to {cut} bytes"),
            bytes: bytes[..cut].to_vec(),
        })
        .collect()
}

/// Copies with one to four bytes changed.
fn mutations(name: &str, bytes: &[u8], random: &mut Random) -> Vec<Case> {
    (0..MUTATIONS_PER_FIXTURE)
        .map(|_| {
            let mut bytes = bytes.to_vec();
            let edits: Vec<String> = (0..=random.below(4))
                .map(|_| {
                    let offset = random.offset(bytes.len());
                    bytes[offset] = random.byte(bytes[offset]);
                    format!("{offset}={:#04x}", bytes[offset])
                })
                .collect();
            Case {
                name: format!("{name} with bytes {}", edits.join(", ")),
                bytes,
            }
        })
        .collect()
}

#[test]
fn corrupted_files_never_panic() -> TestResult {
    let folder = tempfile::tempdir()?;
    let path = folder.path().join("corrupted.mp3");
    let mut random = Random(SEED);
    let mut count = 0;
    let mut panics = Vec::new();

    for fixture in fixtures()? {
        let mut cases = truncations(&fixture.name, &fixture.bytes);
        cases.extend(mutations(&fixture.name, &fixture.bytes, &mut random));
        for case in cases {
            fs::write(&path, &case.bytes)?;
            if panic::catch_unwind(|| read(&path)).is_err() {
                panics.push(case.name);
            }
            count += 1;
        }
    }

    assert!(
        panics.is_empty(),
        "{} of {count} corrupted files panicked:\n{}",
        panics.len(),
        panics.join("\n")
    );
    Ok(())
}

fn read_bytes(bytes: &[u8]) -> Result<Result<Metadata, ReadError>, Box<dyn Error>> {
    let folder = tempfile::tempdir()?;
    let path = folder.path().join("lying.mp3");
    fs::write(&path, bytes)?;
    Ok(read(&path))
}

/// `fixture` with `patch` written over its bytes from `offset`.
fn patched(fixture_name: &str, offset: usize, patch: &[u8]) -> Result<Vec<u8>, Box<dyn Error>> {
    let mut bytes = fs::read(fixture(fixture_name))?;
    bytes
        .get_mut(offset..offset + patch.len())
        .ok_or("the patch runs past the end of the fixture")?
        .copy_from_slice(patch);
    Ok(bytes)
}

/// The size of an ID3v2 tag, header included. The header's last four bytes hold the size of the
/// rest, seven bits per byte (syncsafe).
fn id3v2_len(bytes: &[u8]) -> usize {
    10 + bytes[6..10]
        .iter()
        .fold(0, |size, byte| size << 7 | usize::from(*byte))
}

#[test]
fn a_tag_said_to_be_longer_than_its_file_is_damaged() -> TestResult {
    // The case of the mockup's error screen: the header says 4,086 bytes in a file of 1,270.
    let result = read_bytes(&patched("v23_full.mp3", 6, &[0x00, 0x00, 0x1f, 0x76])?)?;

    assert!(matches!(result, Err(ReadError::Damaged(_))), "{result:?}");
    Ok(())
}

#[test]
fn a_tag_size_that_is_not_syncsafe_is_damaged() -> TestResult {
    let result = read_bytes(&patched("v23_full.mp3", 6, &[0xff; 4])?)?;

    assert!(matches!(result, Err(ReadError::Damaged(_))), "{result:?}");
    Ok(())
}

#[test]
fn a_frame_said_to_be_longer_than_its_tag_leaves_the_rest_readable() -> TestResult {
    // The first frame, TIT2, starts after the 10 byte tag header; its size follows its 4 byte ID.
    let metadata = read_bytes(&patched("v23_full.mp3", 14, &[0x7f, 0xff, 0xff, 0xff])?)??;

    assert_eq!(metadata.formats, [TagFormat::Id3v2(Id3v2Version::V2_3)]);
    assert_eq!(metadata.audio.sample_rate, Some(44_100));
    Ok(())
}

#[test]
fn an_empty_file_is_damaged() -> TestResult {
    let result = read_bytes(&[])?;

    assert!(matches!(result, Err(ReadError::Damaged(_))), "{result:?}");
    Ok(())
}

#[test]
fn tags_without_audio_are_damaged() -> TestResult {
    let id3v2 = fs::read(fixture("v23_full.mp3"))?;
    let id3v1 = fs::read(fixture("v1_1_ascii.mp3"))?;

    for bytes in [&id3v2[..id3v2_len(&id3v2)], &id3v1[id3v1.len() - 128..]] {
        let result = read_bytes(bytes)?;
        assert!(matches!(result, Err(ReadError::Damaged(_))), "{result:?}");
    }
    Ok(())
}
