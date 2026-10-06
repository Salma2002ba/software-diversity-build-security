#!/usr/bin/env python3
"""Compute a normalized hash across one or more jars, for comparing build
output across different Maven resolver configurations.

Two normalizations applied, both discovered empirically (see Part 3 of the
report -- manual diffoscope-equivalent analysis of 5 originally "JAR
sensitive" projects found zero real bytecode differences; all of it traced to
these two sources):

1. Hash each zip entry's decompressed CONTENT, not the zip entry itself.
   This sidesteps zip-level metadata (timestamps, compression settings) that
   -Dproject.build.outputTimestamp doesn't fully reach -- e.g. module-info.class
   consistently differed only in its embedded build timestamp (CRC identical)
   despite outputTimestamp being pinned.

2. Exclude files that are *defined* to embed the live dependency-resolution
   result, not compiled application content:
     - META-INF/DEPENDENCIES              (license/dependency notice)
     - META-INF/maven/**                  (plugin.xml, dependencies.properties,
                                            pom.xml/pom.properties echoes, etc.)
   Asking these to stay byte-identical across resolver strategies is asking
   them to stop doing their job; excluding them isolates whether anything
   that actually executes changed.

Usage: normalize-jar-hash.py <jar1> [jar2] [jar3] ...
       normalize-jar-hash.py -            (reads newline-separated jar paths from stdin)
Prints a single sha256 hash to stdout summarizing all given jars together
(sorted by jar path for determinism), or NO_JAR if no jars given.

IMPORTANT for callers: always invoke this as ONE process with ALL jar paths,
never via `xargs` without an explicit single-batch guarantee. xargs silently
splits a long argument list into multiple invocations (its default behavior,
triggered by long lists -- e.g. large multi-module reactors), and each
invocation prints its own hash line, corrupting a CSV row that expects one
line of output. Use the `-` stdin mode from a shell pipeline instead of
`xargs normalize-jar-hash.py`.
"""
import hashlib
import sys
import zipfile
from pathlib import Path

EXCLUDE_EXACT = {"META-INF/DEPENDENCIES"}
EXCLUDE_PREFIXES = ("META-INF/maven/",)


def excluded(name):
    if name in EXCLUDE_EXACT:
        return True
    return any(name.startswith(p) for p in EXCLUDE_PREFIXES)


def normalized_jar_hash(jar_path):
    entries = []
    with zipfile.ZipFile(jar_path) as z:
        for info in z.infolist():
            if info.is_dir() or excluded(info.filename):
                continue
            content_hash = hashlib.sha256(z.read(info.filename)).hexdigest()
            entries.append((info.filename, content_hash))
    entries.sort(key=lambda e: e[0])
    combined = "\n".join(f"{name}:{h}" for name, h in entries)
    return hashlib.sha256(combined.encode("utf-8")).hexdigest()


def main():
    if sys.argv[1:] == ["-"]:
        jar_paths = sorted(line.strip() for line in sys.stdin if line.strip())
    else:
        jar_paths = sorted(sys.argv[1:])
    if not jar_paths:
        print("NO_JAR")
        return
    per_jar = []
    for jp in jar_paths:
        p = Path(jp)
        if not p.is_file():
            continue
        try:
            per_jar.append(f"{p.name}:{normalized_jar_hash(p)}")
        except Exception as e:
            print(f"WARN: could not hash {p}: {e}", file=sys.stderr)
    if not per_jar:
        print("NO_JAR")
        return
    combined = "\n".join(sorted(per_jar))
    print(hashlib.sha256(combined.encode("utf-8")).hexdigest())


if __name__ == "__main__":
    main()
