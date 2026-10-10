use std::collections::{BTreeMap, BTreeSet};

use colophon_library::Track;
use colophon_library::tags::Tags;

/// A field of the inspector, which an edit changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Field {
    Title,
    Artist,
    AlbumArtist,
    Album,
    Year,
    Track,
    TrackTotal,
    Genre,
    Comment,
}

impl Field {
    pub const ALL: [Field; 9] = [
        Field::Title,
        Field::Artist,
        Field::AlbumArtist,
        Field::Album,
        Field::Year,
        Field::Track,
        Field::TrackTotal,
        Field::Genre,
        Field::Comment,
    ];

    /// Whether two sets of tags hold different values for this field.
    pub fn differs(self, one: &Tags, other: &Tags) -> bool {
        match self {
            Field::Title => one.title != other.title,
            Field::Artist => one.artist != other.artist,
            Field::AlbumArtist => one.album_artist != other.album_artist,
            Field::Album => one.album != other.album,
            Field::Year => one.year != other.year,
            Field::Track => one.track != other.track,
            Field::TrackTotal => one.track_total != other.track_total,
            Field::Genre => one.genre != other.genre,
            Field::Comment => one.comment != other.comment,
        }
    }
}

/// A new value for one field of the selected tracks. `None`, or empty text, empties the field.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Edit {
    Title(Option<String>),
    Artist(Option<String>),
    AlbumArtist(Option<String>),
    Album(Option<String>),
    Year(Option<u16>),
    Track(Option<u32>),
    TrackTotal(Option<u32>),
    Genre(Option<String>),
    Comment(Option<String>),
}

impl Edit {
    pub fn field(&self) -> Field {
        match self {
            Edit::Title(_) => Field::Title,
            Edit::Artist(_) => Field::Artist,
            Edit::AlbumArtist(_) => Field::AlbumArtist,
            Edit::Album(_) => Field::Album,
            Edit::Year(_) => Field::Year,
            Edit::Track(_) => Field::Track,
            Edit::TrackTotal(_) => Field::TrackTotal,
            Edit::Genre(_) => Field::Genre,
            Edit::Comment(_) => Field::Comment,
        }
    }

    fn apply(&self, tags: &mut Tags) {
        let text = |value: &Option<String>| value.clone().filter(|value| !value.is_empty());
        match self {
            Edit::Title(value) => tags.title = text(value),
            Edit::Artist(value) => tags.artist = text(value),
            Edit::AlbumArtist(value) => tags.album_artist = text(value),
            Edit::Album(value) => tags.album = text(value),
            Edit::Year(value) => tags.year = *value,
            Edit::Track(value) => tags.track = *value,
            Edit::TrackTotal(value) => tags.track_total = *value,
            Edit::Genre(value) => tags.genre = text(value),
            Edit::Comment(value) => tags.comment = text(value),
        }
    }
}

/// One step of the history: the tags of each track it changed, before and after, and the field
/// it edited, if it came from an edit.
#[derive(Debug, Clone)]
struct Action {
    field: Option<Field>,
    changes: Vec<Change>,
}

#[derive(Debug, Clone)]
struct Change {
    track: usize,
    before: Tags,
    after: Tags,
}

/// The tags the user wants for each track, where they differ from the file's, and the history
/// of how they got there. The history holds values rather than "modified or not", so that undoing
/// an edit already saved brings the old values back as a change to save.
#[derive(Debug, Default)]
pub struct Edits {
    pending: BTreeMap<usize, Tags>,
    undo: Vec<Action>,
    redo: Vec<Action>,
}

impl Edits {
    /// The tags the user wants for a track, if they differ from the file's.
    pub fn pending(&self, track: usize) -> Option<&Tags> {
        self.pending.get(&track)
    }

