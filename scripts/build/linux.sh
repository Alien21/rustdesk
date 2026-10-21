#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CLIENT_SOURCE=
SERVER_SOURCE=
ONLY=all
CHECK=0
CLIENT_RUST=1.75.0
SERVER_RUST=1.99.1
BRIDGE_FLUTTER=3.22.3
BUILD_FLUTTER=3.24.5
VCPKG_COMMIT=9e593bb18ea69cc5095e012465dcd675a822ed0d
CMAKE_VERSION=4.3.0
CARGO_EXPAND_VERSION=1.0.95
FRB_VERSION=1.80.1

usage() {
    cat <<'HELP'
Usage: linux.sh --client-source DIR --server-source DIR [--check] [--only client|server|all]

Builds natively on Debian 13 amd64. Dependencies are checked before any files
are written; missing packages are listed with an explicit apt-get command.
The build uses isolated SDKs, caches and source copies under client/artifacts.
--check only validates the host and sources; it performs no installs or downloads.
HELP
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 2; }
while (($#)); do
    case "$1" in
        --client-source|--server-source|--only)
            (($# >= 2)) || fail "Missing value for $1"
            case "$1" in
                --client-source) CLIENT_SOURCE=$2 ;;
                --server-source) SERVER_SOURCE=$2 ;;
                --only) ONLY=$2 ;;
            esac
            shift 2 ;;
        --check) CHECK=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done
[[ "$ONLY" == client || "$ONLY" == server || "$ONLY" == all ]] || fail '--only must be client, server or all'
[[ -n "$CLIENT_SOURCE" && -d "$CLIENT_SOURCE" ]] || fail '--client-source must name the artifact/source root directory'
[[ -n "$SERVER_SOURCE" ]] || fail '--server-source must be provided'
CLIENT_SOURCE=$(cd -- "$CLIENT_SOURCE" && pwd -P)
SOURCES=()
if [[ "$ONLY" != server ]]; then
    [[ -f "$CLIENT_SOURCE/Cargo.toml" && -f "$CLIENT_SOURCE/build.py" ]] || fail 'Client source is not a RustDesk client checkout'
    SOURCES+=("$CLIENT_SOURCE")
fi
if [[ "$ONLY" != client ]]; then
    [[ -d "$SERVER_SOURCE" && -f "$SERVER_SOURCE/Cargo.toml" && -f "$SERVER_SOURCE/src/main.rs" ]] || fail 'Server source is not a RustDesk server checkout'
    SERVER_SOURCE=$(cd -- "$SERVER_SOURCE" && pwd -P)
    SOURCES+=("$SERVER_SOURCE")
fi
[[ "$(uname -s)" == Linux ]] || fail 'Run this helper inside Debian 13 (native or WSL); Cygwin only launches the outer wrapper'
[[ -r /etc/os-release ]] || fail 'Cannot identify the Linux distribution'
. /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" == 13 ]] || fail 'This preset targets Debian 13 only'
[[ "$(uname -m)" == x86_64 && "$(dpkg --print-architecture)" == amd64 ]] || fail 'This preset targets x86_64/amd64 only'

PACKAGES=()
SECTION=common
while IFS= read -r package || [[ -n "$package" ]]; do
    case "$package" in
        '# [common]') SECTION=common; continue ;;
        '# [client]') SECTION=client; continue ;;
        ''|'#'*) continue ;;
    esac
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || fail "Invalid package list entry: $package"
    [[ "$ONLY" == server && "$SECTION" == client ]] && continue
    PACKAGES+=("$package")
done < "$SCRIPT_DIR/debian-packages.txt"
MISSING=()
for package in "${PACKAGES[@]}"; do
    if [[ "$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)" != installed ]]; then
        MISSING+=("$package")
    fi
