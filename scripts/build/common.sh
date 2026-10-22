#!/usr/bin/env bash
# Shared launch options; platform builds run against copies below artifacts/.
set -euo pipefail
BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*)
        if command -v cygpath >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && canonical_root=$(git -C "$BUILD_ROOT" rev-parse --show-toplevel); then
            BUILD_ROOT=$(cygpath -u "$canonical_root")
        fi ;;
esac
SERVER_ROOT="${RUSTDESK_SERVER_DIR:-$BUILD_ROOT/../rustdesk-server}"
API_ROOT="${RUSTDESK_API_DIR:-$BUILD_ROOT/../rustdesk-api}"
APIWEB_ROOT="${RUSTDESK_API_WEB_DIR:-$BUILD_ROOT/../rustdesk-api-web}"
ARTIFACTS_ROOT="${RUSTDESK_ARTIFACTS_DIR:-$BUILD_ROOT/../artifacts}"
ONLY=all
CHECK=0
PLATFORM=all
usage() {
    cat <<'HELP'
Usage: bash build_linux.sh|build_windows.sh [--check] [--only all|client|server|api|apiweb]
       bash build_all.sh [--check] [--only all|client|server|api|apiweb] [--platform all|linux|windows]

Linux: Debian 13 amd64, natively or in WSL (RUSTDESK_WSL_DISTRO=Debian).
Windows: native Windows x64, Visual Studio C++ Desktop tools and Windows SDK.
Outputs: ../artifacts/rustdesk/publish/linux-x64 and windows-x64.
--artifacts-root DIR or RUSTDESK_ARTIFACTS_DIR selects the shared artifacts root.
--check verifies prerequisites without downloading tools or compiling.
RUSTDESK_SERVER_DIR overrides the default sibling ../rustdesk-server source.
RUSTDESK_API_DIR and RUSTDESK_API_WEB_DIR override the API/frontend sources.
api builds the frontend and API; apiweb builds only the static administration.
API/frontend outputs use rustdesk-api and rustdesk-api-web below the shared root.
HELP
}
parse_options() {
    while (($#)); do
        case "$1" in
            --check) CHECK=1; shift ;;
            --only) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; ONLY="$2"; shift 2 ;;
            --artifacts-root) [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }; ARTIFACTS_ROOT="$2"; shift 2 ;;
            --platform)
                [[ "${_BUILD_ALL:-0}" == 1 && $# -ge 2 ]] || { usage >&2; exit 2; }
                PLATFORM="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
    done
    case "$ONLY" in all|client|server|api|apiweb) ;; *) usage >&2; exit 2 ;; esac
    case "$PLATFORM" in all|linux|windows) ;; *) usage >&2; exit 2 ;; esac
    if is_windows; then
        require_command cygpath
        ARTIFACTS_ROOT=$(cygpath -u "$(cygpath -am "$ARTIFACTS_ROOT")")
    fi
    ARTIFACTS_ROOT=$(realpath -ms -- "$ARTIFACTS_ROOT")
    export RUSTDESK_ARTIFACTS_DIR="$ARTIFACTS_ROOT"
}
is_windows() {
    case "$(uname -s)" in CYGWIN*|MINGW*|MSYS*) return 0 ;; *) return 1 ;; esac
}
require_command() {
    command -v "$1" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$1" >&2; exit 1; }
}
