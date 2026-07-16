#!/usr/bin/env python3
"""Emit only the diff hunks that overlap requested file:line ranges.

Usage: slice-hunks.py <diff-range> <file:start-end> [file:start ...]

<diff-range> is anything `git diff` accepts (e.g. origin/main...HEAD, or
<prev-cycle-sha>...HEAD). Each remaining arg is a path plus a new-file line
range (`start-end`), a single line (`line`), or no range (whole file). Prints
the matching hunks grouped by file so a Haiku scorer sees exactly the code its
findings cite and nothing else — the deterministic version of SKILL Step 6's
"slice the relevant hunks", which the orchestrator otherwise eyeballs.

Self-check: `slice-hunks.py --selftest`.
"""
import re
import subprocess
import sys
from collections import defaultdict


def parse_spec(s):
    path, sep, rng = s.rpartition(":")
    if not sep:  # no colon -> whole file
        return s, None
    if "-" in rng:
        a, b = rng.split("-", 1)
        return path, (int(a), int(b))
    return path, (int(rng), int(rng))


def _overlaps(r, start, end):
    return not (r[1] < start or r[0] > end)


def slice_file(diff_range, path, ranges):
    diff = subprocess.run(
        ["git", "diff", diff_range, "--", path],
        capture_output=True, text=True,
    ).stdout
    if not diff.strip():
        return None

    lines = diff.splitlines()
    first = next((i for i, l in enumerate(lines) if l.startswith("@@")), len(lines))
    header = lines[:first]

    hunks, cur = [], None
    for l in lines[first:]:
        if l.startswith("@@"):
            if cur:
                hunks.append(cur)
            cur = [l]
        elif cur is not None:
            cur.append(l)
    if cur:
        hunks.append(cur)

    want_all = any(r is None for r in ranges)
    keep = []
    for h in hunks:
        m = re.search(r'\+(\d+)(?:,(\d+))?', h[0])
        start = int(m.group(1))
        length = int(m.group(2)) if m.group(2) else 1
        end = start + max(length - 1, 0)
        if want_all or any(r and _overlaps(r, start, end) for r in ranges):
            keep.append(h)
    if not keep:
        return None
    return "\n".join(header + [l for h in keep for l in h])


def _selftest():
    assert parse_spec("a.py:10-20") == ("a.py", (10, 20))
    assert parse_spec("a.py:5") == ("a.py", (5, 5))
    assert parse_spec("a.py") == ("a.py", None)
    assert parse_spec("dir/b.ts:1-2") == ("dir/b.ts", (1, 2))
    assert _overlaps((10, 20), 15, 30)
    assert _overlaps((10, 20), 5, 12)
    assert _overlaps((10, 20), 10, 10)
    assert not _overlaps((10, 20), 21, 30)
    assert not _overlaps((10, 20), 1, 9)
    print("ok")


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        _selftest()
        return 0
    if len(argv) < 3:
        sys.exit("usage: slice-hunks.py <diff-range> <file:start-end> ...")

    diff_range = argv[1]
    wanted = defaultdict(list)
    for spec in argv[2:]:
        path, rng = parse_spec(spec)
        wanted[path].append(rng)

    for path, ranges in wanted.items():
        out = slice_file(diff_range, path, ranges)
        if out:
            print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
