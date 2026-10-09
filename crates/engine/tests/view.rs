use std::collections::HashSet;
use std::path::PathBuf;

use colophon_engine::{Column, Command, Engine, ViewState};

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
fn the_table_shows_the_columns_of_the_mockup_at_start() {
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
            Column::Time,
            Column::Bitrate
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
fn resetting_the_columns_brings_back_those_of_the_mockup() {
    let mut engine = Engine::new();
    engine.execute(Command::ToggleColumn(Column::Tags));
    engine.execute(Command::ToggleColumn(Column::Artist));

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
        Command::ResetColumns,
    ];

    let ids: HashSet<_> = commands.iter().map(Command::id).collect();

    assert_eq!(ids.len(), commands.len());
}
