#!/usr/bin/env bash
set -euo pipefail
_BUILD_ALL=0
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/scripts/build/common.sh"
parse_options "$@"
if ! is_windows; then
    echo 'The Windows Flutter client must be built on Windows. Run build_windows.sh in Git Bash, MSYS2 or Cygwin.' >&2
    exit 1
fi
require_command powershell.exe
require_command cygpath
args=(-NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$BUILD_ROOT/scripts/build/windows.ps1")"
      -ClientSource "$(cygpath -w "$BUILD_ROOT")" -ServerSource "$(cygpath -w "$SERVER_ROOT")"
      -ArtifactsRoot "$(cygpath -w "$ARTIFACTS_ROOT")"
      -ApiSource "$(cygpath -w "$API_ROOT")" -ApiWebSource "$(cygpath -w "$APIWEB_ROOT")" -Only "$ONLY")
((CHECK == 0)) || args+=(-Check)
# Native PowerShell receives Windows paths; MSYS must not rewrite them again.
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' powershell.exe "${args[@]}"
