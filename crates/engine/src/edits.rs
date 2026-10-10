use std::collections::{BTreeMap, BTreeSet};

use colophon_library::Track;
use colophon_library::tags::{
    Cover, Id3v1Version, Id3v2Version, Metadata, TagFormat, TagVersions, Tags, WritePolicy,
    formats_after_write,
};

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
    Disc,
    DiscTotal,
    Genre,
    Comment,
    Cover,
}

impl Field {
    pub const ALL: [Field; 12] = [
        Field::Title,
        Field::Artist,
        Field::AlbumArtist,
        Field::Album,
        Field::Year,
        Field::Track,
        Field::TrackTotal,
        Field::Disc,
        Field::DiscTotal,
        Field::Genre,
        Field::Comment,
        Field::Cover,
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
            Field::Disc => one.disc != other.disc,
            Field::DiscTotal => one.disc_total != other.disc_total,
            Field::Genre => one.genre != other.genre,
            Field::Comment => one.comment != other.comment,
            Field::Cover => one.cover != other.cover,
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
    Disc(Option<u32>),
    DiscTotal(Option<u32>),
    Genre(Option<String>),
    Comment(Option<String>),
    Cover(Option<Cover>),
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
            Edit::Disc(_) => Field::Disc,
            Edit::DiscTotal(_) => Field::DiscTotal,
            Edit::Genre(_) => Field::Genre,
            Edit::Comment(_) => Field::Comment,
            Edit::Cover(_) => Field::Cover,
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
            Edit::Disc(value) => tags.disc = *value,
            Edit::DiscTotal(value) => tags.disc_total = *value,
            Edit::Genre(value) => tags.genre = text(value),
            Edit::Comment(value) => tags.comment = text(value),
            Edit::Cover(value) => tags.cover.clone_from(value),
        }
        // A file holds a total only with its number, both in one frame.
        tags.track_total = tags.track_total.filter(|_| tags.track.is_some());
        tags.disc_total = tags.disc_total.filter(|_| tags.disc.is_some());
    }
}

/// A choice of the version to write one tag of the selected tracks in. `None` removes the tag.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum VersionChoice {
    Id3v2(Option<Id3v2Version>),
    Id3v1(Option<Id3v1Version>),
}

/// What the user wants for a track: its tags, and the tag versions to write them in if the user
/// chose some rather than Colophon's.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Wanted {
    tags: Tags,
    versions: Option<TagVersions>,
}

/// One step of the history: what the user wanted for each track it changed, before and after,
/// and the field it edited, if it came from an edit.
#[derive(Debug, Clone)]
struct Action {
    field: Option<Field>,
    changes: Vec<Change>,
}

#[derive(Debug, Clone)]
struct Change {
    track: usize,
    before: Wanted,
    after: Wanted,
}

/// What the user wants for each track, and the history of how they got there. The history holds
/// values rather than "modified or not", so that undoing an edit already saved brings the old
/// values back as a change to save.
#[derive(Debug, Default)]
pub struct Edits {
    /// The tracks saving would change, with the tags to write into them.
    pending: BTreeMap<usize, Tags>,
    /// The tag versions the user chose, kept once saved so that the next save writes them again.
    chosen: BTreeMap<usize, TagVersions>,
    /// The versions to write the other tracks in.
    policy: WritePolicy,
    undo: Vec<Action>,
    redo: Vec<Action>,
}

impl Edits {
    /// The tags to write into a track, if saving would change its file: new tags, or tags to
    /// write in other versions.
    pub fn pending(&self, track: usize) -> Option<&Tags> {
        self.pending.get(&track)
    }

