#!/usr/bin/env python3
"""Find which preserved jars differ between nearest/highest for each project."""
import hashlib
import sys
from pathlib import Path

BASE = Path(sys.argv[1] if len(sys.argv) > 1 else "diffoscope-work")


def sha256(path):
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def main():
    for proj_dir in sorted(BASE.iterdir()):
        if not proj_dir.is_dir():
            continue
        nearest_dir = proj_dir / "nearest" / "jars"
        highest_dir = proj_dir / "highest" / "jars"
        if not nearest_dir.is_dir() or not highest_dir.is_dir():
            continue
        nearest_jars = {p.name: p for p in nearest_dir.glob("*.jar")}
        highest_jars = {p.name: p for p in highest_dir.glob("*.jar")}
        common = sorted(set(nearest_jars) & set(highest_jars))
        only_nearest = sorted(set(nearest_jars) - set(highest_jars))
        only_highest = sorted(set(highest_jars) - set(nearest_jars))

        diffs = []
        for name in common:
            if sha256(nearest_jars[name]) != sha256(highest_jars[name]):
                diffs.append(name)

        print(f"=== {proj_dir.name} ===  ({len(common)} common jars, {len(diffs)} differ)")
        for d in diffs:
            print(f"  DIFFERS: {d}")
        if only_nearest:
            print(f"  only in nearest: {only_nearest}")
        if only_highest:
            print(f"  only in highest: {only_highest}")
        print()


if __name__ == "__main__":
    main()
