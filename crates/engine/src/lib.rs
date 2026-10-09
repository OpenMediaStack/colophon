//! Colophon's application state and the commands that change it. No UI types.

/// A user action. The UI turns buttons, menu items and shortcuts into commands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Command {
    ToggleSidebar,
    ToggleInspector,
}

impl Command {
    /// A stable identifier, for the command palette and the shortcut table.
    pub fn id(self) -> &'static str {
        match self {
            Command::ToggleSidebar => "view.toggle_sidebar",
            Command::ToggleInspector => "view.toggle_inspector",
        }
    }
}

/// Which panels the user wants to see. The UI may still hide the sidebar when the window is too narrow.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ViewState {
    pub sidebar_visible: bool,
    pub inspector_visible: bool,
}

impl Default for ViewState {
    fn default() -> Self {
        Self {
            sidebar_visible: true,
            inspector_visible: true,
        }
    }
}

#[derive(Debug, Default)]
pub struct Engine {
    view: ViewState,
}

impl Engine {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn view(&self) -> &ViewState {
        &self.view
    }

    pub fn execute(&mut self, command: Command) {
        match command {
            Command::ToggleSidebar => self.view.sidebar_visible = !self.view.sidebar_visible,
            Command::ToggleInspector => self.view.inspector_visible = !self.view.inspector_visible,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    const ALL_COMMANDS: [Command; 2] = [Command::ToggleSidebar, Command::ToggleInspector];

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
        let ids: HashSet<_> = ALL_COMMANDS.iter().map(|command| command.id()).collect();

        assert_eq!(ids.len(), ALL_COMMANDS.len());
    }
}
