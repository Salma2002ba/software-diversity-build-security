#!/usr/bin/env python3
"""For every jar that find-diffs.py flagged as differing, check whether the
difference is CRC-real (actual content changed) or just zip-entry metadata
(timestamps) with matching CRC (content identical)."""
import sys
import zipfile
from pathlib import Path

BASE = Path(sys.argv[1] if len(sys.argv) > 1 else "diffoscope-work")


def check_pair(nearest_jar, highest_jar):
    n = zipfile.ZipFile(nearest_jar)
    h = zipfile.ZipFile(highest_jar)
    n_info = {i.filename: i for i in n.infolist()}
    h_info = {i.filename: i for i in h.infolist()}
    real_diffs = []
    meta_only_diffs = []
    for name in set(n_info) & set(h_info):
        ni, hi = n_info[name], h_info[name]
        if ni.CRC != hi.CRC or ni.file_size != hi.file_size:
            real_diffs.append(name)
        elif (ni.date_time, ni.compress_size) != (hi.date_time, hi.compress_size):
            meta_only_diffs.append(name)
    return real_diffs, meta_only_diffs, set(h_info) - set(n_info), set(n_info) - set(h_info)


def main():
    import hashlib
    for proj_dir in sorted(BASE.iterdir()):
        if not proj_dir.is_dir():
            continue
        nearest_dir, highest_dir = proj_dir / "nearest" / "jars", proj_dir / "highest" / "jars"
        if not nearest_dir.is_dir():
            continue
        for njar in sorted(nearest_dir.glob("*.jar")):
            hjar = highest_dir / njar.name
            if not hjar.exists():
                continue
            if hashlib.sha256(njar.read_bytes()).hexdigest() == hashlib.sha256(hjar.read_bytes()).hexdigest():
                continue  # identical whole file, skip
            real, meta, only_h, only_n = check_pair(njar, hjar)
            print(f"{proj_dir.name} / {njar.name}")
            print(f"  real content diffs (CRC differs): {len(real)} {real[:10]}")
            print(f"  metadata-only diffs (CRC matches, e.g. timestamp): {len(meta)} {meta[:5]}")
            if only_h:
                print(f"  entries only in highest: {sorted(only_h)[:10]}")
            if only_n:
                print(f"  entries only in nearest: {sorted(only_n)[:10]}")
            print()


if __name__ == "__main__":
    main()
