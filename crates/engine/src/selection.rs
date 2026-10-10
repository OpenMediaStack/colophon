use std::collections::BTreeSet;

/// The selected tracks, by their place in the library.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Selection {
    tracks: BTreeSet<usize>,
    /// Where a Shift click or a Shift arrow extends the selection from.
    anchor: Option<usize>,
    /// The track the arrow keys move from, outlined in the table.
    focus: Option<usize>,
}

/// A move of the arrow keys.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Step {
    Up,
    Down,
}

impl Selection {
    pub fn contains(&self, track: usize) -> bool {
        self.tracks.contains(&track)
    }

    pub fn len(&self) -> usize {
        self.tracks.len()
    }

    pub fn is_empty(&self) -> bool {
        self.tracks.is_empty()
    }

    pub fn focus(&self) -> Option<usize> {
        self.focus
    }

    /// The selected tracks, in library order.
    pub fn iter(&self) -> impl Iterator<Item = usize> + '_ {
        self.tracks.iter().copied()
    }

    /// A click: the track alone.
    pub(crate) fn select(&mut self, track: usize) {
        self.tracks = BTreeSet::from([track]);
        self.anchor = Some(track);
        self.focus = Some(track);
    }

    /// A Command click: the track joins the selection or leaves it.
    pub(crate) fn toggle(&mut self, track: usize) {
        if !self.tracks.remove(&track) {
            self.tracks.insert(track);
        }
        self.anchor = Some(track);
        self.focus = Some(track);
    }

    /// A Shift click: every track of `order`, the tracks as the table lists them, from the anchor
    /// to this one, and nothing else. An anchor the table no longer lists starts from this track.
    pub(crate) fn select_range(&mut self, track: usize, order: &[usize]) {
        let place = |track: usize| order.iter().position(|listed| *listed == track);
        let Some(to) = place(track) else {
            return self.select(track);
        };
        let from = self.anchor.and_then(place).unwrap_or(to);
        self.tracks = order[from.min(to)..=from.max(to)].iter().copied().collect();
        if from == to {
            self.anchor = Some(track);
        }
        self.focus = Some(track);
    }

    /// These tracks join the selection.
    pub(crate) fn add(&mut self, tracks: impl IntoIterator<Item = usize>) {
        self.tracks.extend(tracks);
    }

    /// Every track the table lists.
    pub(crate) fn select_all(&mut self, order: &[usize]) {
        self.tracks = order.iter().copied().collect();
    }

    /// An arrow key in `order`, the tracks as the table lists them: the selection moves to the
    /// next track, or grows and shrinks from the anchor when `extend`. It starts from the first or
    /// the last track.
    pub(crate) fn step(&mut self, step: Step, order: &[usize], extend: bool) {
        let Some(last) = order.len().checked_sub(1) else {
            return;
        };
        let place = self
            .focus
            .and_then(|focus| order.iter().position(|listed| *listed == focus));
        let place = match (place, step) {
            (None, Step::Down) => 0,
            (None, Step::Up) => last,
            (Some(place), Step::Up) => place.saturating_sub(1),
            (Some(place), Step::Down) => (place + 1).min(last),
        };
        if extend {
            self.select_range(order[place], order);
        } else {
            self.select(order[place]);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ORDER: [usize; 10] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    const FIVE: [usize; 5] = [0, 1, 2, 3, 4];

    fn selected(selection: &Selection) -> Vec<usize> {
        selection.iter().collect()
    }

    #[test]
    fn a_click_selects_one_track() {
        let mut selection = Selection::default();
        selection.select(3);

        selection.select(5);

        assert_eq!(selected(&selection), [5]);
        assert_eq!(selection.focus(), Some(5));
    }

    #[test]
    fn a_command_click_adds_then_removes_a_track() {
        let mut selection = Selection::default();
        selection.select(1);

        selection.toggle(4);
        assert_eq!(selected(&selection), [1, 4]);

        selection.toggle(1);
        assert_eq!(selected(&selection), [4]);
    }

    #[test]
    fn a_shift_click_selects_from_the_anchor_in_either_direction() {
        let mut selection = Selection::default();
        selection.select(5);

        selection.select_range(8, &ORDER);
        assert_eq!(selected(&selection), [5, 6, 7, 8]);

        selection.select_range(3, &ORDER);
        assert_eq!(selected(&selection), [3, 4, 5]);
        assert_eq!(selection.focus(), Some(3));
    }

    #[test]
    fn a_shift_click_after_a_command_click_starts_from_that_track() {
        let mut selection = Selection::default();
        selection.select(1);
        selection.toggle(6);

        selection.select_range(8, &ORDER);

        assert_eq!(selected(&selection), [6, 7, 8]);
    }

    #[test]
    fn select_all_keeps_the_focus() {
        let mut selection = Selection::default();
        selection.select(2);

        selection.select_all(&[0, 1, 2, 3]);

        assert_eq!(selected(&selection), [0, 1, 2, 3]);
        assert_eq!(selection.focus(), Some(2));
    }

    #[test]
    fn the_arrows_start_from_either_end() {
        let mut down = Selection::default();
        let mut up = Selection::default();

        down.step(Step::Down, &FIVE, false);
        up.step(Step::Up, &FIVE, false);

        assert_eq!(selected(&down), [0]);
        assert_eq!(selected(&up), [4]);
    }

    #[test]
    fn the_arrows_move_the_selection_and_stop_at_the_ends() {
        let mut selection = Selection::default();
        selection.select(1);

        selection.step(Step::Up, &FIVE, false);
        selection.step(Step::Up, &FIVE, false);
        assert_eq!(selected(&selection), [0]);

        selection.select(4);
        selection.step(Step::Down, &FIVE, false);
        assert_eq!(selected(&selection), [4]);
    }

    #[test]
    fn shift_arrows_grow_then_shrink_the_selection() {
        let mut selection = Selection::default();
        selection.select(2);

        selection.step(Step::Down, &FIVE, true);
        selection.step(Step::Down, &FIVE, true);
        assert_eq!(selected(&selection), [2, 3, 4]);

        selection.step(Step::Up, &FIVE, true);
        assert_eq!(selected(&selection), [2, 3]);
    }

    #[test]
    fn a_range_and_the_arrows_follow_the_order_of_the_table() {
        let order = [4, 0, 3, 1];
        let mut selection = Selection::default();
        selection.select(0);

        selection.select_range(1, &order);
        assert_eq!(selected(&selection), [0, 1, 3]);

        selection.select(4);
        selection.step(Step::Down, &order, false);
        assert_eq!(selected(&selection), [0]);
    }

    #[test]
    fn the_arrows_do_nothing_without_tracks() {
        let mut selection = Selection::default();

        selection.step(Step::Down, &[], false);

        assert!(selection.is_empty());
        assert_eq!(selection.focus(), None);
    }
}
