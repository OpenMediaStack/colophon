//! How a file's tags are laid out, byte by byte: for people who write ID3 readers and writers.

use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::Path;

use crate::Id3v2Version;

/// Where a file's tags are, and what they are made of.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Layout {
    pub id3v2: Option<Id3v2Layout>,
    /// Where the ID3v1 tag starts, 128 bytes before the end of the file.
    pub id3v1: Option<u64>,
}

/// An ID3v2 tag at the start of a file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Id3v2Layout {
    pub version: Id3v2Version,
    pub revision: u8,
    /// The whole tag is unsynchronised: in ID3v2.3, the offsets of its frames are those of the
    /// tag once resynchronised.
    pub unsynchronisation: bool,
    pub extended_header: bool,
    pub experimental: bool,
    pub footer: bool,
    /// Its size, header and footer included.
    pub size: u32,
    /// The zeros after its last frame.
    pub padding: u32,
    pub frames: Vec<FrameLayout>,
}

/// A frame of an ID3v2 tag.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrameLayout {
    pub id: String,
    /// Where its header starts, from the start of the file.
    pub offset: u32,
    /// The size of its content, its header left out.
    pub size: u32,
    pub flags: FrameFlags,
    /// The encoding of its text, for the frames that hold some.
    pub encoding: Option<TextEncoding>,
    /// What it holds, as text: its text, or what it is when it is not text.
    pub value: FrameValue,
}

/// The flags of a frame that change how its content reads. ID3v2.2 frames have none.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct FrameFlags {
    pub read_only: bool,
    pub grouping: bool,
    pub compression: bool,
    pub encryption: bool,
    pub unsynchronisation: bool,
    pub data_length: bool,
}

/// How a frame encodes its text.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TextEncoding {
    Latin1,
    /// UTF-16 with a byte order mark.
    Utf16,
    Utf16Be,
    Utf8,
}

/// What a frame holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FrameValue {
    Text(String),
    /// A picture: its type, such as image/jpeg, and its size in bytes.
    Picture {
        mime: String,
        size: usize,
    },
    /// Compressed or encrypted content, which this reader does not open.
    Sealed,
    /// Bytes this reader does not decode.
    Binary,
}

