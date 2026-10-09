use std::collections::HashSet;
use std::path::PathBuf;

use colophon_engine::{Command, Engine, ViewState};

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
fn command_ids_are_unique() {
    let commands = [
        Command::ToggleSidebar,
        Command::ToggleInspector,
        Command::OpenFolder(PathBuf::new()),
        Command::StopScan,
    ];

    let ids: HashSet<_> = commands.iter().map(Command::id).collect();

    assert_eq!(ids.len(), commands.len());
}
