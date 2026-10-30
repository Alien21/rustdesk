#!/usr/bin/env python3
"""Copy current Git working trees into disposable artifacts build directories."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

# A directly invoked staging helper must also leave its source checkout untouched.
sys.dont_write_bytecode = True
from remove_tree import remove_tree


def git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], check=True, stdout=subprocess.PIPE)
    return result.stdout


def copy_repository(source, destination):
    top = Path(os.fsdecode(git(source, "rev-parse", "--show-toplevel")).strip()).resolve()
    if top != source.resolve():
        raise ValueError(f"Uninitialized submodule or invalid repository: {source}")
    entries = git(source, "ls-files", "--cached", "--others", "--exclude-standard", "--eol", "-z")
    executable = set()
    for entry in git(source, "ls-files", "--stage", "-z").split(b"\0"):
        if entry.startswith(b"100755 "):
            executable.add(os.fsdecode(entry.split(b"\t", 1)[1]))
    seen = set()
    destination.mkdir(parents=True, exist_ok=True)
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        attributes, raw_name = entry.split(b"\t", 1)
        name = os.fsdecode(raw_name)
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Invalid Git path: {name}")
        if name in seen:
            continue
        seen.add(name)
        original, copied = source / relative, destination / relative
        if original.is_dir():
            copy_repository(original, copied)
        elif original.is_file():
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, copied)
            # A Windows checkout may have CRLF. Git identifies text so binary assets stay intact.
            if b"w/crlf" in attributes or b"w/mixed" in attributes:
                copied.write_bytes(copied.read_bytes().replace(b"\r\n", b"\n"))
            if name in executable:
                copied.chmod(copied.stat().st_mode | 0o111)
        elif original.is_symlink():
            raise ValueError(f"Broken source symlink: {original}")
        # Tracked files deleted in the working tree are intentionally absent.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-source", required=True, type=Path)
    parser.add_argument("--server-source", required=True, type=Path)
    parser.add_argument("--artifacts-root", type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--only", choices=("all", "client", "server"), default="all")
    args = parser.parse_args()
    client = args.client_source.resolve()
    artifact_root = args.artifacts_root or Path(os.environ.get("RUSTDESK_ARTIFACTS_DIR", client.parent / "artifacts"))
    artifact_root = Path(os.path.abspath(artifact_root))
    destination = Path(os.path.abspath(args.destination))
    allowed = {artifact_root / "rustdesk" / "build" / name for name in ("linux-x64", "windows-x64")}
    if destination not in allowed:
        raise ValueError("Destination must be rustdesk/build/linux-x64 or rustdesk/build/windows-x64 inside the shared artifacts root")
    selected = (
        ("client", client, destination / "client"),
        ("server", args.server_source.resolve(), artifact_root / "rustdesk-server" / "build" / destination.name / "server"),
    )
    for name, source, target in selected:
        if args.only not in ("all", name):
            continue
        for path in (artifact_root, target):
            for ancestor in (path, *path.parents):
                if ancestor.exists() or ancestor.is_symlink():
                    if ancestor.is_symlink() or getattr(ancestor.lstat(), "st_file_attributes", 0) & 0x400:
                        raise ValueError(f"Artifact path must not be redirected: {ancestor}")
        if not (source / "Cargo.toml").is_file():
            raise ValueError(f"Missing {name} source: {source}")
        # Validate before removing an older build copy.
        git(source, "rev-parse", "--show-toplevel")
        if target == source or source in target.parents or target in source.parents:
            raise ValueError(f"Build directory overlaps the source checkout: {target}")
        if target.is_symlink() or (target.exists() and target.resolve() != target):
            raise ValueError(f"Build directory must not be a symlink: {target}")
        if target.exists():
            remove_tree(target)
        print(f"Staging {name}: {source} -> {target}", flush=True)
        copy_repository(source, target)


if __name__ == "__main__":
    main()
