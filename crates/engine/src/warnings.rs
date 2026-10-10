use std::collections::{BTreeMap, HashMap};
use std::hash::Hash;
use std::path::Path;

use colophon_library::tags::Tags;

/// What looks wrong in a track's tags beside the other tracks of its album: those of the same
/// folder with the same album title.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Warnings {
    /// The track has no number, while other tracks of its album have one.
    pub missing_number: bool,
    /// Its album artist is not the one most tracks of its album have.
    pub odd_album_artist: bool,
}

impl Warnings {
    pub fn any(self) -> bool {
        self.missing_number || self.odd_album_artist
    }
}

impl std::ops::BitOr for Warnings {
    type Output = Self;

    fn bitor(self, other: Self) -> Self {
        Self {
            missing_number: self.missing_number || other.missing_number,
            odd_album_artist: self.odd_album_artist || other.odd_album_artist,
        }
    }
}

/// The tracks with something that looks wrong, among these tracks with the tags they show.
pub(crate) fn warnings<'a>(
    tracks: impl IntoIterator<Item = (usize, &'a Path, &'a Tags)>,
) -> BTreeMap<usize, Warnings> {
    let mut albums: HashMap<(&Path, &str), Vec<(usize, &Tags)>> = HashMap::new();
    for (track, path, tags) in tracks {
        if let (Some(folder), Some(album)) = (path.parent(), tags.album.as_deref()) {
            albums
                .entry((folder, album))
                .or_default()
                .push((track, tags));
        }
    }
    let mut found = BTreeMap::new();
    for album in albums.values().filter(|album| album.len() > 1) {
        let numbered = album.iter().any(|(_, tags)| tags.track.is_some());
        let usual_artist = most_common(album.iter().map(|(_, tags)| tags.album_artist.as_deref()));
        for (track, tags) in album {
            let warnings = Warnings {
                missing_number: numbered && tags.track.is_none(),
                odd_album_artist: usual_artist
                    .is_some_and(|usual| tags.album_artist.as_deref() != usual),
            };
            if warnings.any() {
                found.insert(*track, warnings);
            }
        }
    }
    found
}

/// The value that comes up most often, unless another comes up as often.
fn most_common<T: Eq + Hash + Copy>(values: impl IntoIterator<Item = T>) -> Option<T> {
    let mut counts: HashMap<T, usize> = HashMap::new();
    for value in values {
        *counts.entry(value).or_default() += 1;
    }
    let most = *counts.values().max()?;
    let mut tops = counts
        .into_iter()
        .filter(|(_, count)| *count == most)
        .map(|(value, _)| value);
    let top = tops.next()?;
    tops.next().is_none().then_some(top)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn tags(album: &str, track: Option<u32>, album_artist: Option<&str>) -> Tags {
        Tags {
            album: Some(album.into()),
            track,
            album_artist: album_artist.map(Into::into),
            ..Tags::default()
        }
    }

    fn found(tracks: &[(&str, Tags)]) -> BTreeMap<usize, Warnings> {
        let paths: Vec<PathBuf> = tracks.iter().map(|(path, _)| PathBuf::from(path)).collect();
        warnings(
            tracks
                .iter()
                .zip(&paths)
                .enumerate()
                .map(|(track, ((_, tags), path))| (track, path.as_path(), tags)),
        )
    }

    #[test]
    fn a_track_without_a_number_stands_out_in_a_numbered_album() {
        let warnings = found(&[
            ("/music/a/1.mp3", tags("Analog Hearts", Some(1), None)),
            ("/music/a/2.mp3", tags("Analog Hearts", None, None)),
            ("/music/b/3.mp3", tags("Field Notes", None, None)),
            ("/music/b/4.mp3", tags("Field Notes", None, None)),
        ]);

        assert_eq!(
            warnings,
            BTreeMap::from([(
                1,
                Warnings {
                    missing_number: true,
                    odd_album_artist: false,
                }
            )])
        );
    }

    #[test]
    fn an_album_artist_unlike_the_others_stands_out() {
        let warnings = found(&[
            (
                "/music/a/1.mp3",
                tags("Analog Hearts", Some(1), Some("Cassette Bloom")),
            ),
            (
                "/music/a/2.mp3",
                tags("Analog Hearts", Some(2), Some("Cassette Bloom")),
            ),
            (
                "/music/a/3.mp3",
                tags("Analog Hearts", Some(3), Some("Casette Bloom")),
            ),
        ]);

        assert_eq!(warnings.keys().copied().collect::<Vec<_>>(), [2]);
        assert!(warnings[&2].odd_album_artist);
    }

    #[test]
    fn a_tie_or_a_lone_track_raises_nothing() {
        assert!(
            found(&[
                (
                    "/music/a/1.mp3",
                    tags("Analog Hearts", Some(1), Some("One"))
                ),
                (
                    "/music/a/2.mp3",
                    tags("Analog Hearts", Some(2), Some("Other"))
                ),
                ("/music/b/1.mp3", tags("Field Notes", None, None)),
            ])
            .is_empty()
        );
    }

    #[test]
    fn the_same_title_in_two_folders_makes_two_albums() {
        assert!(
            found(&[
                (
                    "/music/a/1.mp3",
                    tags("Greatest Hits", Some(1), Some("One"))
                ),
                ("/music/b/1.mp3", tags("Greatest Hits", None, Some("Other"))),
            ])
            .is_empty()
        );
    }
}