done
if ((${#MISSING[@]})); then
    printf 'Missing Debian packages:\n  %s\n' "${MISSING[*]}" >&2
    printf 'Install explicitly, then run the build again:\n  sudo apt-get update\n  sudo apt-get install --no-install-recommends' >&2
    printf ' %q' "${MISSING[@]}" >&2
    printf '\n' >&2
    exit 2
fi
[[ -f "$SCRIPT_DIR/stage.py" ]] || fail "Missing shared source staging helper: $SCRIPT_DIR/stage.py"
[[ "$ONLY" == server || -f "$SCRIPT_DIR/dpkg-deb.sh" ]] || fail "Missing client packaging helper: $SCRIPT_DIR/dpkg-deb.sh"
for source in "${SOURCES[@]}"; do
    [[ "$(git -C "$source" rev-parse --is-inside-work-tree)" == true ]] || fail "Not a Git working tree: $source"
    module="$source/libs/hbb_common"
    [[ -f "$module/Cargo.toml" ]] || fail "Missing hbb_common sources in $source; populate libs/hbb_common first"
    if ! module_top=$(git -C "$module" rev-parse --show-toplevel); then
        fail "Cannot inspect the hbb_common repository in $source"
    fi
    [[ "$(realpath -- "$module_top")" == "$(cd -- "$module" && pwd -P)" ]] || fail "hbb_common is not an initialized repository in $source"
done
if ((CHECK)); then
    printf 'Debian 13 amd64 preflight passed (%s).\nClient Rust: %s; server Rust: %s; Flutter: %s; bridge: %s.\n' "$ONLY" "$CLIENT_RUST" "$SERVER_RUST" "$BUILD_FLUTTER" "$FRB_VERSION"
    printf 'Publish directory: %s/artifacts/publish/linux-x64\n' "$CLIENT_SOURCE"
    exit 0
fi

ARTIFACTS="$CLIENT_SOURCE/artifacts"
CACHE="$ARTIFACTS/cache/linux-x64"
STAGE="$ARTIFACTS/build/linux-x64"
PUBLISH="$ARTIFACTS/publish/linux-x64"
export CARGO_HOME="$CACHE/cargo"
export RUSTUP_HOME="$CACHE/rustup"
export PUB_CACHE="$CACHE/pub"
export XDG_CACHE_HOME="$CACHE/xdg-cache"
export XDG_CONFIG_HOME="$CACHE/xdg-config"
export TMPDIR="$CACHE/tmp"
export CARGO_TARGET_DIR="$CACHE/tool-build"
export CARGO_INCREMENTAL=0
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
export CI=true
for owned_path in "$ARTIFACTS" "$CACHE" "$STAGE" "$PUBLISH" "$TMPDIR"; do
    [[ "$(realpath -m -- "$owned_path")" == "$owned_path" ]] || fail "Refusing redirected artifact path: $owned_path"
done
mkdir -p "$CACHE/downloads" "$CARGO_HOME" "$RUSTUP_HOME" "$PUB_CACHE" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$TMPDIR" "$PUBLISH"
RUN_TMP=$(mktemp -d "$TMPDIR/build.XXXXXXXX")
trap 'status=$?; rm -rf -- "$RUN_TMP"; exit "$status"' EXIT
trap 'printf "Build failed at line %s. No older selected output is retained in %s.\n" "$LINENO" "$PUBLISH" >&2' ERR
if [[ "$ONLY" != server ]]; then
    find "$PUBLISH" -maxdepth 1 \( -type f -o -type l \) -name 'rustdesk-[0-9]*.deb' -delete
fi
if [[ "$ONLY" != client ]]; then
    find "$PUBLISH" -maxdepth 1 \( -type f -o -type l \) \( -name 'rustdesk-server-*.deb' -o -name hbbs -o -name hbbr -o -name rustdesk-utils \) -delete
fi

fetch() { curl --fail --location --retry 3 --output "$2" "$1"; }
if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
    fetch https://sh.rustup.rs "$RUN_TMP/rustup-init.sh"
    sh "$RUN_TMP/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain none
fi
export PATH="$CARGO_HOME/bin:$PATH"
if [[ "$ONLY" != server ]]; then
    rustup toolchain install "$CLIENT_RUST" --profile minimal --component rustfmt
fi
if [[ "$ONLY" != client ]]; then
    rustup toolchain install "$SERVER_RUST" --profile minimal
fi
python3 "$SCRIPT_DIR/stage.py" --client-source "$CLIENT_SOURCE" --server-source "$SERVER_SOURCE" --destination "$STAGE" --only "$ONLY"

flutter_sdk() {
    local version=$1 sdk="$CACHE/flutter-$1" archive expected info
    if [[ -x "$sdk/bin/flutter" && -f "$sdk/.rustdesk-build-version" && "$(cat "$sdk/.rustdesk-build-version")" == "$version" ]]; then
        return
    fi
    fetch https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json "$RUN_TMP/flutter-releases.json"
    info=$(python3 - "$RUN_TMP/flutter-releases.json" "$version" <<'PY'
import json, sys
metadata = json.load(open(sys.argv[1], encoding='utf-8'))
for release in metadata['releases']:
    if (release['version'] == sys.argv[2] and release['channel'] == 'stable'
            and release.get('dart_sdk_arch', 'x64') == 'x64'):
        print(release['archive'] + '\t' + release['sha256'])
        break
else:
    raise SystemExit('Pinned Flutter Linux x64 release not found: ' + sys.argv[2])
PY
)
    IFS=$'\t' read -r archive expected <<< "$info"
    [[ "$archive" == "stable/linux/flutter_linux_$version-stable.tar.xz" && "$expected" =~ ^[0-9a-f]{64}$ ]] || fail 'Unexpected Flutter release metadata'
    local download="$CACHE/downloads/flutter-$version.tar.xz"
    if [[ ! -f "$download" ]] || ! printf '%s  %s\n' "$expected" "$download" | sha256sum --check --status; then
        fetch "https://storage.googleapis.com/flutter_infra_release/releases/$archive" "$RUN_TMP/flutter.tar.xz"
        printf '%s  %s\n' "$expected" "$RUN_TMP/flutter.tar.xz" | sha256sum --check --status
        mv -- "$RUN_TMP/flutter.tar.xz" "$download"
    fi
    mkdir -p "$RUN_TMP/flutter-$version"
    tar -xJf "$download" -C "$RUN_TMP/flutter-$version"
    [[ "$(realpath -m -- "$sdk")" == "$CACHE/flutter-$version" ]] || fail "Refusing to clean a redirected Flutter SDK: $sdk"
    rm -rf -- "$sdk"
    mv -- "$RUN_TMP/flutter-$version/flutter" "$sdk"
    printf '%s\n' "$version" > "$sdk/.rustdesk-build-version"
}

build_client() {
    local client="$STAGE/client" tools="$CACHE/frb-tools" vcpkg="$CACHE/vcpkg" cmake_env="$CACHE/cmake-venv"
    [[ -f "$client/build.py" ]] || fail "stage.py did not create $client"
    if [[ ! -x "$cmake_env/bin/python" ]]; then python3 -m venv "$cmake_env"; fi
    "$cmake_env/bin/python" -m pip install --disable-pip-version-check "cmake==$CMAKE_VERSION"
    export PATH="$cmake_env/bin:$tools/bin:$PATH"
    export RUSTUP_TOOLCHAIN="$CLIENT_RUST"
    export LIBCLANG_PATH
    LIBCLANG_PATH=$(llvm-config --libdir)
    export VCPKG_FORCE_SYSTEM_BINARIES=1
    export VCPKG_DISABLE_METRICS=1
    export VCPKG_ROOT="$vcpkg"
    export VCPKG_DEFAULT_TRIPLET=x64-linux
    export VCPKG_DEFAULT_HOST_TRIPLET=x64-linux
    if [[ ! -d "$vcpkg/.git" ]]; then
        git init "$vcpkg"
        git -C "$vcpkg" remote add origin https://github.com/microsoft/vcpkg
    fi
    # Version overrides need historical port trees, including in reused caches.
    if [[ "$(git -C "$vcpkg" rev-parse --is-shallow-repository)" == true ]]; then
        git -C "$vcpkg" fetch --unshallow origin
    fi
    if [[ "$(git -C "$vcpkg" rev-parse HEAD 2>/dev/null || true)" != "$VCPKG_COMMIT" ]]; then
        git -C "$vcpkg" fetch origin "$VCPKG_COMMIT"
        git -C "$vcpkg" checkout --detach "$VCPKG_COMMIT"
    fi
    if [[ ! -x "$vcpkg/vcpkg" ]]; then "$vcpkg/bootstrap-vcpkg.sh" -disableMetrics; fi
    (cd "$client" && "$vcpkg/vcpkg" install --triplet x64-linux --x-install-root="$vcpkg/installed" --clean-after-build)
    if [[ ! -x "$tools/bin/cargo-expand" ]] || ! "$tools/bin/cargo-expand" --version | grep -qF "$CARGO_EXPAND_VERSION"; then
        cargo install cargo-expand --version "$CARGO_EXPAND_VERSION" --locked --root "$tools" --force
    fi
    if [[ ! -x "$tools/bin/flutter_rust_bridge_codegen" ]] || ! "$tools/bin/flutter_rust_bridge_codegen" --version | grep -qF "$FRB_VERSION"; then
        cargo install flutter_rust_bridge_codegen --version "$FRB_VERSION" --features uuid --locked --root "$tools" --force
    fi
    flutter_sdk "$BRIDGE_FLUTTER"
    flutter_sdk "$BUILD_FLUTTER"
    local bridge_sdk="$CACHE/flutter-$BRIDGE_FLUTTER" build_sdk="$CACHE/flutter-$BUILD_FLUTTER"
    local patch="$client/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff"
    if git -C "$build_sdk" apply --check "$patch"; then
        git -C "$build_sdk" apply "$patch"
    elif ! git -C "$build_sdk" apply --reverse --check "$patch"; then
        fail 'The pinned Flutter SDK does not match the required dropdown patch'
    fi
    cp -- "$client/flutter/pubspec.yaml" "$RUN_TMP/pubspec.yaml"
    if [[ -f "$client/flutter/pubspec.lock" ]]; then cp -- "$client/flutter/pubspec.lock" "$RUN_TMP/pubspec.lock"; fi
    python3 - "$client/flutter/pubspec.yaml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
body = path.read_bytes()
old = b'extended_text: 14.0.0'
if body.count(old) != 1:
    raise SystemExit('The bridge preset expects extended_text: 14.0.0')
path.write_bytes(body.replace(old, b'extended_text: 13.0.0'))
PY
    export PATH="$bridge_sdk/bin:$PATH"
    (cd "$client/flutter" && flutter pub get)
    (cd "$client" && flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h --llvm-path "$(llvm-config --prefix)")
    cp -- "$client/flutter/macos/Runner/bridge_generated.h" "$client/flutter/ios/Runner/bridge_generated.h"
    cp -- "$RUN_TMP/pubspec.yaml" "$client/flutter/pubspec.yaml"
    if [[ -f "$RUN_TMP/pubspec.lock" ]]; then
        cp -- "$RUN_TMP/pubspec.lock" "$client/flutter/pubspec.lock"
    else
        rm -f -- "$client/flutter/pubspec.lock"
    fi
    export PATH="$build_sdk/bin:$PATH"
    export CARGO_TARGET_DIR="$client/artifacts/target"
    export DEB_ARCH=amd64
    (cd "$client/flutter" && flutter config --enable-linux-desktop --no-analytics && flutter pub get)
    local deb_shims="$RUN_TMP/debian-tools"
    mkdir -p "$deb_shims"
    install -m 0755 -- "$SCRIPT_DIR/dpkg-deb.sh" "$deb_shims/dpkg-deb"
    (cd "$client" && RUSTDESK_DEB_STAGE_CLIENT="$client" PATH="$deb_shims:$PATH" python3 build.py --flutter --hwcodec --unix-file-copy-paste)
    local packages=("$client"/artifacts/publish/rustdesk-[0-9]*.deb)
    [[ -f "${packages[0]}" ]] || fail 'Client build did not produce a Debian package'
    for package in "${packages[@]}"; do
        dpkg-deb --info "$package" >/dev/null
        install -m 0644 -- "$package" "$PUBLISH/"
    done
}

build_server() {
    local server="$STAGE/server" package_dir="$STAGE/server-debian"
    [[ -f "$server/Cargo.toml" ]] || fail "stage.py did not create $server"
    [[ "$(realpath -m -- "$package_dir")" == "$STAGE/server-debian" ]] || fail 'Refusing to clean a redirected server package directory'
    rm -rf -- "$package_dir"
    find "$STAGE" -maxdepth 1 \( -type f -o -type l \) -name 'rustdesk-server-*.deb' -delete
    export RUSTUP_TOOLCHAIN="$SERVER_RUST"
    export CARGO_TARGET_DIR="$server/artifacts/target"
    (cd "$server" && cargo build --locked --release --bin hbbs --bin hbbr --bin rustdesk-utils)
    mkdir -p "$package_dir/bin"
    cp -a -- "$server/debian" "$server/systemd" "$package_dir/"
    for binary in hbbs hbbr rustdesk-utils; do
        install -m 0755 -- "$CARGO_TARGET_DIR/release/$binary" "$package_dir/bin/$binary"
    done
    python3 - "$server/Cargo.toml" "$package_dir/debian" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import sys, tomllib
version = tomllib.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))['package']['version']
debian = Path(sys.argv[2])
control = (debian / 'control.tpl').read_text(encoding='utf-8')
if '{{ ARCH }}' not in control:
    raise SystemExit('Server control template has no architecture placeholder')
control = control.replace('Depends: systemd ${misc:Depends}', 'Depends: systemd, ${shlibs:Depends}, ${misc:Depends}')
control = control.replace('Depends: ${misc:Depends}', 'Depends: ${shlibs:Depends}, ${misc:Depends}')
if control.count('${shlibs:Depends}') != 3:
    raise SystemExit('Expected shared-library dependencies for all three server packages')
(debian / 'control').write_text(control.replace('{{ ARCH }}', 'amd64'), encoding='utf-8')
stamp = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
(debian / 'changelog').write_text(
    f'rustdesk-server ({version}) trixie; urgency=medium\n\n'
    '  * Built from the selected local RustDesk working tree.\n\n'
    f' -- RustDesk build <info@rustdesk.com>  {stamp}\n', encoding='utf-8')
PY
    # DrvFS can report every file executable; debhelper uses Perl's stat modes.
    (cd "$package_dir" && fakeroot bash -c '
        set -Eeuo pipefail
        find debian systemd -type f -exec chmod 0644 {} +
        find bin -type f -exec chmod 0755 {} +
        chmod 0755 debian/rules
        for config in debian/*.install; do
            perl -e "exit((-x \$ARGV[0]) ? 1 : 0)" "$config" || { printf "Fakeroot did not normalize %s\n" "$config" >&2; exit 2; }
        done
        debian/rules binary
    ')
    local packages=("$STAGE"/rustdesk-server-*_amd64.deb)
    [[ -f "${packages[0]}" ]] || fail 'Server packaging did not produce Debian packages'
    for package in "${packages[@]}"; do
        dpkg-deb --info "$package" >/dev/null
        install -m 0644 -- "$package" "$PUBLISH/"
    done
    for binary in hbbs hbbr rustdesk-utils; do install -m 0755 -- "$package_dir/bin/$binary" "$PUBLISH/$binary"; done
}

if [[ "$ONLY" != server ]]; then build_client; fi
if [[ "$ONLY" != client ]]; then build_server; fi
printf 'Build completed: %s\n' "$PUBLISH"
