//! The command palette's search: which entries hold what is typed, and where.

use std::ops::Range;

use crate::generated::{PaletteEntry, PaletteMatch};

/// The entries that can run and whose name holds `query`, ignoring case, cut around where it
/// first does. Names with a word that starts with it come first, then the others, then the
/// entries whose category holds it; each group keeps the palette's order.
pub(crate) fn matches(
    entries: impl IntoIterator<Item = PaletteEntry>,
    query: &str,
) -> Vec<PaletteMatch> {
    let query = query.trim();
    let mut found: Vec<(u8, PaletteMatch)> = entries
        .into_iter()
        .filter(|entry| entry.enabled)
        .filter_map(|entry| {
            let label = entry.label.as_str();
            let (rank, range) = match find_ignoring_case(label, query) {
                Some(range) if range.start == 0 || label[..range.start].ends_with([' ', '(']) => {
                    (0, range)
                }
                Some(range) => (1, range),
                None => {
                    find_ignoring_case(&entry.category, query)?;
                    (2, 0..0)
                }
            };
            let entry_match = PaletteMatch {
                before: label[..range.start].into(),
                matched: label[range.clone()].into(),
                after: label[range.end..].into(),
                category: entry.category.clone(),
                action: entry.action,
            };
            Some((rank, entry_match))
        })
        .collect();
    found.sort_by_key(|(rank, _)| *rank);
    found
        .into_iter()
        .map(|(_, entry_match)| entry_match)
        .collect()
}

/// Where `query` first appears in `text`, ignoring case, in bytes of `text`. An empty query
/// appears at the start.
fn find_ignoring_case(text: &str, query: &str) -> Option<Range<usize>> {
    let query: Vec<char> = query.chars().flat_map(char::to_lowercase).collect();
    if query.is_empty() {
        return Some(0..0);
    }
    // Each lowercase character of the text, with the bytes of the character it comes from.
    let lowered: Vec<(Range<usize>, char)> = text
        .char_indices()
        .flat_map(|(start, character)| {
            let bytes = start..start + character.len_utf8();
            character
                .to_lowercase()
                .map(move |lowercase| (bytes.clone(), lowercase))
        })
        .collect();
    lowered
        .windows(query.len())
        .find(|window| {
            window
                .iter()
                .map(|(_, character)| *character)
                .eq(query.iter().copied())
        })
        .and_then(|window| Some(window.first()?.0.start..window.last()?.0.end))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::generated::PaletteAction;

    fn entry(label: &str, category: &str) -> PaletteEntry {
        PaletteEntry {
            label: label.into(),
            category: category.into(),
            enabled: true,
            action: PaletteAction::Save,
        }
    }

    fn labels(matches: &[PaletteMatch]) -> Vec<String> {
        matches
            .iter()
            .map(|found| format!("{}[{}]{}", found.before, found.matched, found.after))
            .collect()
    }

    #[test]
    fn a_match_ignores_case_and_keeps_the_text_as_written() {
        assert_eq!(find_ignoring_case("Write ID3v2.4", "id3"), Some(6..9));
        assert_eq!(find_ignoring_case("Réglages", "ÉGL"), Some(1..5));
        assert_eq!(find_ignoring_case("Save", "saved"), None);
        assert_eq!(find_ignoring_case("Save", ""), Some(0..0));
    }

    #[test]
    fn names_with_a_word_that_starts_with_the_text_come_first() {
        let entries = [
            entry("Overview", "Help"),
            entry("Remove ID3v1 from the selected files…", "Tags"),
            entry("Show the Tags column (ID3 versions)", "View"),
            entry("ID3v1 policy: keep where it exists", "Settings"),
            entry("Save", "File"),
        ];

        assert_eq!(
            labels(&matches(entries, "id3")),
            [
                "Remove [ID3]v1 from the selected files…",
                "Show the Tags column ([ID3] versions)",
                "[ID3]v1 policy: keep where it exists",
            ]
        );
    }

    #[test]
    fn a_category_finds_its_entries_after_the_names() {
        let entries = [entry("Hide Sidebar", "View"), entry("Overview", "Help")];

        assert_eq!(
            labels(&matches(entries, "view")),
            ["Over[view]", "[]Hide Sidebar"]
        );
    }

    #[test]
    fn entries_that_cannot_run_are_left_out() {
        let entries = [
            PaletteEntry {
                enabled: false,
                ..entry("Undo", "Edit")
            },
            entry("Redo", "Edit"),
        ];

        assert_eq!(labels(&matches(entries, "")), ["[]Redo"]);
    }
}