    /// The tracks saving would change, with the tags to write into them, in library order.
    pub fn modified(&self) -> impl Iterator<Item = (usize, &Tags)> + '_ {
        self.pending.iter().map(|(track, tags)| (*track, tags))
    }

    /// The tag versions to write a track in: those the user chose, or else the policy's.
    pub fn versions(&self, tracks: &[Track], track: usize) -> Option<TagVersions> {
        let saved = saved(tracks, track)?;
        Some(
            self.chosen
                .get(&track)
                .copied()
                .unwrap_or_else(|| TagVersions::following(self.policy, &saved.formats)),
        )
    }

    /// The same, but a track the policy alone would strip of its ID3v1 tag keeps it.
    pub(crate) fn versions_keeping_id3v1(
        &self,
        tracks: &[Track],
        track: usize,
    ) -> Option<TagVersions> {
        let versions = self.versions(tracks, track)?;
        if self.chosen.contains_key(&track) || versions.id3v1.is_some() {
            return Some(versions);
        }
        let id3v1 = saved(tracks, track)?
            .formats
            .iter()
            .find_map(|format| match format {
                TagFormat::Id3v1(version) => Some(*version),
                _ => None,
            });
        Some(TagVersions { id3v1, ..versions })
    }

    /// The tracks with changes that saving would strip of their ID3v1 tag because the policy
    /// never writes one, and not because the user chose so for them.
    pub fn losing_id3v1_to_policy(&self, tracks: &[Track]) -> Vec<usize> {
        self.pending
            .keys()
            .copied()
            .filter(|track| {
                self.versions(tracks, *track) != self.versions_keeping_id3v1(tracks, *track)
            })
            .collect()
    }

    pub fn policy(&self) -> WritePolicy {
        self.policy
    }

    pub(crate) fn set_policy(&mut self, policy: WritePolicy) {
        self.policy = policy;
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
            .filter_map(|track| Some((self.pending(track)?, &saved(tracks, track)?.tags)))
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
        let changes = self.changes(tracks, selected, |wanted, _, _| {
            edit.apply(&mut wanted.tags)
        });
        if continues && self.continue_last(tracks, edit.field(), &changes) {
            return;
        }
        self.record(tracks, Some(edit.field()), changes);
    }

    /// Numbers these tracks in this order from 1, disc by disc, each with the number of tracks
    /// of its disc as the total. A track without a disc number counts as on the first disc.
    pub(crate) fn number(&mut self, tracks: &[Track], ordered: impl IntoIterator<Item = usize>) {
        let mut discs: BTreeMap<u32, Vec<usize>> = BTreeMap::new();
        for track in ordered {
            if let Some(wanted) = self.wanted(tracks, track) {
                discs
                    .entry(wanted.tags.disc.unwrap_or(1))
                    .or_default()
                    .push(track);
            }
        }
        let edits = &*self;
        let changes = discs
            .into_values()
            .flat_map(|disc| {
                let total = u32::try_from(disc.len()).ok();
                disc.into_iter().zip(1..).flat_map(move |(track, number)| {
                    edits.changes(tracks, [track], |wanted, _, _| {
                        wanted.tags.track = Some(number);
                        wanted.tags.track_total = total;
                    })
                })
            })
            .collect();
        self.record(tracks, None, changes);
    }

    /// Writes these tracks in the version chosen for one tag, the other tag keeping its own.
    pub(crate) fn choose_versions(
        &mut self,
        tracks: &[Track],
        selected: impl IntoIterator<Item = usize>,
        choice: VersionChoice,
    ) {
        let changes = self.changes(tracks, selected, |wanted, _, mut versions| {
            match choice {
                VersionChoice::Id3v2(version) => versions.id3v2 = version,
                VersionChoice::Id3v1(version) => versions.id3v1 = version,
            }
            wanted.versions = Some(versions);
        });
        self.record(tracks, None, changes);
    }

    /// What `change` makes of what the user wants for each of these tracks whose tags could be
    /// read. It also gets what the file holds, and the versions the track would be written in.
    fn changes(
        &self,
        tracks: &[Track],
        selected: impl IntoIterator<Item = usize>,
        change: impl Fn(&mut Wanted, &Metadata, TagVersions),
    ) -> Vec<Change> {
        selected
            .into_iter()
            .filter_map(|track| {
                let before = self.wanted(tracks, track)?;
                let mut after = before.clone();
                change(
                    &mut after,
                    saved(tracks, track)?,
                    self.versions(tracks, track)?,
                );
                Some(Change {
                    track,
                    before,
                    after,
                })
            })
            .collect()
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
        let wanted: Vec<(usize, Wanted)> = last
            .changes
            .iter()
            .map(|change| (change.track, change.after.clone()))
            .collect();
        if undone {
            self.undo.pop();
        }
        for (track, wanted) in wanted {
            self.want(tracks, track, wanted);
        }
        self.redo.clear();
        true
    }

    /// Brings these tracks back to their files' tags, written in Colophon's versions.
    pub(crate) fn revert(&mut self, tracks: &[Track], selected: impl IntoIterator<Item = usize>) {
        let changes = self.changes(tracks, selected, |wanted, saved, _| {
            wanted.tags = saved.tags.clone();
            wanted.versions = None;
        });
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
        if let Some(wanted) = self.wanted(tracks, track) {
            self.want(tracks, track, wanted);
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

    /// What the user wants for a track: the pending tags, or else its file's, and the versions
    /// they chose.
    fn wanted(&self, tracks: &[Track], track: usize) -> Option<Wanted> {
        let tags = self.pending(track).or(Some(&saved(tracks, track)?.tags))?;
        Some(Wanted {
            tags: tags.clone(),
            versions: self.chosen.get(&track).copied(),
        })
    }

    /// Takes `wanted` in for a track: it waits to be saved if saving would change the file, with
    /// other tags or in other versions.
    fn want(&mut self, tracks: &[Track], track: usize, wanted: Wanted) {
        match wanted.versions {
            Some(versions) => self.chosen.insert(track, versions),
            None => self.chosen.remove(&track),
        };
        let Some(saved) = saved(tracks, track) else {
            return;
        };
        let rewritten = wanted.versions.is_some_and(|versions| {
            formats_after_write(&saved.formats, &wanted.tags, versions) != saved.formats
        });
        if wanted.tags != saved.tags || rewritten {
            self.pending.insert(track, wanted.tags);
        } else {
            self.pending.remove(&track);
        }
    }
}

/// What a track's file holds, if it could be read.
fn saved(tracks: &[Track], track: usize) -> Option<&Metadata> {
    tracks.get(track)?.metadata.as_ref().ok()
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use colophon_library::tags::{ReadError, TagFormat};

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

    /// A track whose file holds an ID3v2.3 tag.
    fn in_id3v2_3(title: &str) -> Track {
        let mut track = track(title);
        if let Ok(metadata) = &mut track.metadata {
            metadata.formats = vec![TagFormat::Id3v2(Id3v2Version::V2_3)];
        }
        track
    }

    fn unreadable() -> Track {
        Track {
            metadata: Err(ReadError::ReaderPanicked),
            ..track("broken")
        }
    }

    fn title(edits: &Edits, tracks: &[Track], track: usize) -> Option<String> {
        edits
            .wanted(tracks, track)
            .and_then(|wanted| wanted.tags.title)
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
    fn a_total_goes_with_its_number() {
        let tracks = [track("a")];
        let mut edits = Edits::default();
        edits.edit(&tracks, [0], &Edit::Track(Some(3)), false);
        edits.edit(&tracks, [0], &Edit::TrackTotal(Some(12)), false);

        edits.edit(&tracks, [0], &Edit::Track(None), false);

        let tags = edits.pending(0).cloned().unwrap_or_default();
        assert_eq!((tags.track, tags.track_total), (None, None));
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
    fn a_version_that_changes_the_file_waits_to_be_saved() {
        let tracks = [in_id3v2_3("a")];
        let mut edits = Edits::default();

        edits.choose_versions(&tracks, [0], VersionChoice::Id3v2(Some(Id3v2Version::V2_4)));
        assert_eq!(edits.modified_count(), 1);
        assert_eq!(
            edits.versions(&tracks, 0).map(|versions| versions.id3v2),
            Some(Some(Id3v2Version::V2_4))
        );

        edits.undo(&tracks);
        assert_eq!(edits.modified_count(), 0);
    }

    #[test]
    fn the_version_a_file_has_changes_nothing_but_is_kept_for_the_next_save() {
        let tracks = [in_id3v2_3("a")];
        let mut edits = Edits::default();

        edits.choose_versions(&tracks, [0], VersionChoice::Id3v2(Some(Id3v2Version::V2_3)));
        assert_eq!(edits.modified_count(), 0);

        edits.edit(&tracks, [0], &renamed("New"), false);
        assert_eq!(
            edits.versions(&tracks, 0).map(|versions| versions.id3v2),
            Some(Some(Id3v2Version::V2_3))
        );
    }

    #[test]
    fn a_chosen_version_outlives_the_save_that_wrote_it() {
        let mut tracks = [in_id3v2_3("a")];
        let mut edits = Edits::default();
        edits.choose_versions(&tracks, [0], VersionChoice::Id3v2(Some(Id3v2Version::V2_2)));

        if let Ok(metadata) = &mut tracks[0].metadata {
            metadata.formats = vec![TagFormat::Id3v2(Id3v2Version::V2_2)];
        }
        edits.settle(&tracks, 0);

        assert_eq!(edits.modified_count(), 0);
        assert_eq!(
            edits.versions(&tracks, 0).map(|versions| versions.id3v2),
            Some(Some(Id3v2Version::V2_2))
        );
    }

    #[test]
    fn revert_drops_the_chosen_versions() {
        let tracks = [in_id3v2_3("a")];
        let mut edits = Edits::default();
        edits.choose_versions(&tracks, [0], VersionChoice::Id3v1(Some(Id3v1Version::V1_1)));

        edits.revert(&tracks, [0]);

        assert_eq!(edits.modified_count(), 0);
        assert_eq!(
            edits.versions(&tracks, 0),
            Some(TagVersions {
                id3v2: Some(Id3v2Version::V2_4),
                id3v1: None
            })
        );
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
