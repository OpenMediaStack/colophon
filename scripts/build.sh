#!/usr/bin/env bash
# Builds Colophon into build/: ./scripts/build.sh [debug|release], debug by default.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

mode=${1:-debug}
case "$mode" in
debug) flags=(-debug) ;;
release)
	flags=(-o:speed)
	# The oldest macOS the bundle's Info.plist says it runs on, and no console window.
	if [ "$(uname)" = "Darwin" ]; then flags+=(-minimum-os-version:11.0.0); fi
	if is_windows; then flags+=(-subsystem:windows); fi
	;;
*)
	echo "usage: $0 [debug|release]" >&2
	exit 2
	;;
esac

mkdir -p build
out=build/colophon
if is_windows; then
	out=build/colophon.exe
	cp "$(sdl3_dll)" build/
	flags+=(-resource:packaging/windows/colophon.rc)
fi
# shellcheck disable=SC2046
odin build src/app -out:"$out" "${ODIN_FLAGS[@]}" "${flags[@]}" $(linker_flags)
echo "$out"
