#!/usr/bin/env bash
set -Eeuo pipefail
fail() { printf 'Error: %s\n' "$*" >&2; exit 2; }
if (($# == 0)); then exec /usr/bin/dpkg-deb "$@"; fi
case "$1" in
    -b|--build) ;;
    *) exec /usr/bin/dpkg-deb "$@" ;;
esac
(($# == 3)) || fail 'The client packaging shim expects --build PACKAGE OUTPUT'
[[ -n "${RUSTDESK_DEB_STAGE_CLIENT:-}" && "${RUSTDESK_DEB_STAGE_CLIENT:-}" == /* ]] || fail 'Missing absolute client staging directory'
client="$RUSTDESK_DEB_STAGE_CLIENT"
[[ "$(realpath -m -- "$client")" == "$client" ]] || fail 'Client staging directory is redirected'
package=$(realpath -m -- "$2")
output=$(realpath -m -- "$3")
[[ "$package" == "$client/flutter/artifacts/tmpdeb" ]] || fail 'Unexpected client package directory'
[[ "$output" == "$client/artifacts/publish/rustdesk.deb" ]] || fail 'Unexpected client package output'
[[ -d "$package" && -f "$package/DEBIAN/control" ]] || fail 'Client package is incomplete'
[[ "$(realpath -m -- "$package/DEBIAN/control")" == "$package/DEBIAN/control" ]] || fail 'Client control file is redirected'
[[ ! -L "$2" && ! -L "$3" ]] || fail 'Client package or output is a symbolic link'
exec fakeroot bash -c '
    set -Eeuo pipefail
    root=$1
    output=$2
    find "$root" -type d -exec chmod 0755 {} +
    find "$root" -type f -exec chmod 0644 {} +
    for relative in usr/share/rustdesk/rustdesk usr/share/rustdesk/files/polkit DEBIAN/preinst DEBIAN/postinst DEBIAN/prerm DEBIAN/postrm; do
        path="$root/$relative"
        [[ "$(realpath -m -- "$path")" == "$path" && ! -L "$path" ]] || { printf "Refusing redirected executable: %s\n" "$path" >&2; exit 2; }
        if [[ -f "$path" ]]; then chmod 0755 "$path"; fi
    done
    [[ -f "$root/usr/share/rustdesk/rustdesk" ]] || { echo "Missing RustDesk package executable" >&2; exit 2; }
    exec /usr/bin/dpkg-deb -b "$root" "$output"
' _ "$package" "$output"
