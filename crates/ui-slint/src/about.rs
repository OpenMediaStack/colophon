//! What the About dialog lists: the software Colophon ships, each piece under its licenses.

use std::collections::HashMap;

use serde::Deserialize;
use slint::SharedString;

use crate::generated::Notice;

/// The crates Colophon ships and the texts of their licenses, which `cargo about` writes from
/// `about.toml` and `about.hbs` at the root of the repository.
const CRATES: &str = include_str!("../licenses/third-party.json");

/// Slint's license, which `cargo about` leaves out of the crates that ship it.
const SLINT_LICENSE: &str = include_str!("../licenses/LicenseRef-Slint-Royalty-free-2.0.md");
const SLINT_LICENSE_ID: &str = "LicenseRef-Slint-Royalty-free-2.0";

/// The fonts and icons the window draws with: name, license, source and license text.
const ASSETS: [(&str, &str, &str, &str); 3] = [
    (
        "Inter",
        "SIL Open Font License 1.1",
        "https://github.com/rsms/inter",
        include_str!("../ui/fonts/OFL-Inter.txt"),
    ),
    (
        "JetBrains Mono",
        "SIL Open Font License 1.1",
        "https://github.com/JetBrains/JetBrainsMono",
        include_str!("../ui/fonts/OFL-JetBrainsMono.txt"),
    ),
    (
        "Lucide",
        "ISC License",
        "https://github.com/lucide-icons/lucide",
        include_str!("../ui/images/LICENSE-lucide.txt"),
    ),
];

/// Where the MIT text that `cargo about` falls back on, for a crate that ships none, leaves
/// the copyright holders blank.
const BLANK_HOLDERS: &str = "<year> <copyright holders>";

#[derive(Deserialize, Default)]
struct Generated {
    licenses: Vec<LicenseText>,
    crates: Vec<Crate>,
}

#[derive(Deserialize)]
struct LicenseText {
    name: String,
    text: String,
    /// The crates under this text, by package id.
    used_by: Vec<String>,
}

#[derive(Deserialize)]
struct Crate {
    id: String,
    name: String,
    version: String,
    /// The license expression of its manifest.
    license: String,
    repository: Option<String>,
    authors: Vec<String>,
}

/// Every piece of software Colophon ships beside its own code, by name.
pub(crate) fn notices() -> Vec<Notice> {
    let generated: Generated = serde_json::from_str(CRATES).unwrap_or_default();
    let shared: Vec<SharedString> = generated
        .licenses
        .iter()
        .map(|license| license.text.as_str().into())
        .collect();
    let mut texts_of: HashMap<&str, Vec<usize>> = HashMap::new();
    for (index, license) in generated.licenses.iter().enumerate() {
        for id in &license.used_by {
            texts_of.entry(id.as_str()).or_default().push(index);
        }
    }
    let crates = generated.crates.iter().map(|krate| {
        let texts = texts_of
            .get(krate.id.as_str())
            .map_or(&[][..], Vec::as_slice);
        let (license, text) = if texts.is_empty() && krate.license.contains(SLINT_LICENSE_ID) {
            (
                "Slint Royalty-free License 2.0".into(),
                SLINT_LICENSE.into(),
            )
        } else {
            let names: Vec<&str> = texts
                .iter()
                .map(|&index| generated.licenses[index].name.as_str())
                .collect();
            let text = match texts {
                [index] => holders_filled(&shared[*index], krate),
                _ => texts
                    .iter()
                    .map(|&index| holders_filled(&shared[index], krate))
                    .collect::<Vec<_>>()
                    .join("\n\n")
                    .into(),
            };
            (names.join(", ").into(), text)
        };
        Notice {
            name: krate.name.as_str().into(),
            version: krate.version.as_str().into(),
            license,
            source: krate.repository.as_deref().unwrap_or_default().into(),
            text,
        }
    });
    let assets = ASSETS.map(|(name, license, source, text)| Notice {
        name: name.into(),
        version: SharedString::new(),
        license: license.into(),
        source: source.into(),
        text: text.into(),
    });
    let mut notices: Vec<Notice> = assets.into_iter().chain(crates).collect();
    notices.sort_by_cached_key(|notice| notice.name.to_lowercase());
    notices
}

/// The text, with the crate's authors as its copyright holders where it leaves them blank.
fn holders_filled(text: &SharedString, krate: &Crate) -> SharedString {
    if !text.contains(BLANK_HOLDERS) {
        return text.clone();
    }
    let authors: Vec<&str> = krate
        .authors
        .iter()
        .map(|author| author.split(" <").next().unwrap_or(author).trim())
        .collect();
    let holders = if authors.is_empty() {
        format!("the authors of {}", krate.name)
    } else {
        authors.join(", ")
    };
    text.replace(BLANK_HOLDERS, &holders).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn notice<'a>(notices: &'a [Notice], name: &str) -> &'a Notice {
        notices
            .iter()
            .find(|notice| notice.name == name)
            .unwrap_or_else(|| panic!("no notice for {name}"))
    }

    #[test]
    fn every_crate_and_asset_has_its_license_text() {
        let notices = notices();

        assert!(notices.len() > 100);
        for notice in &notices {
            assert!(!notice.license.is_empty(), "{} has no license", notice.name);
            assert!(
                !notice.text.trim().is_empty(),
                "{} has no text",
                notice.name
            );
        }
        assert!(
            notices
                .windows(2)
                .all(|pair| pair[0].name.to_lowercase() <= pair[1].name.to_lowercase())
        );
    }

    #[test]
    fn slint_comes_under_its_royalty_free_license() {
        let notices = notices();
        let slint = notice(&notices, "slint");

        assert_eq!(slint.license, "Slint Royalty-free License 2.0");
        assert!(slint.text.contains("AboutSlint"));
    }

    #[test]
    fn the_mpl_crates_say_where_their_source_is() {
        let notices = notices();
        let symphonia = notice(&notices, "symphonia");

        assert_eq!(symphonia.license, "Mozilla Public License 2.0");
        assert!(symphonia.source.starts_with("https://"));
    }

    #[test]
    fn blank_copyright_holders_name_the_authors() {
        let notices = notices();

        assert!(
            notices
                .iter()
                .all(|notice| !notice.text.contains(BLANK_HOLDERS))
        );
        assert!(
            notice(&notices, "lofty")
                .text
                .contains("Copyright (c) Serial")
        );
    }

    #[test]
    fn the_fonts_and_icons_are_listed() {
        let notices = notices();

        assert!(notice(&notices, "Inter").text.contains("Open Font License"));
        assert!(notice(&notices, "Lucide").text.contains("ISC License"));
    }
}
