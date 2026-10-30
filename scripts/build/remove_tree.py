#!/usr/bin/env python3
"""Remove owned build trees without following Windows reparse points."""
import argparse
import os
from pathlib import Path
import shutil
import stat


def is_redirect(info):
    return stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400


def remove_tree(path):
    path = Path(path)
    if os.name != "nt":
        shutil.rmtree(path)
        return
    info = path.lstat()
    redirected = is_redirect(info)
    directory = stat.S_ISDIR(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x10
    if directory and not redirected:
        for child in path.iterdir():
            remove_tree(child)
    remove = path.rmdir if directory else path.unlink
    try:
        remove()
    except PermissionError:
        # Never chmod a link: on Windows that can change the cache target instead.
        info = path.lstat()
        if is_redirect(info):
            raise
        path.chmod(info.st_mode | stat.S_IWRITE)
        remove()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    root = Path(os.path.abspath(args.root))
    target = Path(os.path.abspath(args.path))
    if root not in target.parents:
        raise ValueError(f"Deletion is outside the artifact root: {target}")
    for ancestor in (target.parent, *target.parent.parents):
        if ancestor.exists() or ancestor.is_symlink():
            if is_redirect(ancestor.lstat()):
                raise ValueError(f"Redirected artifact parent: {ancestor}")
        if ancestor == root:
            break
    if target.exists() or target.is_symlink():
        remove_tree(target)


if __name__ == "__main__":
    main()
