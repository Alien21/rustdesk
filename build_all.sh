#!/usr/bin/env bash
set -euo pipefail
_BUILD_ALL=1
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/scripts/build/common.sh"
parse_options "$@"
platforms=()
case "$PLATFORM" in all) platforms=(windows linux) ;; *) platforms=("$PLATFORM") ;; esac
# Check every selected platform before a lengthy build starts.
for platform in "${platforms[@]}"; do
    bash "$BUILD_ROOT/build_$platform.sh" --check --only "$ONLY"
done
if ((CHECK == 0)); then
    for platform in "${platforms[@]}"; do
        bash "$BUILD_ROOT/build_$platform.sh" --only "$ONLY"
    done
fi
