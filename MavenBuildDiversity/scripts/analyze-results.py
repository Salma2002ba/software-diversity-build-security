#!/usr/bin/env python3
"""Analyze results-expanded.csv: classify each project's sensitivity pattern
and summarize build-time behavior."""
import csv
import statistics
import sys
from collections import defaultdict

RESULTS_FILE = sys.argv[1] if len(sys.argv) > 1 else "results-expanded.csv"


def classify(rows):
    """rows: list of 4 dicts (df/nearest, df/highest, bf/nearest, bf/highest)."""
    by_key = {(r["Collector"], r["Selector"]): r for r in rows}
    tree = {k: v["TreeHash"] for k, v in by_key.items()}
    jar = {k: v["JARHash"] for k, v in by_key.items()}

    def same(d, keys):
        vals = {d[k] for k in keys}
        return len(vals) == 1

    collector_pairs = [(("df", "nearest"), ("bf", "nearest")), (("df", "highest"), ("bf", "highest"))]
    selector_pairs = [(("df", "nearest"), ("df", "highest")), (("bf", "nearest"), ("bf", "highest"))]

    def dimension_changes(d, pairs):
        return any(d[a] != d[b] for a, b in pairs)

    tree_selector_sensitive = dimension_changes(tree, selector_pairs)
    tree_collector_sensitive = dimension_changes(tree, collector_pairs)
    jar_selector_sensitive = dimension_changes(jar, selector_pairs)
    jar_collector_sensitive = dimension_changes(jar, collector_pairs)

    return {
        "tree_selector": tree_selector_sensitive,
        "tree_collector": tree_collector_sensitive,
        "jar_selector": jar_selector_sensitive,
        "jar_collector": jar_collector_sensitive,
        "distinct_trees": len(set(tree.values())),
        "distinct_jars": len(set(jar.values())),
    }


def main():
    rows = []
    with open(RESULTS_FILE, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    by_proj = defaultdict(list)
    for r in rows:
        by_proj[r["Project"]].append(r)

    print("=" * 100)
    print(f"{'Project':<26}{'#OK':<5}{'TreeHash varies with':<24}{'JARHash varies with':<24}{'mean build time (s)'}")
    print("=" * 100)

    summary_counts = defaultdict(int)
    for proj, rs in sorted(by_proj.items()):
        ok = [r for r in rs if r["Notes"] == "SUCCESS"]
        if len(ok) < 4:
            print(f"{proj:<26}{len(ok)}/4  -- BUILD FAILED, excluded from sensitivity analysis")
            continue
        c = classify(ok)
        tree_dims = "+".join([d for d, flag in [("selector", c["tree_selector"]), ("collector", c["tree_collector"])] if flag]) or "none"
        jar_dims = "+".join([d for d, flag in [("selector", c["jar_selector"]), ("collector", c["jar_collector"])] if flag]) or "none"
        times = [int(r["BuildTime_sec"]) for r in ok]
        print(f"{proj:<26}{len(ok)}/4  {tree_dims:<24}{jar_dims:<24}{statistics.mean(times):.1f}")
        summary_counts[(tree_dims, jar_dims)] += 1

    print("\n" + "=" * 100)
    print("PATTERN COUNTS (TreeHash sensitivity -> JARHash sensitivity)")
    print("=" * 100)
    for k, v in sorted(summary_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {k[0]:<24} -> {k[1]:<24} : {v} project(s)")


if __name__ == "__main__":
    main()
