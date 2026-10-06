#!/usr/bin/env python3
"""Verify JARHash_Normalized is identical across all 4 configs, per project."""
import csv
import sys
from collections import defaultdict

RESULTS_FILE = sys.argv[1] if len(sys.argv) > 1 else "results-expanded.csv"

with open(RESULTS_FILE, newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

by_proj = defaultdict(list)
for r in rows:
    by_proj[r["Project"]].append(r)

converged, diverged, failed = [], [], []
for proj, rs in sorted(by_proj.items()):
    ok = [r for r in rs if r["Notes"] == "SUCCESS"]
    if len(ok) < 4:
        failed.append(proj)
        continue
    norm_hashes = {r["JARHash_Normalized"] for r in ok}
    raw_hashes = {r["JARHash"] for r in ok}
    if len(norm_hashes) == 1:
        converged.append((proj, len(raw_hashes)))
    else:
        diverged.append((proj, norm_hashes))

print(f"CONVERGED (identical JARHash_Normalized across all 4 configs): {len(converged)}")
for proj, n_raw in converged:
    tag = "  (raw JARHash also matched all 4 -- was never actually sensitive)" if n_raw == 1 else f"  (raw JARHash had {n_raw} distinct values -- normalization fixed a real divergence)"
    print(f"  - {proj}{tag}")

print(f"\nSTILL DIVERGED after normalization: {len(diverged)}")
for proj, hashes in diverged:
    print(f"  - {proj}: {len(hashes)} distinct normalized hashes")

print(f"\nBUILD FAILED (excluded from convergence check): {len(failed)}")
for proj in failed:
    print(f"  - {proj}")
