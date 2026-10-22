#!/usr/bin/env bash
# API/admin builds stay separate from the Rust/Flutter environment.
rd_api_owned() {
    [[ "$2" == "$1/"* && "$(realpath -m -- "$2")" == "$2" ]] || fail "Refusing redirected API artifact path: $2"
}
rd_api_separate() {
    local source=${1%/} namespace=${2%/}
    [[ "$source" != "$namespace" && "$source" != "$namespace/"* && "$namespace" != "$source/"* ]] ||
        fail "API source and artifact namespace must be separate: $1 / $2"
}
rd_api_find_node() {
    local candidate version
    RD_API_NODE=
    RD_API_NPM=
    for candidate in "$RD_API_WEB_ARTIFACTS/cache/linux-tools/node-v22.17.0-linux-x64/bin/node" "$(command -v node || true)"; do
        [[ -x "$candidate" && -x "${candidate%/*}/npm" ]] || continue
        version=$("$candidate" -p 'process.platform + "/" + process.arch + "/" + process.versions.node' 2>/dev/null) || continue
        if [[ "$version" =~ ^linux/x64/([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] &&
            ((BASH_REMATCH[1] > 22 || (BASH_REMATCH[1] == 22 && BASH_REMATCH[2] >= 17))); then
            RD_API_NODE=$candidate
            RD_API_NPM="${candidate%/*}/npm"
            printf 'APIweb Node: %s (%s)\n' "$candidate" "$version"
            return
        fi
    done
    printf 'APIweb Node/npm: build will prepare verified portable Node 22.17.0 in %s/cache/linux-tools.\n' "$RD_API_WEB_ARTIFACTS"
}
rd_api_find_go() {
    local candidate version
    RD_API_GO=
    for candidate in "$RD_API_ARTIFACTS/cache/linux-tools/go-1.23.10/bin/go" "$(command -v go || true)"; do
        [[ -x "$candidate" ]] || continue
        version=$(env -u GOROOT GOENV=off GOTOOLCHAIN=local "$candidate" version 2>/dev/null) || continue
        if [[ "$version" == 'go version go1.23.10 linux/amd64' ]]; then
            RD_API_GO=$candidate
            printf 'API Go: %s (%s)\n' "$candidate" "$version"
            return
        fi
    done
    printf 'API Go: build will prepare verified portable Go 1.23.10 in %s/cache/linux-tools.\n' "$RD_API_ARTIFACTS"
}
rd_api_preflight() {
    local anchor command compiler source
    RD_API_COMPONENT=$1
    RD_API_GO=
    anchor=$(cd -- "$4" && pwd -P)
    RD_API_WEB=${3:-"$anchor/../rustdesk-api-web"}
    RD_API_SOURCE=${2:-"$anchor/../rustdesk-api"}
    RD_API_BASE=${5:-"$anchor/../artifacts"}
    [[ "$RD_API_BASE" == /* ]] || fail '--artifacts-root must be absolute'
    RD_API_BASE=$(realpath -ms -- "$RD_API_BASE")
    RD_API_ARTIFACTS="$RD_API_BASE/rustdesk-api"
    RD_API_WEB_ARTIFACTS="$RD_API_BASE/rustdesk-api-web"
    [[ "$(uname -s)" == Linux && -r /etc/os-release ]] || fail 'API builds require Debian 13 amd64 (native or WSL)'
    local ID VERSION_ID
    . /etc/os-release
    [[ "$ID" == debian && "$VERSION_ID" == 13 && "$(uname -m)" == x86_64 && "$(dpkg --print-architecture)" == amd64 ]] || fail 'API builds target Debian 13 amd64'
    for command in realpath tar; do
        command -v "$command" >/dev/null 2>&1 || fail "API build prerequisite missing: $command"
    done
    [[ "$RD_API_WEB" == /* && -d "$RD_API_WEB" ]] || fail '--apiweb-source must name an absolute APIweb checkout directory'
    RD_API_WEB=$(cd -- "$RD_API_WEB" && pwd -P)
    rd_api_separate "$RD_API_WEB" "$RD_API_WEB_ARTIFACTS"
    [[ -f "$RD_API_WEB/package.json" && -f "$RD_API_WEB/package-lock.json" ]] || fail 'APIweb requires package.json and package-lock.json for npm ci'
    for directory in cache/linux-tools/node-v22.17.0-linux-x64 cache/npm-linux tmp build/linux-amd64/source publish/web; do
        rd_api_owned "$RD_API_WEB_ARTIFACTS" "$RD_API_WEB_ARTIFACTS/$directory"
    done
    rd_api_find_node
    if [[ "$RD_API_COMPONENT" != apiweb ]]; then
        [[ "$RD_API_SOURCE" == /* && -d "$RD_API_SOURCE" ]] || fail '--api-source must name an absolute API checkout directory'
        RD_API_SOURCE=$(cd -- "$RD_API_SOURCE" && pwd -P)
        for source in "$RD_API_SOURCE" "$RD_API_WEB"; do
            rd_api_separate "$source" "$RD_API_ARTIFACTS"
            rd_api_separate "$source" "$RD_API_WEB_ARTIFACTS"
        done
        [[ -f "$RD_API_SOURCE/go.mod" && -f "$RD_API_SOURCE/build.sh" && -f "$RD_API_SOURCE/scripts/build/main.go" ]] || fail 'API source requires go.mod and its isolated build helper'
        for directory in cache/linux-tools/go-1.23.10 cache/go-build cache/go-mod tmp build/linux-amd64 publish/linux-amd64; do
            rd_api_owned "$RD_API_ARTIFACTS" "$RD_API_ARTIFACTS/$directory"
        done
        command -v gcc >/dev/null 2>&1 || fail 'API CGO build requires native Linux gcc'
        compiler=$(gcc -dumpmachine)
        [[ "$compiler" == x86_64*-linux* ]] || fail "API CGO build requires Linux amd64 gcc, found: $compiler"
        rd_api_find_go
        printf 'API CGO compiler: %s (%s)\n' "$(command -v gcc)" "$compiler"
        printf 'API publish directory: %s/publish/linux-amd64\n' "$RD_API_ARTIFACTS"
    fi
    if [[ -z "$RD_API_NODE" || ( "$RD_API_COMPONENT" != apiweb && -z "${RD_API_GO:-}" ) ]]; then
        for command in curl sha256sum; do
            command -v "$command" >/dev/null 2>&1 || fail "Portable API SDK bootstrap requires: $command"
        done
    fi
    printf 'APIweb publish directory: %s/publish/web\n' "$RD_API_WEB_ARTIFACTS"
}
rd_api_sdk() (
    set -Eeuo pipefail
    local owner=$1 name=$2 url=$3 expected=$4 member=$5 destination=$6
    local cache="$owner/cache/linux-tools" temporary download
    rd_api_owned "$owner" "$cache"
    rd_api_owned "$owner" "$cache/downloads"
    rd_api_owned "$owner" "$cache/tmp"
    rd_api_owned "$owner" "$destination"
    mkdir -p "$cache/downloads" "$cache/tmp"
    temporary=$(mktemp -d "$cache/tmp/sdk.XXXXXXXX")
    trap 'rm -rf -- "$temporary"' EXIT
    download="$cache/downloads/$name"
    rd_api_owned "$owner" "$download"
    if [[ ! -f "$download" ]] || ! printf '%s  %s\n' "$expected" "$download" | sha256sum --check --status; then
        curl --fail --location --retry 3 --proto '=https' --output "$temporary/$name" "$url"
        printf '%s  %s\n' "$expected" "$temporary/$name" | sha256sum --check --status
        mv -T -- "$temporary/$name" "$download"
    fi
    tar -xzf "$download" -C "$temporary"
    [[ -d "$temporary/$member/bin" ]] || fail "Portable SDK has an unexpected layout: $name"
    rd_api_owned "$owner" "$destination"
    rm -rf -- "$destination"
    mv -T -- "$temporary/$member" "$destination"
)
rd_api_build() (
    set -Eeuo pipefail
    local stage="$RD_API_WEB_ARTIFACTS/build/linux-amd64/source"
    local publish="$RD_API_WEB_ARTIFACTS/publish/web"
    if [[ -z "$RD_API_NODE" ]]; then
        rd_api_sdk "$RD_API_WEB_ARTIFACTS" node-v22.17.0-linux-x64.tar.gz \
            https://nodejs.org/dist/v22.17.0/node-v22.17.0-linux-x64.tar.gz \
            0fa01328a0f3d10800623f7107fbcd654a60ec178fab1ef5b9779e94e0419e1a \
            node-v22.17.0-linux-x64 "$RD_API_WEB_ARTIFACTS/cache/linux-tools/node-v22.17.0-linux-x64"
        rd_api_find_node
        [[ -n "$RD_API_NODE" ]] || fail 'Portable Linux Node/npm did not start'
    fi
    if [[ "$RD_API_COMPONENT" != apiweb && -z "$RD_API_GO" ]]; then
        rd_api_sdk "$RD_API_ARTIFACTS" go1.23.10.linux-amd64.tar.gz \
            https://go.dev/dl/go1.23.10.linux-amd64.tar.gz \
            535f9f81802499f2a7dbfa70abb8fda3793725fcc29460f719815f6e10b5fd60 \
            go "$RD_API_ARTIFACTS/cache/linux-tools/go-1.23.10"
        rd_api_find_go
        [[ -n "$RD_API_GO" ]] || fail 'Portable Linux Go 1.23.10 did not start'
    fi
    export RUSTDESK_ARTIFACTS_DIR="$RD_API_BASE"
    export PATH="${RD_API_NODE%/*}:$PATH"
    export npm_config_cache="$RD_API_WEB_ARTIFACTS/cache/npm-linux"
    export npm_config_update_notifier=false
    export TMPDIR="$RD_API_WEB_ARTIFACTS/tmp"
    export TMP="$TMPDIR" TEMP="$TMPDIR"
    unset NODE_PATH
    rd_api_owned "$RD_API_WEB_ARTIFACTS" "$stage"
    rd_api_owned "$RD_API_WEB_ARTIFACTS" "$publish"
    mkdir -p "$npm_config_cache" "$TMPDIR"
    rm -rf -- "$stage"
    mkdir -p "$stage"
    tar --exclude=./.git --exclude=./artifacts --exclude=./node_modules --exclude=./dist \
        -C "$RD_API_WEB" -cf - . | tar -xf - -C "$stage"
    (
        cd -- "$stage"
        "$RD_API_NPM" ci --include=dev --include=optional --no-audit --no-fund
        "$RD_API_NPM" run build -- --outDir "$publish" --emptyOutDir
    )
    [[ -s "$publish/index.html" ]] || fail 'APIweb build did not produce publish/web/index.html'
    if [[ "$RD_API_COMPONENT" != apiweb ]]; then
        export PATH="${RD_API_GO%/*}:$PATH"
        export GOOS=linux GOARCH=amd64 CGO_ENABLED=1 GO111MODULE=on GOTOOLCHAIN=local GOENV=off
        export CC=gcc CXX=g++
        export WEB_DIST="$publish"
        export DOCS=${DOCS:-false}
        unset GOROOT GOWORK GOFLAGS CGO_CFLAGS CGO_CPPFLAGS CGO_CXXFLAGS CGO_LDFLAGS
        sh "$RD_API_SOURCE/build.sh"
        [[ -s "$RD_API_ARTIFACTS/publish/linux-amd64/apimain" ]] || fail 'API build did not produce publish/linux-amd64/apimain'
    fi
    printf 'APIweb build completed: %s\n' "$publish"
)
