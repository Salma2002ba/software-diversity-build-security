#!/usr/bin/env python3
"""Filter all-maven-projects.csv down to a manageable, diverse candidate list.

Reproducible Central lists one row per *release*; a project (groupId+artifactId)
usually has many. This collapses to one row per project -- the most recent
release that is confirmed fully reproducible (ko=0, ok>0), built with plain
`mvn` (not gradle/sbt), and doesn't require manual/SHELL intervention.
"""
import csv
import sys
from collections import defaultdict
from packaging import version as pv

IN_FILE = sys.argv[1] if len(sys.argv) > 1 else "all-maven-projects.csv"
OUT_FILE = sys.argv[2] if len(sys.argv) > 2 else "selected-projects.csv"


def parse_version_key(v):
    try:
        return pv.parse(v)
    except Exception:
        return pv.parse("0")


def main():
    rows = []
    with open(IN_FILE, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rows.append(row)

    print(f"Total release rows: {len(rows)}")

    # Filter: mvn tool, no SHELL in command, confirmed fully reproducible
    candidates = []
    for r in rows:
        tool = r.get("tool", "")
        command = r.get("command", "")
        reproducible = r.get("reproducible", "")
        if not tool.startswith("mvn"):
            continue
        if "SHELL" in command.upper():
            continue
        if reproducible != "true":
            continue
        candidates.append(r)

    print(f"Rows after mvn/no-SHELL/reproducible filter: {len(candidates)}")

    # Collapse to one row per project: prefer the highest version number.
    by_project = defaultdict(list)
    for r in candidates:
        key = (r["groupId"], r["artifactId"])
        by_project[key].append(r)

    best_per_project = []
    for key, releases in by_project.items():
        releases.sort(key=lambda r: parse_version_key(r["version"]), reverse=True)
        best_per_project.append(releases[0])

    print(f"Distinct projects with >=1 reproducible mvn release: {len(best_per_project)}")

    best_per_project.sort(key=lambda r: (r["groupId"], r["artifactId"]))

    with open(OUT_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["groupId", "artifactId", "version", "gitRepo",
                                                "gitTag", "jdk", "tool", "command"])
        writer.writeheader()
        for r in best_per_project:
            writer.writerow({k: r[k] for k in writer.fieldnames})

    print(f"Wrote {OUT_FILE}")


if __name__ == "__main__":
    main()
