#!/usr/bin/env bash
set -euo pipefail
_BUILD_ALL=0
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/scripts/build/common.sh"
parse_options "$@"
args=(--client-source "$BUILD_ROOT" --server-source "$SERVER_ROOT" --only "$ONLY")
((CHECK == 0)) || args+=(--check)
if is_windows; then
    require_command wsl.exe
    require_command cygpath
    distro="${RUSTDESK_WSL_DISTRO:-Debian}"
    # Resolve each path inside the selected distribution, including paths with spaces.
    wsl_path() {
        local result
        result=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' wsl.exe --distribution "$distro" --exec wslpath -u "$(cygpath -w "$1")") || {
            printf 'Debian 13 WSL distribution "%s" is unavailable. Install it or run this script directly in Debian 13.\n' "$distro" >&2
            return 1
        }
        printf '%s' "$result" | tr -d '\r'
    }
    linux_root=$(wsl_path "$BUILD_ROOT")
    linux_server=$(wsl_path "$SERVER_ROOT")
    args=(--client-source "$linux_root" --server-source "$linux_server" --only "$ONLY")
    ((CHECK == 0)) || args+=(--check)
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' wsl.exe --distribution "$distro" --exec bash "$linux_root/scripts/build/linux.sh" "${args[@]}"
elif [[ "$(uname -s)" == Linux ]]; then
    bash "$BUILD_ROOT/scripts/build/linux.sh" "${args[@]}"
else
    echo 'The Linux build requires Debian 13 amd64 (or a Debian 13 WSL distribution on Windows).' >&2
    exit 1
fi
