use std::collections::HashSet;
use std::path::PathBuf;

use colophon_engine::{
    Column, ColumnWidths, Command, Edit, Engine, Step, VersionChoice, ViewState,
};

#[test]
fn both_panels_are_visible_at_start() {
    let engine = Engine::new();

    assert!(engine.view().sidebar_visible);
    assert!(engine.view().inspector_visible);
}

#[test]
fn toggling_the_sidebar_leaves_the_inspector_alone() {
    let mut engine = Engine::new();

    engine.execute(Command::ToggleSidebar);

    assert!(!engine.view().sidebar_visible);
    assert!(engine.view().inspector_visible);
}

#[test]
fn toggling_the_inspector_leaves_the_sidebar_alone() {
    let mut engine = Engine::new();

    engine.execute(Command::ToggleInspector);

    assert!(engine.view().sidebar_visible);
    assert!(!engine.view().inspector_visible);
}

#[test]
fn toggling_twice_restores_the_panel() {
    let mut engine = Engine::new();

    engine.execute(Command::ToggleSidebar);
    engine.execute(Command::ToggleSidebar);

    assert_eq!(*engine.view(), ViewState::default());
}

#[test]
fn the_table_shows_the_columns_of_the_mockup_but_the_bitrate_at_start() {
    let engine = Engine::new();

    let shown: Vec<Column> = Column::ALL
        .into_iter()
        .filter(|column| engine.view().columns.contains(*column))
        .collect();

    assert_eq!(
        shown,
        [
            Column::Artist,
            Column::Album,
            Column::Year,
            Column::Genre,
            Column::Time
        ]
    );
}

#[test]
fn toggling_a_column_shows_or_hides_it_alone() {
    let mut engine = Engine::new();

    engine.execute(Command::ToggleColumn(Column::Tags));
    engine.execute(Command::ToggleColumn(Column::Genre));

    let columns = engine.view().columns;
    assert!(columns.contains(Column::Tags));
    assert!(!columns.contains(Column::Genre));
    assert!(columns.contains(Column::Year));
    assert!(!columns.contains(Column::File));
}

#[test]
fn the_table_shares_its_width_until_a_column_is_resized() {
    let mut engine = Engine::new();
    assert_eq!(engine.view().column_widths, None);
    let widths = ColumnWidths {
        title: 300,
        artist: 180,
        ..ColumnWidths::default()
    };

    engine.execute(Command::ResizeColumns(widths));

    assert_eq!(engine.view().column_widths, Some(widths));
}

#[test]
fn resetting_the_columns_brings_back_those_of_the_mockup() {
    let mut engine = Engine::new();
    engine.execute(Command::ToggleColumn(Column::Tags));
    engine.execute(Command::ToggleColumn(Column::Artist));
    engine.execute(Command::ResizeColumns(ColumnWidths::default()));

    engine.execute(Command::ResetColumns);

    assert_eq!(*engine.view(), ViewState::default());
}

#[test]
fn command_ids_are_unique() {
    let commands = [
        Command::ToggleSidebar,
        Command::ToggleInspector,
        Command::OpenFolder(PathBuf::new()),
        Command::StopScan,
        Command::ToggleColumn(Column::Tags),
        Command::ResizeColumns(ColumnWidths::default()),
        Command::ResetColumns,
        Command::Select(0),
        Command::ToggleSelected(0),
        Command::SelectRange(0),
        Command::SelectAll,
        Command::MoveSelection(Step::Down),
        Command::ExtendSelection(Step::Down),
        Command::Edit(Edit::Title(None)),
        Command::ContinueEdit(Edit::Title(None)),
        Command::Undo,
        Command::Redo,
        Command::Revert,
        Command::ChooseVersion(VersionChoice::Id3v1(None)),
        Command::Save,
    ];

    let ids: HashSet<_> = commands.iter().map(Command::id).collect();

    assert_eq!(ids.len(), commands.len());
}
