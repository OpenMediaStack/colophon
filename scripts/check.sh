#!/usr/bin/env bash
# What the CI checks: every package with vet and strict style, then formatting.
# odinfmt rewrites what it would change, and the script fails if it changed anything,
# committed or not.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

for package in $(packages); do
	entry=(-no-entry-point)
	if [ "$package" = "src/app" ]; then
		entry=()
	fi
	echo "check $package"
	odin check "$package" "${ODIN_FLAGS[@]}" ${entry[@]+"${entry[@]}"}
done

if command -v odinfmt >/dev/null; then
	sums() { find src -name '*.odin' -exec cksum {} + | sort; }
	before=$(sums)
	odinfmt -path:src -w >/dev/null
	after=$(sums)
	if [ "$before" != "$after" ]; then
		diff <(echo "$before") <(echo "$after") | sed -n 's/^> [0-9]* [0-9]* /formatted: /p' >&2
		echo "odinfmt changed the files above: review them" >&2
		exit 1
	fi
else
	echo "odinfmt not found: formatting not checked" >&2
fi