    /// The tracks whose tags differ from their file's, in library order.
    pub fn modified(&self) -> impl Iterator<Item = (usize, &Tags)> + '_ {
        self.pending.iter().map(|(track, tags)| (*track, tags))
    }

    pub fn modified_count(&self) -> usize {
        self.pending.len()
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }

    /// The fields of these tracks whose values differ from their files'.
    pub fn modified_fields(
        &self,
        tracks: &[Track],
        selected: impl IntoIterator<Item = usize>,
    ) -> BTreeSet<Field> {
        selected
            .into_iter()
            .filter_map(|track| Some((self.pending(track)?, saved_tags(tracks, track)?)))
            .flat_map(|(wanted, saved)| {
                Field::ALL
                    .into_iter()
                    .filter(|field| field.differs(wanted, saved))
            })
            .collect()
    }

    /// Applies `edit` to each of these tracks whose tags could be read. When `continues`, the
    /// edit goes on with the latest step, if that step edited the same field of the same tracks:
    /// typing a word makes one step, and typing back the old value makes none.
    pub(crate) fn edit(
        &mut self,
        tracks: &[Track],
        selected: impl IntoIterator<Item = usize>,
        edit: &Edit,
        continues: bool,
    ) {
        let changes: Vec<Change> = selected
            .into_iter()
            .filter_map(|track| {
                let before = self.wanted(tracks, track)?;
                let mut after = before.clone();
                edit.apply(&mut after);
                Some(Change {
                    track,
                    before,
                    after,
                })
            })
            .collect();
        if continues && self.continue_last(tracks, edit.field(), &changes) {
            return;
        }
        self.record(tracks, Some(edit.field()), changes);
    }

    /// Folds `changes` into the latest step, if it edited `field` of the same tracks.
    fn continue_last(&mut self, tracks: &[Track], field: Field, changes: &[Change]) -> bool {
        let Some(last) = self.undo.last_mut() else {
            return false;
        };
        let same_tracks = last.changes.len() == changes.len()
            && last
                .changes
                .iter()
                .zip(changes)
                .all(|(last, change)| last.track == change.track);
        if last.field != Some(field) || !same_tracks {
            return false;
        }
        for (last, change) in last.changes.iter_mut().zip(changes) {
            last.after = change.after.clone();
        }
        let undone = last
            .changes
            .iter()
            .all(|change| change.before == change.after);
        let wanted: Vec<(usize, Tags)> = last
            .changes
            .iter()
            .map(|change| (change.track, change.after.clone()))
            .collect();
        if undone {
            self.undo.pop();
        }
        for (track, tags) in wanted {
            self.want(tracks, track, tags);
        }
        self.redo.clear();
        true
    }

    /// Brings these tracks back to their files' tags.
    pub(crate) fn revert(&mut self, tracks: &[Track], selected: impl IntoIterator<Item = usize>) {
        let changes = selected
            .into_iter()
            .filter_map(|track| {
                Some(Change {
                    track,
                    before: self.pending(track)?.clone(),
                    after: saved_tags(tracks, track)?.clone(),
                })
            })
            .collect();
        self.record(tracks, None, changes);
    }

    pub(crate) fn undo(&mut self, tracks: &[Track]) {
        if let Some(action) = self.undo.pop() {
            for change in &action.changes {
                self.want(tracks, change.track, change.before.clone());
            }
            self.redo.push(action);
        }
    }

    pub(crate) fn redo(&mut self, tracks: &[Track]) {
        if let Some(action) = self.redo.pop() {
            for change in &action.changes {
                self.want(tracks, change.track, change.after.clone());
            }
            self.undo.push(action);
        }
    }

    /// Forgets a track's pending tags once its file holds them, after a save.
    pub(crate) fn settle(&mut self, tracks: &[Track], track: usize) {
        if let Some(tags) = self.pending.get(&track).cloned() {
            self.want(tracks, track, tags);
        }
    }

    /// Takes in a change that does change something as the latest step of the history.
    fn record(&mut self, tracks: &[Track], field: Option<Field>, changes: Vec<Change>) {
        let changes: Vec<Change> = changes
            .into_iter()
            .filter(|change| change.before != change.after)
            .collect();
        if changes.is_empty() {
            return;
        }
        for change in &changes {
            self.want(tracks, change.track, change.after.clone());
        }
        self.undo.push(Action { field, changes });
        self.redo.clear();
    }

    /// The tags a track should have: the pending ones, or else its file's.
    fn wanted(&self, tracks: &[Track], track: usize) -> Option<Tags> {
        self.pending(track)
            .or_else(|| saved_tags(tracks, track))
            .cloned()
    }

    fn want(&mut self, tracks: &[Track], track: usize, tags: Tags) {
        if saved_tags(tracks, track) == Some(&tags) {
            self.pending.remove(&track);
        } else {
            self.pending.insert(track, tags);
        }
    }
}

