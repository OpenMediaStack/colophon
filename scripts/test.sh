#!/usr/bin/env bash
# Every test of every package, failing on a leak or a bad free.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

mkdir -p build/tests
if is_windows; then
	cp "$(sdl3_dll)" build/tests/
fi

run_tests() {
	local dir=$1
	local name
	name=$(echo "$dir" | tr '/' '-')
	if is_windows; then
		name="$name.exe"
	fi
	echo "test $dir"
	# shellcheck disable=SC2046
	odin test "$dir" "${ODIN_FLAGS[@]}" -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
		-out:"build/tests/$name" $(linker_flags)
}

for package in $(packages); do
	if compgen -G "$package/*_test.odin" >/dev/null; then
		run_tests "$package"
	fi
	if [ -d "$package/tests" ]; then
		run_tests "$package/tests"
	fi
done
