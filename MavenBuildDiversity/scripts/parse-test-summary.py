#!/usr/bin/env python3
"""Sum all Maven surefire "Tests run: X, Failures: Y, Errors: Z, Skipped: W"
aggregate lines in a build log (one per reactor module) into totals.

Usage: parse-test-summary.py <log_file>
Prints: TestsRun,Failures,Errors,Skipped
"""
import re
import sys

# Anchored at the end only (after stripping) so this only matches the
# module-level "Results:" aggregate line, not per-test-class lines like
# "Tests run: 5, ..., Skipped: 0, Time elapsed: 0.12 s -- in com.example.FooTest"
# which share the same text but carry extra trailing content. Not anchored at
# the start: real log lines carry a "[INFO] " prefix (or similar) before
# "Tests run:", e.g. "[INFO] Tests run: 29, Failures: 0, Errors: 0, Skipped: 0".
PATTERN = re.compile(
    r"Tests run:\s*(\d+),\s*Failures:\s*(\d+),\s*Errors:\s*(\d+),\s*Skipped:\s*(\d+)\s*$"
)


def main():
    log_path = sys.argv[1]
    run = failures = errors = skipped = 0
    try:
        with open(log_path, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = PATTERN.search(line.strip())
                if m:
                    run += int(m.group(1))
                    failures += int(m.group(2))
                    errors += int(m.group(3))
                    skipped += int(m.group(4))
    except FileNotFoundError:
        pass
    print(f"{run},{failures},{errors},{skipped}")


if __name__ == "__main__":
    main()
