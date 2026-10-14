#!/usr/bin/env bash
# Lists the strings the code translates, tr("...") and tr_n("...", "...", n), into
# translations/colophon.pot, then brings each .po up to date with msgmerge: new strings
# appear untranslated, strings no longer used become obsolete (#~). Needs gettext.
set -euo pipefail
cd "$(dirname "$0")/.."

# Odin's strings and comments are C's as far as xgettext needs, so pass tr one plain
# literal, never a raw string in backticks nor a sum of strings; a third argument is
# the context (msgctxt) that tells the same English words apart.
find src -name '*.odin' -not -name '*_test.odin' | sort | xgettext \
	--files-from=- \
	--language=C \
	--from-code=UTF-8 \
	--keyword= \
	--keyword=tr:1 \
	--keyword=tr:1,2c \
	--keyword=tr_n:1,2 \
	--keyword=tr_n:1,2,3c \
	--package-name=Colophon \
	--msgid-bugs-address=https://github.com/OpenMediaStack/colophon/issues \
	--copyright-holder="Open Media Stack" \
	--no-wrap \
	--sort-by-file \
	--output=translations/colophon.pot

for po in translations/*.po; do
	msgmerge --update --no-wrap --backup=none --quiet "$po" translations/colophon.pot
done
