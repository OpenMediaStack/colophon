use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use colophon_library::Track;
use colophon_library::tags::Tags;

/// Where the table's tracks come from: what the sidebar chose.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]
pub enum Source {
    #[default]
    AllTracks,
    /// The tracks with changes waiting to be saved, or saved since Colophon started.
    RecentlyChanged,
    /// The tracks whose tags could not be read.
    Unreadable,
    /// The tracks under a folder of the library.
    Folder(PathBuf),
    Album(AlbumKey),
    Artist(String),
}

/// An album: its title, and the album artist, or else the artist, that sets it apart from
/// another album of the same title.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AlbumKey {
    pub title: String,
    pub artist: Option<String>,
}

impl AlbumKey {
    pub fn of(tags: &Tags) -> Option<Self> {
        Some(Self {
            title: tags.album.clone()?,
            artist: tags.album_artist.clone().or_else(|| tags.artist.clone()),
        })
    }
}

/// What the table can be sorted by.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SortColumn {
    Number,
    Title,
    Artist,
    Album,
    Year,
    Genre,
    Time,
    Bitrate,
    Tags,
    File,
    Folder,
}

/// The order of the table: by a column, up or down.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Sort {
    pub column: SortColumn,
    pub descending: bool,
}

/// The albums and artists of the library, with how many tracks each has, in alphabetical order.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Groups {
    pub albums: Vec<(AlbumKey, usize)>,
    pub artists: Vec<(String, usize)>,
}

/// Groups the readable tracks by album and by artist, from their files' tags.
pub(crate) fn groups(tracks: &[Track]) -> Groups {
    let mut albums: BTreeMap<AlbumKey, usize> = BTreeMap::new();
    let mut artists: BTreeMap<String, usize> = BTreeMap::new();
    for tags in tracks.iter().filter_map(file_tags) {
        if let Some(album) = AlbumKey::of(tags) {
            *albums.entry(album).or_default() += 1;
        }
        if let Some(artist) = &tags.artist {
            *artists.entry(artist.clone()).or_default() += 1;
        }
    }
    let by_name = |one: &String, other: &String| one.to_lowercase().cmp(&other.to_lowercase());
    let mut albums: Vec<_> = albums.into_iter().collect();
    albums.sort_by(|(one, _), (other, _)| by_name(&one.title, &other.title).then(one.cmp(other)));
    let mut artists: Vec<_> = artists.into_iter().collect();
    artists.sort_by(|(one, _), (other, _)| by_name(one, other).then(one.cmp(other)));
    Groups { albums, artists }
}

/// What the listing needs to know of the library beyond its tracks.
pub(crate) struct Context<'a> {
    pub tracks: &'a [Track],
    /// The tags each track shows: those waiting to be saved, or else its file's.
    pub shown: &'a dyn Fn(usize) -> Option<&'a Tags>,
    /// The tracks with changes pending or saved since Colophon started.
    pub changed: &'a BTreeSet<usize>,
}

/// The tracks the table lists, in order: those of `source` whose title, artist, album or file
/// name holds `filter`, ignoring case, sorted by `sort` or else in library order.
pub(crate) fn list(
    context: &Context<'_>,
    source: &Source,
    filter: &str,
    sort: Option<Sort>,
) -> Vec<usize> {
    let filter = filter.trim().to_lowercase();
    let mut listed: Vec<usize> = (0..context.tracks.len())
        .filter(|track| in_source(context, *track, source))
        .filter(|track| filter.is_empty() || matches(context, *track, &filter))
        .collect();
    if let Some(sort) = sort {
        let mut keyed: Vec<(SortKey, usize)> = listed
            .into_iter()
            .map(|track| (sort_key(context, track, sort.column), track))
            .collect();
        keyed.sort_by(|(one, one_track), (other, other_track)| {
            let order = one.primary.cmp(&other.primary);
            let order = if sort.descending {
                order.reverse()
            } else {
                order
            };
            order
                .then_with(|| one.album_order.cmp(&other.album_order))
                .then(one_track.cmp(other_track))
        });
        listed = keyed.into_iter().map(|(_, track)| track).collect();
    }
    listed
}