#[derive(Debug, thiserror::Error)]
pub enum LayoutError {
    #[error("could not read the file")]
    Io(#[from] io::Error),
}

/// Reads how the tags of the file at `path` are laid out. A tag this reader does not understand
/// is reported as far as it goes.
pub fn layout(path: &Path) -> Result<Layout, LayoutError> {
    let mut file = File::open(path)?;
    let length = file.metadata()?.len();
    let mut header = [0; 10];
    let id3v2 = match file.read_exact(&mut header) {
        Ok(()) if header.starts_with(b"ID3") => {
            let size = synchsafe(&header[6..10]);
            let mut body = vec![0; usize::try_from(size).unwrap_or(0)];
            let read = read_up_to(&mut file, &mut body)?;
            body.truncate(read);
            id3v2_layout(&header, body)
        }
        _ => None,
    };
    let id3v1 = if length >= 128 {
        file.seek(SeekFrom::Start(length - 128))?;
        let mut marker = [0; 3];
        file.read_exact(&mut marker)?;
        (&marker == b"TAG").then_some(length - 128)
    } else {
        None
    };
    Ok(Layout { id3v2, id3v1 })
}

fn read_up_to(file: &mut File, buffer: &mut [u8]) -> io::Result<usize> {
    let mut read = 0;
    while read < buffer.len() {
        match file.read(&mut buffer[read..])? {
            0 => break,
            count => read += count,
        }
    }
    Ok(read)
}

fn id3v2_layout(header: &[u8; 10], mut body: Vec<u8>) -> Option<Id3v2Layout> {
    let version = match header[3] {
        2 => Id3v2Version::V2_2,
        3 => Id3v2Version::V2_3,
        4 => Id3v2Version::V2_4,
        _ => return None,
    };
    let flags = header[5];
    let unsynchronisation = flags & 0x80 != 0;
    let extended_header = version != Id3v2Version::V2_2 && flags & 0x40 != 0;
    let footer = version == Id3v2Version::V2_4 && flags & 0x10 != 0;
    // ID3v2.4 unsynchronises frame by frame, each saying so.
    if unsynchronisation && version != Id3v2Version::V2_4 {
        body = resynchronise(&body);
    }
    let mut position = if extended_header {
        match version {
            Id3v2Version::V2_3 => be_u32(body.get(..4)?) as usize + 4,
            _ => synchsafe(body.get(..4)?) as usize,
        }
    } else {
        0
    };
    let mut frames = Vec::new();
    let header_size = if version == Id3v2Version::V2_2 { 6 } else { 10 };
    while position + header_size <= body.len() && body[position] != 0 {
        let frame = &body[position..];
        let (id, size, raw_flags) = match version {
            Id3v2Version::V2_2 => (&frame[..3], be_u24(&frame[3..6]), 0),
            Id3v2Version::V2_3 => (&frame[..4], be_u32(&frame[4..8]), be_u16(&frame[8..10])),
            Id3v2Version::V2_4 => (&frame[..4], synchsafe(&frame[4..8]), be_u16(&frame[8..10])),
        };
        let Ok(id) = std::str::from_utf8(id) else {
            break;
        };
        let start = position + header_size;
        let end = start.saturating_add(size as usize).min(body.len());
        let flags = frame_flags(version, raw_flags, unsynchronisation);
        let (encoding, value) = frame_value(id, version, flags, &body[start..end]);
        frames.push(FrameLayout {
            id: id.to_owned(),
            offset: u32::try_from(10 + position).unwrap_or(u32::MAX),
            size,
            flags,
            encoding,
            value,
        });
        position = end;
    }
    let tag_size = synchsafe(&header[6..10]);
    Some(Id3v2Layout {
        version,
        revision: header[4],
        unsynchronisation,
        extended_header,
        experimental: version != Id3v2Version::V2_2 && flags & 0x20 != 0,
        footer,
        size: tag_size + 10 + if footer { 10 } else { 0 },
        padding: u32::try_from(body.len().saturating_sub(position)).unwrap_or(0),
        frames,
    })
}

fn frame_flags(version: Id3v2Version, flags: u16, whole_tag_unsynchronised: bool) -> FrameFlags {
    match version {
        Id3v2Version::V2_2 => FrameFlags::default(),
        Id3v2Version::V2_3 => FrameFlags {
            read_only: flags & 0x2000 != 0,
            compression: flags & 0x0080 != 0,
            encryption: flags & 0x0040 != 0,
            grouping: flags & 0x0020 != 0,
            unsynchronisation: whole_tag_unsynchronised,
            data_length: false,
        },
        Id3v2Version::V2_4 => FrameFlags {
            read_only: flags & 0x1000 != 0,
            grouping: flags & 0x0040 != 0,
            compression: flags & 0x0008 != 0,
            encryption: flags & 0x0004 != 0,
            unsynchronisation: flags & 0x0002 != 0 || whole_tag_unsynchronised,
            data_length: flags & 0x0001 != 0,
        },
    }
}

/// What a frame's content says, once the bytes its flags add are skipped.
fn frame_value(
    id: &str,
    version: Id3v2Version,
    flags: FrameFlags,
    content: &[u8],
) -> (Option<TextEncoding>, FrameValue) {
    if flags.compression || flags.encryption {
        return (None, FrameValue::Sealed);
    }
    let mut content = content;
    if flags.grouping {
        content = content.get(1..).unwrap_or_default();
    }
    if flags.data_length {
        content = content.get(4..).unwrap_or_default();
    }
    let resynchronised;
    if flags.unsynchronisation && version == Id3v2Version::V2_4 {
        resynchronised = resynchronise(content);
        content = &resynchronised;
    }
    let Some((&encoding_byte, rest)) = content.split_first() else {
        return (None, FrameValue::Binary);
    };
    let encoding = match encoding_byte {
        0 => TextEncoding::Latin1,
        1 => TextEncoding::Utf16,
        2 => TextEncoding::Utf16Be,
        3 => TextEncoding::Utf8,
        _ => return (None, FrameValue::Binary),
    };
    let text = |bytes: &[u8]| decode(encoding, bytes);
    match id {
        "TXXX" | "TXX" | "WXXX" | "WXX" => {
            let (description, value) = split_once(encoding, rest);
            let value = if id.starts_with('W') {
                latin1(value)
            } else {
                text(value)
            };
            (
                Some(encoding),
                FrameValue::Text(join(&text(description), &value)),
            )
        }
        "COMM" | "COM" | "USLT" | "ULT" => {
            let rest = rest.get(3..).unwrap_or_default();
            let (description, value) = split_once(encoding, rest);
            (
                Some(encoding),
                FrameValue::Text(join(&text(description), &text(value))),
            )
        }
        "APIC" => {
            let (mime, rest) = split_once(TextEncoding::Latin1, rest);
            let rest = rest.get(1..).unwrap_or_default();
            let (_, data) = split_once(encoding, rest);
            let mime = latin1(mime);
            (
                Some(encoding),
                FrameValue::Picture {
                    mime,
                    size: data.len(),
                },
            )
        }
        "PIC" => {
            let format = latin1(rest.get(..3).unwrap_or_default());
            let rest = rest.get(4..).unwrap_or_default();
            let (_, data) = split_once(encoding, rest);
            let mime = format!("image/{}", format.to_lowercase());
            (
                Some(encoding),
                FrameValue::Picture {
                    mime,
                    size: data.len(),
                },
            )
        }
        _ if id.starts_with('T') => {
            let values: Vec<String> = text(rest)
                .split('\0')
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
                .collect();
            (Some(encoding), FrameValue::Text(values.join(" / ")))
        }
        _ => (None, FrameValue::Binary),
    }
}

fn join(description: &str, value: &str) -> String {
    if description.is_empty() {
        value.to_owned()
    } else {
        format!("{description}: {value}")
    }
}

/// The text before the first terminator of `encoding`, and what follows it.
fn split_once(encoding: TextEncoding, bytes: &[u8]) -> (&[u8], &[u8]) {
    let wide = matches!(encoding, TextEncoding::Utf16 | TextEncoding::Utf16Be);
    let end = if wide {
        bytes
            .as_chunks::<2>()
            .0
            .iter()
            .position(|pair| *pair == [0, 0])
            .map(|pair| pair * 2)
    } else {
        bytes.iter().position(|byte| *byte == 0)
    };
    match end {
        Some(end) => (&bytes[..end], &bytes[end + if wide { 2 } else { 1 }..]),
        None => (bytes, &[]),
    }
}

/// The text of `bytes`, without the terminator a writer may leave at its end.
fn decode(encoding: TextEncoding, bytes: &[u8]) -> String {
    let mut text = decode_all(encoding, bytes);
    text.truncate(text.trim_end_matches('\0').len());
    text
}

fn decode_all(encoding: TextEncoding, bytes: &[u8]) -> String {
    match encoding {
        TextEncoding::Latin1 => latin1(bytes),
        TextEncoding::Utf8 => String::from_utf8_lossy(bytes).into_owned(),
        TextEncoding::Utf16 | TextEncoding::Utf16Be => {
            let little = encoding == TextEncoding::Utf16 && bytes.starts_with(&[0xff, 0xfe]);
            let bytes = match bytes {
                [0xff, 0xfe, rest @ ..] | [0xfe, 0xff, rest @ ..] => rest,
                rest => rest,
            };
            let units: Vec<u16> = bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|pair| {
                    if little {
                        u16::from_le_bytes(*pair)
                    } else {
                        u16::from_be_bytes(*pair)
                    }
                })
                .collect();
            String::from_utf16_lossy(&units)
        }
    }
}

fn latin1(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| char::from(*byte)).collect()
}

/// Undoes unsynchronisation: each 0xFF 0x00 becomes 0xFF.
fn resynchronise(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut previous = 0;
    for &byte in bytes {
        if !(previous == 0xff && byte == 0) {
            out.push(byte);
        }
        previous = byte;
    }
    out
}

fn synchsafe(bytes: &[u8]) -> u32 {
    bytes
        .iter()
        .fold(0, |size, byte| (size << 7) | u32::from(byte & 0x7f))
}

fn be_u32(bytes: &[u8]) -> u32 {
    bytes
        .iter()
        .fold(0, |size, byte| (size << 8) | u32::from(*byte))
}

fn be_u24(bytes: &[u8]) -> u32 {
    be_u32(bytes)
}

fn be_u16(bytes: &[u8]) -> u16 {
    u16::from_be_bytes([bytes[0], bytes[1]])
}
