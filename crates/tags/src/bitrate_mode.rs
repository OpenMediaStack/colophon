use std::io::{Read, Seek, SeekFrom};

use crate::BitrateMode;

/// Enough bytes after the ID3v2 tag for the first frames.
const BYTES_READ: u64 = 64 * 1024;
/// The junk lofty accepts before the first frame.
const MAX_JUNK: usize = 1024;
/// The frames compared when no header says how the bitrate goes.
const FRAMES_COMPARED: usize = 64;

/// In kilobits per second, by the 4 bits of the frame header; 0 and the last index are invalid.
const MPEG1_BITRATES: [u32; 16] = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
];
const MPEG2_BITRATES: [u32; 16] = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
];
const MPEG1_SAMPLE_RATES: [usize; 3] = [44_100, 48_000, 32_000];

/// Reads whether an MP3's bitrate is constant or variable: from the Xing, Info or VBRI header of
/// its first frame, or else from the bitrates of its first frames. `None` when no frame is found.
pub(crate) fn read_mode(reader: &mut (impl Read + Seek)) -> Option<BitrateMode> {
    reader.rewind().ok()?;
    let mut start = [0; 10];
    reader.read_exact(&mut start).ok()?;
    reader.seek(SeekFrom::Start(id3v2_len(&start))).ok()?;
    let mut bytes = Vec::new();
    reader.take(BYTES_READ).read_to_end(&mut bytes).ok()?;
    mode_of(&bytes)
}

/// The size of the ID3v2 tag that opens a file, header and footer included, or 0 without one.
fn id3v2_len(start: &[u8; 10]) -> u64 {
    if &start[..3] != b"ID3" {
        return 0;
    }
    let size = start[6..10]
        .iter()
        .fold(0, |size, byte| size << 7 | u64::from(byte & 0x7f));
    let footer = if start[5] & 0x10 == 0 { 0 } else { 10 };
    10 + size + footer
}

struct Frame {
    mpeg1: bool,
    mono: bool,
    bitrate: u32,
    len: usize,
}

/// The Layer III frame whose header starts `bytes`.
fn frame_at(bytes: &[u8]) -> Option<Frame> {
    let &[sync, flags, rates, mode] = bytes.first_chunk::<4>()?;
    let version = (flags >> 3) & 3;
    let layer = (flags >> 1) & 3;
    // Version 1 is reserved; layer 1 is Layer III.
    if sync != 0xff || flags & 0xe0 != 0xe0 || version == 1 || layer != 1 {
        return None;
    }
    let mpeg1 = version == 3;
    let bitrates = if mpeg1 {
        MPEG1_BITRATES
    } else {
        MPEG2_BITRATES
    };
    let bitrate = bitrates[usize::from(rates >> 4)];
    // MPEG 2 halves the sample rates of MPEG 1, MPEG 2.5 quarters them.
    let divisor = match version {
        3 => 1,
        2 => 2,
        _ => 4,
    };
    let sample_rate = MPEG1_SAMPLE_RATES.get(usize::from((rates >> 2) & 3))? / divisor;
    if bitrate == 0 {
        return None;
    }
    let samples_per_byte = if mpeg1 { 144_000 } else { 72_000 };
    Some(Frame {
        mpeg1,
        mono: mode >> 6 == 3,
        bitrate,
        len: samples_per_byte * bitrate as usize / sample_rate + usize::from((rates >> 1) & 1),
    })
}

fn mode_of(bytes: &[u8]) -> Option<BitrateMode> {
    let start =
        (0..bytes.len().min(MAX_JUNK)).find(|&offset| frame_at(&bytes[offset..]).is_some())?;
    let frames = &bytes[start..];
    let first = frame_at(frames)?;
    if let Some(mode) = header_mode(frames, &first) {
        return Some(mode);
    }
    let mut offset = 0;
    for _ in 0..FRAMES_COMPARED {
        let Some(frame) = frames.get(offset..).and_then(frame_at) else {
            break;
        };
        if frame.bitrate != first.bitrate {
            return Some(BitrateMode::Variable);
        }
        offset += frame.len;
    }
    Some(BitrateMode::Constant)
}

/// LAME writes "Xing" in the first frame of a variable bitrate file and "Info" in that of a
/// constant one, after the frame's side information; Fraunhofer's encoder writes "VBRI" 32 bytes in.
fn header_mode(frames: &[u8], first: &Frame) -> Option<BitrateMode> {
    let side_info = match (first.mpeg1, first.mono) {
        (true, true) => 17,
        (true, false) => 32,
        (false, true) => 9,
        (false, false) => 17,
    };
    match frames.get(4 + side_info..8 + side_info)? {
        b"Xing" => Some(BitrateMode::Variable),
        b"Info" => Some(BitrateMode::Constant),
        _ => (frames.get(36..40)? == b"VBRI").then_some(BitrateMode::Variable),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An MPEG 1 Layer III frame at 44.1 kHz, of `bitrate_index`, with `marker` where its header
    /// would be.
    fn frame(bitrate_index: u8, mono: bool, marker: &[u8; 4]) -> Vec<u8> {
        let header = [
            0xff,
            0xfb,
            bitrate_index << 4,
            if mono { 0xc0 } else { 0x00 },
        ];
        let len = frame_at(&header).map_or(0, |frame| frame.len);
        let mut bytes = vec![0; len];
        bytes[..4].copy_from_slice(&header);
        let at = if mono { 21 } else { 36 };
        bytes[at..at + 4].copy_from_slice(marker);
        bytes
    }

    fn frames(bitrate_indexes: &[u8]) -> Vec<u8> {
        bitrate_indexes
            .iter()
            .flat_map(|&index| frame(index, false, b"\0\0\0\0"))
            .collect()
    }

    #[test]
    fn a_xing_header_means_a_variable_bitrate() {
        assert_eq!(
            mode_of(&frame(5, true, b"Xing")),
            Some(BitrateMode::Variable)
        );
    }

    #[test]
    fn an_info_header_means_a_constant_bitrate() {
        assert_eq!(
            mode_of(&frame(9, false, b"Info")),
            Some(BitrateMode::Constant)
        );
    }

    #[test]
    fn frames_of_one_bitrate_without_a_header_are_constant() {
        assert_eq!(mode_of(&frames(&[9, 9, 9])), Some(BitrateMode::Constant));
    }

    #[test]
    fn frames_of_different_bitrates_without_a_header_are_variable() {
        assert_eq!(
            mode_of(&frames(&[11, 2, 1, 1])),
            Some(BitrateMode::Variable)
        );
    }

    #[test]
    fn junk_before_the_first_frame_is_skipped() {
        let mut bytes = vec![0; 300];
        bytes.extend(frame(9, false, b"Info"));
        assert_eq!(mode_of(&bytes), Some(BitrateMode::Constant));
    }

    #[test]
    fn bytes_without_a_frame_have_no_mode() {
        assert_eq!(mode_of(b"Not an MP3 at all"), None);
        assert_eq!(mode_of(&[0xff; 64]), None);
    }

    #[test]
    fn the_id3v2_tag_is_measured_with_its_footer() {
        assert_eq!(id3v2_len(b"ID3\x04\x00\x00\x00\x00\x02\x01"), 10 + 257);
        assert_eq!(id3v2_len(b"ID3\x04\x00\x10\x00\x00\x00\x40"), 10 + 64 + 10);
        assert_eq!(id3v2_len(b"\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00"), 0);
    }
}
