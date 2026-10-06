#!/usr/bin/env python3
"""Unzip a nearest/highest jar pair, diff file listings, and for any differing
.class files, disassemble both with javap and diff the disassembly."""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

# Set JAVA17_HOME to a JDK >=17 install, or have javap already on PATH -- see
# README.md.
_java_home = os.environ.get("JAVA17_HOME")
if _java_home:
    JAVAP = str(Path(_java_home) / "bin" / "javap.exe")
else:
    JAVAP = shutil.which("javap") or "javap"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def extract(jar_path, dest):
    with zipfile.ZipFile(jar_path) as z:
        z.extractall(dest)


def javap_disasm(class_file):
    result = subprocess.run(
        [JAVAP, "-c", "-p", "-constants", str(class_file)],
        capture_output=True, text=True
    )
    return result.stdout


def main():
    nearest_jar = Path(sys.argv[1])
    highest_jar = Path(sys.argv[2])

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        n_dir, h_dir = tmp / "nearest", tmp / "highest"
        extract(nearest_jar, n_dir)
        extract(highest_jar, h_dir)

        n_files = {p.relative_to(n_dir).as_posix(): p for p in n_dir.rglob("*") if p.is_file()}
        h_files = {p.relative_to(h_dir).as_posix(): p for p in h_dir.rglob("*") if p.is_file()}

        only_n = sorted(set(n_files) - set(h_files))
        only_h = sorted(set(h_files) - set(n_files))
        common = sorted(set(n_files) & set(h_files))

        print(f"nearest jar: {nearest_jar.name}  ({len(n_files)} files)")
        print(f"highest jar: {highest_jar.name}  ({len(h_files)} files)")
        if only_n:
            print(f"\nFiles only in NEAREST build ({len(only_n)}):")
            for f in only_n[:30]:
                print(f"  - {f}")
        if only_h:
            print(f"\nFiles only in HIGHEST build ({len(only_h)}):")
            for f in only_h[:30]:
                print(f"  + {f}")

        content_diffs = []
        for f in common:
            b1, b2 = n_files[f].read_bytes(), h_files[f].read_bytes()
            if sha256_bytes(b1) != sha256_bytes(b2):
                content_diffs.append(f)

        print(f"\nCommon files with different content ({len(content_diffs)} of {len(common)}):")
        for f in content_diffs:
            print(f"  * {f}")

        # deep-dive: disassemble differing .class files, and show text diff for text files
        for f in content_diffs:
            if f.endswith(".class"):
                print(f"\n--- javap diff: {f} ---")
                d1 = javap_disasm(n_files[f])
                d2 = javap_disasm(h_files[f])
                if d1 == d2:
                    print("  (javap disassembly identical -- difference is in raw bytes only, e.g. constant pool ordering/debug info)")
                else:
                    import difflib
                    diff = list(difflib.unified_diff(d1.splitlines(), d2.splitlines(),
                                                       fromfile="nearest", tofile="highest", lineterm=""))
                    for line in diff[:60]:
                        print(" ", line)
            elif f.endswith((".MF", ".properties", ".xml", ".txt", "pom.properties")):
                print(f"\n--- text diff: {f} ---")
                try:
                    t1 = n_files[f].read_text(encoding="utf-8", errors="replace").splitlines()
                    t2 = h_files[f].read_text(encoding="utf-8", errors="replace").splitlines()
                    import difflib
                    diff = list(difflib.unified_diff(t1, t2, fromfile="nearest", tofile="highest", lineterm=""))
                    for line in diff[:40]:
                        print(" ", line)
                except Exception as e:
                    print(f"  (could not diff as text: {e})")


if __name__ == "__main__":
    main()