fn file_tags(track: &Track) -> Option<&Tags> {
    track.metadata.as_ref().ok().map(|metadata| &metadata.tags)
}

fn in_source(context: &Context<'_>, track: usize, source: &Source) -> bool {
    let Some(listed) = context.tracks.get(track) else {
        return false;
    };
    match source {
        Source::AllTracks => true,
        Source::RecentlyChanged => context.changed.contains(&track),
        Source::Unreadable => listed.metadata.is_err(),
        Source::Folder(folder) => listed.path.starts_with(folder),
        Source::Album(album) => file_tags(listed).and_then(AlbumKey::of).as_ref() == Some(album),
        Source::Artist(artist) => {
            file_tags(listed).and_then(|tags| tags.artist.as_ref()) == Some(artist)
        }
    }
}

fn matches(context: &Context<'_>, track: usize, filter: &str) -> bool {
    let holds =
        |value: Option<&str>| value.is_some_and(|value| value.to_lowercase().contains(filter));
    let name = context
        .tracks
        .get(track)
        .and_then(|track| file_name(&track.path));
    let tags = (context.shown)(track);
    holds(name.as_deref())
        || tags.is_some_and(|tags| {
            holds(tags.title.as_deref())
                || holds(tags.artist.as_deref())
                || holds(tags.album.as_deref())
        })
}

fn file_name(path: &Path) -> Option<String> {
    Some(path.file_name()?.to_string_lossy().into_owned())
}

/// A value to sort by: text ignoring case or a number, a missing one coming last either way.
#[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Value {
    Number(u64),
    Text(String),
    Missing,
}

struct SortKey {
    primary: Value,
    /// Album, disc and track number: the order of an album, which settles ties.
    album_order: (Value, u32, u32),
}

fn sort_key(context: &Context<'_>, track: usize, column: SortColumn) -> SortKey {
    let listed = context.tracks.get(track);
    let tags = (context.shown)(track);
    let metadata = listed.and_then(|track| track.metadata.as_ref().ok());
    let text = |value: Option<&String>| {
        value.map_or(Value::Missing, |value| Value::Text(value.to_lowercase()))
    };
    let number = |value: Option<u64>| value.map_or(Value::Missing, Value::Number);
    let title = tags
        .and_then(|tags| tags.title.clone())
        .or_else(|| listed.and_then(|track| file_name(&track.path)));
    let primary = match column {
        SortColumn::Number => number(tags.and_then(|tags| tags.track).map(u64::from)),
        SortColumn::Title => text(title.as_ref()),
        SortColumn::Artist => text(tags.and_then(|tags| tags.artist.as_ref())),
        SortColumn::Album => text(tags.and_then(|tags| tags.album.as_ref())),
        SortColumn::Year => number(tags.and_then(|tags| tags.year).map(u64::from)),
        SortColumn::Genre => text(tags.and_then(|tags| tags.genre.as_ref())),
        SortColumn::Time => number(
            metadata
                .and_then(|metadata| metadata.audio.duration)
                .map(|duration| duration.as_millis().try_into().unwrap_or(u64::MAX)),
        ),
        SortColumn::Bitrate => number(
            metadata
                .and_then(|metadata| metadata.audio.bitrate)
                .map(u64::from),
        ),
        SortColumn::Tags => text(
            metadata
                .map(|metadata| {
                    metadata
                        .formats
                        .iter()
                        .map(ToString::to_string)
                        .collect::<Vec<_>>()
                        .join(", ")
                })
                .filter(|formats| !formats.is_empty())
                .as_ref(),
        ),
        SortColumn::File => text(listed.and_then(|track| file_name(&track.path)).as_ref()),
        SortColumn::Folder => text(
            listed
                .and_then(|track| track.path.parent())
                .map(|folder| folder.to_string_lossy().into_owned())
                .as_ref(),
        ),
    };
    SortKey {
        primary,
        album_order: (
            text(tags.and_then(|tags| tags.album.as_ref())),
            tags.and_then(|tags| tags.disc).unwrap_or(0),
            tags.and_then(|tags| tags.track).unwrap_or(0),
        ),
    }
}
