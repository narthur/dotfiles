#!/usr/bin/env python3
"""Pack a cycle's changed files into context-bounded batches for the
file-scoped review agents (#1 CLAUDE.md, #2 bugs, #4 comments).

Those agents review the WHOLE changed file (omission bugs are invisible in a
diff-of-additions). Handing one agent every file dilutes attention (measured:
whole-PR context tanked recall); one agent per file is needless fan-out. So we
greedily bin-pack files under a target line budget and run one instance of each
file-scoped agent per batch, in parallel. Disjoint batches → no cross-instance
dedup needed.

  batch-files.py <diff-range> [--target 1500] [--hardcap 2500]
  batch-files.py --selftest

<diff-range> is anything git diff accepts (origin/main...HEAD, <sha>...HEAD).
Emits JSON: batches (each a list of files under the target), plus oversized
files that must fall back to diff-plus-enclosing-scope so one giant file can't
re-dilute a batch. Small PR -> one batch -> identical to the pre-batching flow.

ponytail: line count is the lazy proxy for a context budget; swap to a token
count only if it ever misjudges. Greedy first-fit-decreasing, not optimal
bin-packing — batches are a soft budget, not a constraint to minimize.
"""
import argparse
import json
import subprocess
import sys


def head_ref(diff_range):
    r = diff_range.strip()
    for sep in ("...", ".."):
        if sep in r:
            return r.split(sep)[-1] or "HEAD"
    return r or "HEAD"


def changed_files(diff_range):
    """Added/modified files (skip deletions — no 'after' file to review)."""
    out = subprocess.run(["git", "diff", "--name-status", diff_range],
                         capture_output=True, text=True).stdout
    files = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status = parts[0]
        if status.startswith("D"):
            continue
        files.append(parts[-1])  # for renames (Rxxx) the new path is last
    return files


def file_lines(head, path):
    p = subprocess.run(["git", "show", f"{head}:{path}"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None  # binary/missing/unreadable
    return p.stdout.count("\n") + (0 if p.stdout.endswith("\n") or not p.stdout else 1)


def pack(sizes, target, hardcap):
    """sizes: list of (path, lines). Returns (batches, oversized_fallback)."""
    fallback = [{"file": p, "lines": n, "mode": "diff+enclosing-scope"}
                for p, n in sizes if n > hardcap]
    solo = [(p, n) for p, n in sizes if target < n <= hardcap]
    normal = sorted([(p, n) for p, n in sizes if n <= target], key=lambda x: -x[1])

    batches = []
    for p, n in normal:  # first-fit-decreasing
        for b in batches:
            if b["lines"] + n <= target:
                b["files"].append(p)
                b["lines"] += n
                break
        else:
            batches.append({"files": [p], "lines": n})
    for p, n in solo:  # each over-target-but-reviewable file gets its own batch
        batches.append({"files": [p], "lines": n})
    return batches, fallback


def _selftest():
    b, f = pack([("a", 900), ("b", 800), ("c", 400), ("d", 100)], 1500, 2500)
    assert all(x["lines"] <= 1500 for x in b), b
    assert sum(len(x["files"]) for x in b) == 4
    assert f == []
    # a file between target and hardcap -> its own batch, whole file kept
    b, f = pack([("big", 2000), ("x", 300)], 1500, 2500)
    assert {"files": ["big"], "lines": 2000} in b
    assert f == []
    # a file over hardcap -> fallback, not a batch
    b, f = pack([("huge", 5000), ("x", 300)], 1500, 2500)
    assert f and f[0]["file"] == "huge" and f[0]["mode"] == "diff+enclosing-scope"
    assert all("huge" not in x["files"] for x in b)
    # empty
    assert pack([], 1500, 2500) == ([], [])
    print("ok")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("diff_range", nargs="?")
    ap.add_argument("--target", type=int, default=1500,
                    help="line budget per file-scoped agent batch")
    ap.add_argument("--hardcap", type=int, default=2500,
                    help="a file bigger than this falls back to diff+enclosing scope")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        _selftest()
        return 0
    if not args.diff_range:
        ap.error("diff_range is required")

    head = head_ref(args.diff_range)
    sizes, unreadable = [], []
    for path in changed_files(args.diff_range):
        n = file_lines(head, path)
        (sizes if n is not None else unreadable).append((path, n))
    batches, fallback = pack(sizes, args.target, args.hardcap)
    print(json.dumps({
        "target": args.target,
        "hardcap": args.hardcap,
        "n_batches": len(batches),
        "batches": batches,
        "oversized_fallback": fallback,
        "unreadable_skipped": [p for p, _ in unreadable],
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
