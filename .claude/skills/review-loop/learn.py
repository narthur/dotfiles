#!/usr/bin/env python3
"""Deterministic file surgery for the review-loop learnings file (Step 11).

The LLM keeps the judgment — whether a finding is novel, which existing entry it
matches, whether to promote to a PATTERN. This script does the mechanical edits
so they're consistent every run: append with today's date, bump an existing
entry's date on a re-match (the freshness signal the Step 2a sweep depends on —
easy for the LLM to forget), and enforce the ~50 cap by evicting oldest
non-PATTERN entries (dismissed one-offs first, then accepted).

  learn.py add   <file> --section dismissed|accepted "<entry text, no date>"
  learn.py bump  <file> "<substring of the matched entry>"
  learn.py prune <file> [--cap 50]
  learn.py --selftest

Entry line: "- YYYY-MM-DD: <text>"; "PATTERN:" in the text marks a durable entry
(never auto-pruned). Sections: "## Dismissed", "## Accepted patterns".
"""
import argparse
import datetime
import re
import sys

ENTRY_RE = re.compile(r'^- (\d{4}-\d{2}-\d{2}): (.*)$')


def today():
    return datetime.date.today().isoformat()


def bump(lines, match, today_str):
    for i, ln in enumerate(lines):
        m = ENTRY_RE.match(ln)
        if m and match in m.group(2):
            lines[i] = f"- {today_str}: {m.group(2)}"
            return lines, True
    return lines, False


def add(lines, section, text, today_str):
    header = "## Dismissed" if section == "dismissed" else "## Accepted patterns"
    entry = f"- {today_str}: {text}"
    for i, ln in enumerate(lines):
        if ln.strip() == header:
            j = i + 1
            while j < len(lines) and lines[j].strip().startswith("<!--"):
                j += 1
            lines.insert(j, entry)
            return lines
    return lines + ["", header, entry]  # section missing -> append it


def prune(lines, cap):
    section = None
    entries = []  # (line_idx, date, is_pattern, section)
    for i, ln in enumerate(lines):
        if ln.startswith("## "):
            section = ln[3:].strip().lower()
        m = ENTRY_RE.match(ln)
        if m:
            entries.append((i, m.group(1), "PATTERN:" in m.group(2), section or ""))
    if len(entries) <= cap:
        return lines, []
    # evict non-PATTERN only; dismissed before accepted; oldest first
    candidates = sorted(
        [e for e in entries if not e[2]],
        key=lambda e: (0 if "dismiss" in e[3] else 1, e[1]))
    drop_idx = {e[0] for e in candidates[:len(entries) - cap]}
    dropped = [lines[i] for i in sorted(drop_idx)]
    kept = [ln for i, ln in enumerate(lines) if i not in drop_idx]
    return kept, dropped


def _selftest():
    t = "2026-07-17"
    base = ["# Review Loop Learnings", "", "## Dismissed", "<!-- c -->",
            "- 2026-01-01: foo bar (declined)", "", "## Accepted patterns", "<!-- c -->"]
    # bump
    out, hit = bump(list(base), "foo bar", t)
    assert hit and out[4] == f"- {t}: foo bar (declined)"
    _, miss = bump(list(base), "nope", t)
    assert miss is False
    # add
    out = add(list(base), "accepted", "new thing (accepted)", t)
    assert f"- {t}: new thing (accepted)" in out
    out = add(list(base), "dismissed", "d thing", t)
    assert out[4] == f"- {t}: d thing"   # inserted right after the <!-- --> comment
    # prune: 4 entries, cap 2 -> drop 2 oldest non-PATTERN, dismissed first
    many = ["## Dismissed", "- 2026-01-01: a", "- 2026-02-01: b",
            "## Accepted patterns", "- 2026-01-15: PATTERN: keep me", "- 2026-03-01: d"]
    kept, dropped = prune(list(many), 2)
    assert "- 2026-01-15: PATTERN: keep me" in kept       # PATTERN survives
    assert "- 2026-01-01: a" in dropped                   # oldest dismissed dropped
    assert len([l for l in kept if ENTRY_RE.match(l)]) == 2
    print("ok")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["add", "bump", "prune"], nargs="?")
    ap.add_argument("file", nargs="?")
    ap.add_argument("text", nargs="?", default="")
    ap.add_argument("--section", choices=["dismissed", "accepted"])
    ap.add_argument("--cap", type=int, default=50)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        _selftest()
        return 0
    if not a.cmd or not a.file:
        ap.error("cmd and file are required")

    with open(a.file) as f:
        lines = f.read().splitlines()

    if a.cmd == "bump":
        lines, hit = bump(lines, a.text, today())
        if not hit:
            sys.exit(f"no entry matched: {a.text!r}")
    elif a.cmd == "add":
        if not a.section:
            ap.error("add requires --section")
        lines = add(lines, a.section, a.text, today())
    elif a.cmd == "prune":
        lines, dropped = prune(lines, a.cap)
        sys.stderr.write(f"pruned {len(dropped)} entr{'y' if len(dropped)==1 else 'ies'}\n")

    with open(a.file, "w") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
