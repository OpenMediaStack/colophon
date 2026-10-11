use colophon_library::tags::{Id3v1Policy, Id3v2Version, WritePolicy};
use serde::{Deserialize, Serialize};

use crate::columns::{Column, ColumnOrder, ColumnWidths, TableColumn};
use crate::{ViewState, WindowSize};

/// What Colophon remembers between launches.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Preferences {
    pub view: ViewState,
    /// From 0, silent, to 100, as loud as the file.
    pub volume: u8,
    pub writing: WritePolicy,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            view: ViewState::default(),
            volume: 80,
            writing: WritePolicy::default(),
        }
    }
}

impl Preferences {
    /// Reads preferences written by `to_toml`. What the text lacks keeps its default, and text
    /// that is not such a file gives the defaults.
    pub fn from_toml(text: &str) -> Self {
        let file: File = toml::from_str(text).unwrap_or_default();
        let defaults = Self::default();
        let view = ViewState {
            sidebar_visible: file.sidebar.unwrap_or(defaults.view.sidebar_visible),
            inspector_visible: file.inspector.unwrap_or(defaults.view.inspector_visible),
            columns: file.columns.map_or(defaults.view.columns, |names| {
                names.iter().filter_map(|name| column(name)).collect()
            }),
            column_widths: file.column_widths,
            column_order: file
                .column_order
                .map_or_else(ColumnOrder::default, |names| {
                    ColumnOrder::starting_with(names.iter().filter_map(|name| table_column(name)))
                }),
            developer_mode: file.developer_mode.unwrap_or_default(),
            window_size: file.window,
        };
        let writing = WritePolicy {
            id3v2: match file.id3v2.as_deref() {
                Some("2.3") => Id3v2Version::V2_3,
                _ => defaults.writing.id3v2,
            },
            id3v1: match file.id3v1.as_deref() {
                Some("always") => Id3v1Policy::Always,
                Some("never") => Id3v1Policy::Never,
                _ => defaults.writing.id3v1,
            },
        };
        Self {
            view,
            volume: file
                .volume
                .map_or(defaults.volume, |volume| volume.min(100)),
            writing,
        }
    }

    pub fn to_toml(&self) -> String {
        let view = &self.view;
        let file = File {
            sidebar: Some(view.sidebar_visible),
            inspector: Some(view.inspector_visible),
            columns: Some(
                Column::ALL
                    .into_iter()
                    .filter(|column| view.columns.contains(*column))
                    .map(|column| name(column).to_owned())
                    .collect(),
            ),
            volume: Some(self.volume),
            id3v2: Some(
                match self.writing.id3v2 {
                    Id3v2Version::V2_3 => "2.3",
                    Id3v2Version::V2_2 | Id3v2Version::V2_4 => "2.4",
                }
                .to_owned(),
            ),
            id3v1: Some(
                match self.writing.id3v1 {
                    Id3v1Policy::Keep => "keep",
                    Id3v1Policy::Always => "always",
                    Id3v1Policy::Never => "never",
                }
                .to_owned(),
            ),
            developer_mode: Some(view.developer_mode),
            window: view.window_size,
            column_widths: view.column_widths,
            column_order: Some(
                view.column_order
                    .iter()
                    .map(|column| table_column_name(column).to_owned())
                    .collect(),
            ),
        };
        toml::to_string(&file).unwrap_or_default()
    }
}

/// The preferences file. Every key is optional, so that an older or a hand-edited file still
/// reads.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
struct File {
    sidebar: Option<bool>,
    inspector: Option<bool>,
    columns: Option<Vec<String>>,
    volume: Option<u8>,
    /// The ID3v2 version to write: "2.3" or "2.4".
    id3v2: Option<String>,
    /// Which files get an ID3v1 tag: "keep", "always" or "never".
    id3v1: Option<String>,
    developer_mode: Option<bool>,
    window: Option<WindowSize>,
    column_widths: Option<ColumnWidths>,
    /// Every column but status and number, title included, from left to right.
    column_order: Option<Vec<String>>,
}

/// A column's name in the file.
fn name(column: Column) -> &'static str {
    match column {
        Column::Artist => "artist",
        Column::Album => "album",
        Column::Year => "year",
        Column::Genre => "genre",
        Column::Time => "time",
        Column::Bitrate => "bitrate",
        Column::Tags => "tags",
        Column::File => "file",
        Column::Folder => "folder",
    }
}

fn column(name: &str) -> Option<Column> {
    Column::ALL
        .into_iter()
        .find(|column| self::name(*column) == name)
}

fn table_column_name(column: TableColumn) -> &'static str {
    match column {
        TableColumn::Title => "title",
        TableColumn::Other(column) => name(column),
    }
}

fn table_column(name: &str) -> Option<TableColumn> {
    TableColumn::ALL
        .into_iter()
        .find(|column| table_column_name(*column) == name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn changed() -> Preferences {
        Preferences {
            view: ViewState {
                sidebar_visible: false,
                inspector_visible: true,
                columns: [Column::Artist, Column::Tags].into_iter().collect(),
                column_widths: Some(ColumnWidths {
                    title: 240,
                    artist: 120,
                    ..ColumnWidths::default()
                }),
                column_order: ColumnOrder::starting_with([
                    TableColumn::Other(Column::Album),
                    TableColumn::Title,
                ]),
                developer_mode: true,
                window_size: Some(WindowSize {
                    width: 1440,
                    height: 900,
                }),
            },
            volume: 35,
            writing: WritePolicy {
                id3v2: Id3v2Version::V2_3,
                id3v1: Id3v1Policy::Never,
            },
        }
    }

    #[test]
    fn preferences_read_back_as_written() {
        assert_eq!(Preferences::from_toml(&changed().to_toml()), changed());
        assert_eq!(
            Preferences::from_toml(&Preferences::default().to_toml()),
            Preferences::default()
        );
    }

    #[test]
    fn what_the_file_lacks_keeps_its_default() {
        let preferences = Preferences::from_toml("sidebar = false\n");

        assert!(!preferences.view.sidebar_visible);
        assert_eq!(
            preferences,
            Preferences {
                view: ViewState {
                    sidebar_visible: false,
                    ..ViewState::default()
                },
                ..Preferences::default()
            }
        );
    }

    #[test]
    fn a_file_that_is_not_one_gives_the_defaults() {
        assert_eq!(
            Preferences::from_toml("sidebar = ["),
            Preferences::default()
        );
        assert_eq!(
            Preferences::from_toml("volume = \"loud\""),
            Preferences::default()
        );
    }

    #[test]
    fn unknown_columns_are_left_out_and_the_volume_kept_in_range() {
        let preferences = Preferences::from_toml(
            "columns = [\"album\", \"mood\"]\ncolumn_order = [\"mood\", \"year\"]\nvolume = 250\n",
        );

        assert_eq!(
            preferences.view.columns,
            [Column::Album].into_iter().collect()
        );
        assert_eq!(preferences.volume, 100);
        assert_eq!(
            preferences.view.column_order.iter().next(),
            Some(TableColumn::Other(Column::Year))
        );
    }
}
