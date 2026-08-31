#!/usr/bin/env python3
"""Threat-model staleness check for review-loop (Step 2b).

The threat model lives at `<git-common-dir>/info/review-loop-threat-model.md`.
Every OBSERVED claim carries a citation pinned to the commit it was verified at:

    - OBSERVED: All /api/v2 routes authenticate in middleware. [src/app.ts:42 @ a1b2c3d]

A claim is STALE when its cited file has changed since that pin. That is a
`git log` away, so staleness is mechanical here rather than a judgment call for
the LLM sweep — the update agent gets an exact worklist instead of "re-read the
diff and guess what's now wrong".

  threat-model.py            # JSON: {path, exists, claims, stale, uncited}
  threat-model.py --selftest

Exit 0 always (informational); callers read `exists` and `stale`.
"""
import json
import re
import subprocess
import sys

# [path:line @ sha] or [path:start-end @ sha] or [path @ sha]
CITATION = re.compile(r"\[([^\]\s:]+)(?::(\d+(?:-\d+)?))?\s*@\s*([0-9a-f]{7,40})\]")


def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def model_path():
    common = git("rev-parse", "--git-common-dir")
    # --git-common-dir, never --git-dir: in a worktree the latter has no info/.
    return f"{common}/info/review-loop-threat-model.md" if common else ""


def parse(text):
    """-> (claims, uncited_observed). claims are {line, path, lines, sha}."""
    claims, uncited = [], 0
    for n, raw in enumerate(text.splitlines(), 1):
        m = CITATION.search(raw)
        if m:
            claims.append({"line": n, "path": m.group(1), "lines": m.group(2), "sha": m.group(3)})
        elif "OBSERVED:" in raw:
            uncited += 1
    return claims, uncited


def stale(claims):
    """A claim is stale when its cited file moved since the pin."""
    out = []
    for c in claims:
        touched = git("log", "--oneline", f"{c['sha']}..HEAD", "--", c["path"])
        if touched:
            out.append({**c, "commits": touched.splitlines()})
    return out


def report():
    path = model_path()
    try:
        text = open(path).read()
    except (OSError, TypeError):
        return {"path": path, "exists": False, "claims": 0, "stale": [], "uncited": 0}
    claims, uncited = parse(text)
    return {
        "path": path,
        "exists": True,
        "claims": len(claims),
        "stale": stale(claims),
        "uncited": uncited,
    }


def _selftest():
    c, u = parse(
        "- OBSERVED: routes authenticate in middleware. [src/app.ts:42 @ a1b2c3d]\n"
        "- OBSERVED: token lifecycle. [src/auth.ts:10-30 @ deadbeefcafe]\n"
        "- OBSERVED: whole-file claim. [src/db.ts @ 0123456]\n"
        "- OBSERVED: no citation on this one, so it is really an inference.\n"
        "- INFERRED: task text is user-authored and untrusted.\n"
    )
    assert len(c) == 3, c
    assert c[0] == {"line": 1, "path": "src/app.ts", "lines": "42", "sha": "a1b2c3d"}, c[0]
    assert c[1]["lines"] == "10-30"
    assert c[2]["lines"] is None
    assert u == 1, u  # the uncited OBSERVED is counted, the INFERRED is not
    assert not CITATION.search("[not a citation]")
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--selftest"]:
        _selftest()
    else:
        print(json.dumps(report(), indent=2))
