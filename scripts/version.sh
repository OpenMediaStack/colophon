#!/usr/bin/env bash
# Prints the version of Colophon, which is VERSION in src/app/window.odin, and fails when
# that is not a version number: 1.2.3, or 1.2.3-rc.1 for a pre-release.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^VERSION :: "\(.*\)"$/\1/p' src/app/window.odin | head -n 1)
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
	echo "VERSION in src/app/window.odin is not a version number: '$version'" >&2
	exit 1
fi
echo "$version"
