use serde::{Deserialize, Serialize};

/// A column of the track table that the user may hide. Status, number and title always show.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Column {
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

impl Column {
    pub const ALL: [Column; 9] = [
        Column::Artist,
        Column::Album,
        Column::Year,
        Column::Genre,
        Column::Time,
        Column::Bitrate,
        Column::Tags,
        Column::File,
        Column::Folder,
    ];

    /// The columns of the mockup, the bitrate aside. The bitrate, the tag formats and the file's
    /// place are there for whoever wants them.
    fn shown_by_default(self) -> bool {
        !matches!(
            self,
            Column::Bitrate | Column::Tags | Column::File | Column::Folder
        )
    }

    fn bit(self) -> u16 {
        1 << self as u16
    }
}

/// The columns the table shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Columns(u16);

impl Columns {
    pub fn contains(self, column: Column) -> bool {
        self.0 & column.bit() != 0
    }

    pub(crate) fn toggle(&mut self, column: Column) {
        self.0 ^= column.bit();
    }
}

impl Default for Columns {
    fn default() -> Self {
        Column::ALL
            .into_iter()
            .filter(|column| column.shown_by_default())
            .collect()
    }
}

impl FromIterator<Column> for Columns {
    fn from_iter<I: IntoIterator<Item = Column>>(columns: I) -> Self {
        Self(
            columns
                .into_iter()
                .fold(0, |bits, column| bits | column.bit()),
        )
    }
}

/// The width of every column once the user has resized one, in logical pixels. The status and
/// number columns keep theirs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ColumnWidths {
    pub title: u32,
    pub artist: u32,
    pub album: u32,
    pub year: u32,
    pub genre: u32,
    pub time: u32,
    pub bitrate: u32,
    pub tags: u32,
    pub file: u32,
    pub folder: u32,
}
