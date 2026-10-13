#!/usr/bin/env bash
# Builds Colophon into build/: ./scripts/build.sh [debug|release], debug by default.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

mode=${1:-debug}
case "$mode" in
debug) flags=(-debug) ;;
release) flags=(-o:speed) ;;
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
fi
# shellcheck disable=SC2046
odin build src/app -out:"$out" "${ODIN_FLAGS[@]}" "${flags[@]}" $(linker_flags)
echo "$out"