/// The tags in a track's file, if they could be read.
fn saved_tags(tracks: &[Track], track: usize) -> Option<&Tags> {
    tracks
        .get(track)?
        .metadata
        .as_ref()
        .ok()
        .map(|metadata| &metadata.tags)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use colophon_library::tags::{Metadata, ReadError};

    use super::*;

    fn track(title: &str) -> Track {
        Track {
            path: PathBuf::from(format!("/music/{title}.mp3")),
            size: 0,
            modified: None,
            metadata: Ok(Metadata {
                tags: Tags {
                    title: Some(title.into()),
                    ..Tags::default()
                },
                ..Metadata::default()
            }),
        }
    }

    fn unreadable() -> Track {
        Track {
            metadata: Err(ReadError::ReaderPanicked),
            ..track("broken")
        }
    }

    fn title(edits: &Edits, tracks: &[Track], track: usize) -> Option<String> {
        edits.wanted(tracks, track).and_then(|tags| tags.title)
    }

    fn renamed(title: &str) -> Edit {
        Edit::Title(Some(title.into()))
    }

    #[test]
    fn an_edit_changes_every_selected_track() {
        let tracks = [track("a"), track("b"), track("c")];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0, 2], &renamed("New"), false);

        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("New"));
        assert_eq!(title(&edits, &tracks, 1).as_deref(), Some("b"));
        assert_eq!(title(&edits, &tracks, 2).as_deref(), Some("New"));
        assert_eq!(edits.modified_count(), 2);
    }

    #[test]
    fn empty_text_empties_the_field() {
        let tracks = [track("a")];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0], &Edit::Title(Some(String::new())), false);

        assert_eq!(title(&edits, &tracks, 0), None);
    }

    #[test]
    fn going_back_to_the_files_value_is_no_change() {
        let tracks = [track("a")];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0], &renamed("New"), false);
        edits.edit(&tracks, [0], &renamed("a"), false);

        assert_eq!(edits.modified_count(), 0);
        assert!(edits.can_undo());
    }

    #[test]
    fn an_edit_that_changes_nothing_stays_out_of_the_history() {
        let tracks = [track("a")];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0], &renamed("a"), false);

        assert!(!edits.can_undo());
    }

    #[test]
    fn undo_and_redo_walk_the_history() {
        let tracks = [track("a")];
        let mut edits = Edits::default();
        edits.edit(&tracks, [0], &renamed("One"), false);
        edits.edit(&tracks, [0], &renamed("Two"), false);

        edits.undo(&tracks);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("One"));
        edits.undo(&tracks);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("a"));
        assert_eq!(edits.modified_count(), 0);
        edits.redo(&tracks);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("One"));
    }

    #[test]
    fn a_new_edit_forgets_what_could_be_redone() {
        let tracks = [track("a")];
        let mut edits = Edits::default();
        edits.edit(&tracks, [0], &renamed("One"), false);
        edits.undo(&tracks);

        edits.edit(&tracks, [0], &renamed("Two"), false);

        assert!(!edits.can_redo());
    }

    #[test]
    fn revert_brings_back_the_files_tags_and_can_be_undone() {
        let tracks = [track("a"), track("b")];
        let mut edits = Edits::default();
        edits.edit(&tracks, [0, 1], &renamed("New"), false);

        edits.revert(&tracks, [0]);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("a"));
        assert_eq!(edits.modified_count(), 1);

        edits.undo(&tracks);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("New"));
    }

    #[test]
    fn unreadable_tracks_are_left_out() {
        let tracks = [track("a"), unreadable()];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0, 1], &renamed("New"), false);

        assert_eq!(edits.modified_count(), 1);
        assert_eq!(edits.pending(1), None);
    }

    #[test]
    fn typing_goes_on_with_the_same_step() {
        let tracks = [track("a")];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0], &renamed("N"), false);
        edits.edit(&tracks, [0], &renamed("Ne"), true);
        edits.edit(&tracks, [0], &renamed("New"), true);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("New"));

        edits.undo(&tracks);
        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("a"));
        assert!(!edits.can_undo());
    }

    #[test]
    fn typing_back_the_old_value_leaves_no_step() {
        let tracks = [track("a")];
        let mut edits = Edits::default();

        edits.edit(&tracks, [0], &renamed("New"), false);
        edits.edit(&tracks, [0], &renamed("a"), true);

        assert_eq!(edits.modified_count(), 0);
        assert!(!edits.can_undo());
    }

    #[test]
    fn another_field_starts_a_new_step() {
        let tracks = [track("a")];
        let mut edits = Edits::default();
        edits.edit(&tracks, [0], &renamed("New"), false);

        edits.edit(&tracks, [0], &Edit::Year(Some(2024)), true);
        edits.undo(&tracks);

        assert_eq!(title(&edits, &tracks, 0).as_deref(), Some("New"));
    }

    #[test]
    fn modified_fields_are_those_that_differ_from_the_file() {
        let tracks = [track("a"), track("b")];
        let mut edits = Edits::default();
        edits.edit(&tracks, [0], &renamed("New"), false);
        edits.edit(&tracks, [1], &Edit::Year(Some(2024)), false);

        assert_eq!(
            edits.modified_fields(&tracks, [0]),
            BTreeSet::from([Field::Title])
        );
        assert_eq!(
            edits.modified_fields(&tracks, [0, 1]),
            BTreeSet::from([Field::Title, Field::Year])
        );
    }
}
