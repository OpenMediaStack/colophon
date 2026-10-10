use colophon_library::Track;
use colophon_library::tags::{ReadError, TagFormat};

use crate::Selection;

/// What the inspector shows of the selected tracks.
#[derive(Debug)]
pub enum Inspection<'a> {
    /// Nothing is selected.
    Nothing,
    /// One track is selected, and its tags could not be read.
    Unreadable {
        track: &'a Track,
        error: &'a ReadError,
    },
    Tracks(Box<Summary>),
}

/// One value of the selected tracks: the same for all of them, or not.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum Shared<T> {
    /// No selected track has a value.
    #[default]
    Empty,
    Same(T),
    /// The selected tracks do not all have the same value, some having none perhaps.
    Mixed,
}

impl<T: PartialEq> Shared<T> {
    /// What the values of every track have in common.
    fn of(values: impl IntoIterator<Item = Option<T>>) -> Self {
        let mut values = values.into_iter();
        let Some(first) = values.next() else {
            return Shared::Empty;
        };
        if values.all(|value| value == first) {
            first.map_or(Shared::Empty, Shared::Same)
        } else {
            Shared::Mixed
        }
    }
}

/// The audio properties shown in one line, when every track shares them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioLine {
    /// In kilobits per second.
    pub bitrate: u32,
    /// In hertz.
    pub sample_rate: u32,
}

/// The selected tracks whose tags could be read, field by field.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Summary {
    /// How many tracks are selected, the unreadable ones included.
    pub count: usize,
    pub unreadable: usize,
    /// The title of a single track; for one without a title tag, its file name.
    pub heading: Option<String>,
    pub title: Shared<String>,
    pub artist: Shared<String>,
    pub album_artist: Shared<String>,
    pub album: Shared<String>,
    pub year: Shared<u16>,
    pub track: Shared<u32>,
    pub track_total: Shared<u32>,
    pub genre: Shared<String>,
    pub comment: Shared<String>,
    pub audio: Shared<AudioLine>,
    pub formats: Shared<Vec<TagFormat>>,
    /// The size of every selected file, in bytes.
    pub size: u64,
}

pub(crate) fn inspect<'a>(tracks: &'a [Track], selection: &Selection) -> Inspection<'a> {
    let selected: Vec<&Track> = selection
        .iter()
        .filter_map(|index| tracks.get(index))
        .collect();
    match selected.as_slice() {
        [] => Inspection::Nothing,
        [track] => match &track.metadata {
            Ok(_) => Inspection::Tracks(Box::new(summarise(&selected))),
            Err(error) => Inspection::Unreadable { track, error },
        },
        _ => Inspection::Tracks(Box::new(summarise(&selected))),
    }
}

fn summarise(selected: &[&Track]) -> Summary {
    let read: Vec<_> = selected
        .iter()
        .filter_map(|track| track.metadata.as_ref().ok())
        .collect();
    let tags = || read.iter().map(|metadata| &metadata.tags);
    let text = |field: fn(&colophon_library::tags::Tags) -> &Option<String>| {
        Shared::of(tags().map(|tags| field(tags).clone()))
    };
    let heading = match selected {
        [track] => track.metadata.as_ref().ok().and_then(|metadata| {
            metadata.tags.title.clone().or_else(|| {
                track
                    .path
                    .file_stem()
                    .map(|stem| stem.to_string_lossy().into_owned())
            })
        }),
        _ => None,
    };
    Summary {
        count: selected.len(),
        unreadable: selected.len() - read.len(),
        heading,
        title: text(|tags| &tags.title),
        artist: text(|tags| &tags.artist),
        album_artist: text(|tags| &tags.album_artist),
        album: text(|tags| &tags.album),
        year: Shared::of(tags().map(|tags| tags.year)),
        track: Shared::of(tags().map(|tags| tags.track)),
        track_total: Shared::of(tags().map(|tags| tags.track_total)),
        genre: text(|tags| &tags.genre),
        comment: text(|tags| &tags.comment),
        audio: Shared::of(read.iter().map(|metadata| {
            let audio = &metadata.audio;
            audio
                .bitrate
                .zip(audio.sample_rate)
                .map(|(bitrate, sample_rate)| AudioLine {
                    bitrate,
                    sample_rate,
                })
        })),
        formats: Shared::of(read.iter().map(|metadata| Some(metadata.formats.clone()))),
        size: selected.iter().map(|track| track.size).sum(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values_shared_by_every_track_show_once() {
        assert_eq!(Shared::of([Some(1), Some(1)]), Shared::Same(1));
    }

    #[test]
    fn different_values_are_mixed() {
        assert_eq!(Shared::of([Some(1), Some(2)]), Shared::<i32>::Mixed);
    }

    #[test]
    fn a_value_some_tracks_lack_is_mixed() {
        assert_eq!(Shared::of([Some(1), None]), Shared::Mixed);
        assert_eq!(Shared::of([None, Some(1)]), Shared::Mixed);
    }

    #[test]
    fn a_value_no_track_has_is_empty() {
        assert_eq!(Shared::of([None::<i32>, None]), Shared::Empty);
        assert_eq!(Shared::of([] as [Option<i32>; 0]), Shared::Empty);
    }
}
