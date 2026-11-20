#!/usr/bin/env python3
"""
Check docs/topology-matrix.md against the repository.

Every repository path named in a `bundled-tested` or `bundled` row must exist, and every
`guidance-only` row must NOT have one. A renamed or deleted deployment directory then fails
here instead of sending someone to a path that is gone.

    python3 tools/check_topology_matrix.py

Dependency-free so it runs anywhere, including CI.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MATRIX = os.path.join(REPO, "docs", "topology-matrix.md")
STATUS = r"`(bundled-tested|bundled|guidance-only)`"


def main():
    if not os.path.isfile(MATRIX):
        print(f"FAIL  topology matrix not found: {os.path.relpath(MATRIX, REPO)}")
        return 1
    text = open(MATRIX, encoding="utf-8").read()
    failures = []

    # The status cell may carry qualifying prose after the backticked status, e.g.
    # "`bundled-tested` (gateway; dashboard and pump `bundled`)", so do not anchor on a
    # closing pipe.
    rows = re.findall(r"^\|\s*[^|]+\|\s*`([^`]+)`\s*\|[^\n]*?" + STATUS, text, re.M)
    if not rows:
        failures.append("no parseable rows in the topology matrix")

    # Every deployment row (a status and a path cell) must have been parsed. The status
    # legend at the top of the file has no path cell, so it does not count.
    present = [line for line in text.splitlines()
               if line.startswith("|") and re.search(STATUS, line)
               and re.search(r"`[^`]*/[^`]*`", line)]
    if len(rows) != len(present):
        failures.append(f"parsed {len(rows)} of {len(present)} deployment rows")

    seen = set()
    for target, status in rows:
        target = target.strip()
        if target in seen:
            continue
        seen.add(target)
        exists = os.path.exists(os.path.join(REPO, target))
        if status == "guidance-only" and exists:
            failures.append(f"guidance-only row has an artifact: {target}")
        elif status != "guidance-only" and not exists:
            failures.append(f"{status} row names a missing path: {target}")

    for failure in failures:
        print(f"FAIL  {failure}")
    print(f"{len(seen)} distinct paths checked, {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
