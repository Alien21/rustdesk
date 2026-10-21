#!/usr/bin/env bash
# Shared launch options; platform builds run against copies below artifacts/.
set -euo pipefail
BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SERVER_ROOT="${RUSTDESK_SERVER_DIR:-$BUILD_ROOT/../rustdesk-server}"
ONLY=all
CHECK=0
PLATFORM=all
usage() {
    cat <<'HELP'
Usage: bash build_linux.sh|build_windows.sh [--check] [--only all|client|server]
       bash build_all.sh [--check] [--only all|client|server] [--platform all|linux|windows]

Linux: Debian 13 amd64, natively or in WSL (RUSTDESK_WSL_DISTRO=Debian).
Windows: native Windows x64, Visual Studio C++ Desktop tools and Windows SDK.
Outputs: artifacts/publish/linux-x64 and artifacts/publish/windows-x64.
--check verifies prerequisites without downloading tools or compiling.
RUSTDESK_SERVER_DIR overrides the default sibling ../rustdesk-server source.
HELP
}
parse_options() {
    while (($#)); do
        case "$1" in
            --check) CHECK=1; shift ;;
            --only) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; ONLY="$2"; shift 2 ;;
            --platform)
                [[ "${_BUILD_ALL:-0}" == 1 && $# -ge 2 ]] || { usage >&2; exit 2; }
                PLATFORM="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
    done
    case "$ONLY" in all|client|server) ;; *) usage >&2; exit 2 ;; esac
    case "$PLATFORM" in all|linux|windows) ;; *) usage >&2; exit 2 ;; esac
}
is_windows() {
    case "$(uname -s)" in CYGWIN*|MINGW*|MSYS*) return 0 ;; *) return 1 ;; esac
}
require_command() {
    command -v "$1" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$1" >&2; exit 1; }
}
