# shellcheck shell=bash
# Shared by the scripts of this folder: sourced, not run.

# The flags every build, check and test uses.
ODIN_FLAGS=(-vet -strict-style -warnings-as-errors)

# Where SDL3's library is: SDL3_LIB_DIR when set, Homebrew's on macOS. Odin ships SDL3 for
# Windows, and Linux finds it in the system's library folders: nothing then.
sdl3_lib_dir() {
	local dir=${SDL3_LIB_DIR:-}
	if [ -z "$dir" ] && [ "$(uname)" = "Darwin" ] && command -v brew >/dev/null; then
		dir="$(brew --prefix)/lib"
	fi
	echo "$dir"
}

# Where the linker finds SDL3.
linker_flags() {
	local dir
	dir=$(sdl3_lib_dir)
	if [ -n "$dir" ]; then
		echo "-extra-linker-flags:-L$dir"
	fi
}

# Odin's root folder, as a path the shell's tools understand.
odin_root() {
	local root
	root=$(odin root)
	if command -v cygpath >/dev/null; then
		root=$(cygpath -u "$root")
	fi
	echo "${root%/}"
}

# The SDL3 library Windows loads at run time: SDL3_DLL when set (the CI takes the
# official release, the same version as Linux), else the one Odin ships.
sdl3_dll() {
	echo "${SDL3_DLL:-$(odin_root)/vendor/sdl3/SDL3.dll}"
}

# The packages under src/, one per folder.
packages() {
	find src -mindepth 1 -maxdepth 1 -type d | sort
}

is_windows() {
	case "$(uname)" in
	MINGW* | MSYS* | CYGWIN*) return 0 ;;
	*) return 1 ;;
	esac
}
