#!/usr/bin/env python3
"""Drift check for the vendored upstream security-review prompt (Step 2a).

`references/security-review.md` vendors Anthropic's `/security-review` prompt, which is
compiled into the Claude Code binary and therefore updates silently whenever Claude Code
does. Our copy does not. This script makes that drift visible instead of silent.

It extracts the prompt from the installed binary, hashes it, and compares against the
stamp recorded in the vendored file:

    <!-- upstream: claude-code <version> sha256:<hash> -->

  upstream-check.py            # JSON: {vendored_*, current_*, drift, ...}
  upstream-check.py --stamp    # print a fresh stamp line for the installed version
  upstream-check.py --extract  # print the upstream prompt (to diff against ours)
  upstream-check.py --selftest

Drift is not automatically a problem — upstream may have changed something we
deliberately depart from. It is a prompt to go read the diff and decide.
Exit 0 always (informational).
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

VENDORED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "references", "security-review.md")
STAMP = re.compile(r"<!--\s*upstream:\s*claude-code\s+(\S+)\s+sha256:([0-9a-f]{64})\s*-->")

# Anchors bounding the prompt inside the binary's string table. Chosen to be
# distinctive but stable; if BOTH stop matching, upstream restructured the skill
# and this vendoring needs a human look — which is exactly what `found: false` says.
START = "You are a senior security engineer conducting a focused security review"
END = "Your final reply must contain the markdown report and nothing else"


def binary_path():
    cli = shutil.which("claude")
    if not cli:
        return ""
    return os.path.realpath(cli)


def extract(path):
    """Pull the upstream prompt out of the binary's string table."""
    if not path or not os.path.exists(path):
        return ""
    try:
        out = subprocess.run(["strings", path], capture_output=True, text=True, timeout=120).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return slice_between(out.splitlines())


def slice_between(lines):
    start = next((i for i, l in enumerate(lines) if START in l), None)
    if start is None:
        return ""
    end = next((i for i, l in enumerate(lines[start:], start) if END in l), None)
    if end is None:
        return ""
    return "\n".join(lines[start : end + 1]).strip()


def version(path):
    return os.path.basename(path) if path else ""


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest() if text else ""


def vendored_stamp():
    try:
        m = STAMP.search(open(VENDORED).read())
    except OSError:
        return "", ""
    return (m.group(1), m.group(2)) if m else ("", "")


def report():
    path = binary_path()
    text = extract(path)
    cur_ver, cur_hash = version(path), digest(text)
    ven_ver, ven_hash = vendored_stamp()
    return {
        "binary": path,
        "found": bool(text),
        "vendored_version": ven_ver,
        "vendored_sha256": ven_hash,
        "current_version": cur_ver,
        "current_sha256": cur_hash,
        # Unknown (no stamp, or extraction failed) is not drift — it is "cannot tell".
        "drift": bool(text and ven_hash and cur_hash != ven_hash),
        "unstamped": not ven_hash,
    }


def _selftest():
    lines = ["noise", f"x {START} y", "middle", f"z {END} w", "trailing"]
    got = slice_between(lines)
    assert got.startswith("x ") and got.endswith(" w"), got
    assert "middle" in got and "trailing" not in got and "noise" not in got
    assert slice_between(["nothing here"]) == ""
    assert slice_between([f"x {START} y"]) == ""  # start without end -> no partial slice
    m = STAMP.search("<!-- upstream: claude-code 2.1.251 sha256:" + "a" * 64 + " -->")
    assert m and m.group(1) == "2.1.251" and m.group(2) == "a" * 64
    assert digest("") == ""
    print("ok")


if __name__ == "__main__":
    arg = sys.argv[1:2]
    if arg == ["--selftest"]:
        _selftest()
    elif arg == ["--extract"]:
        print(extract(binary_path()))
    elif arg == ["--stamp"]:
        p = binary_path()
        print(f"<!-- upstream: claude-code {version(p)} sha256:{digest(extract(p))} -->")
    else:
        print(json.dumps(report(), indent=2))
