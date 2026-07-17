#!/usr/bin/env python3
"""Deterministic auto-push eligibility for review-loop Step 14.

Combines loop-state flags (passed in — the orchestrator knows them) with git
facts (checked here) into one push/no-push decision + reason, so the
safety-relevant "never push to the default branch / never push a non-converged
branch / need an upstream" logic isn't re-derived in prose each run.

  push-check.py --clean-exit --gate-state passed --branch feat/x --default-branch main
  push-check.py --selftest

Emits JSON {push: bool, reason: str}. clean_exit / gate_state / unresolved_skip
are loop state; branch / default-branch / upstream are git facts.
"""
import argparse
import json
import subprocess
import sys


def decide(clean_exit, gate_state, unresolved_skip, branch, default_branch, upstream_exists):
    """First failing check wins — mirrors Step 14 'When NOT to auto-push'."""
    if not clean_exit:
        return False, "loop did not exit clean (test failure or cycle limit) — change isn't final"
    if gate_state == "blocked":
        return False, "evidence gate blocked or hit its restart cap"
    if unresolved_skip:
        return False, "a 50-79 finding was skipped without 'remember as dismissal' — unresolved"
    if branch and default_branch and branch == default_branch:
        return False, f"branch is the default branch ({branch}) — never auto-push to it"
    if not upstream_exists:
        return False, "no upstream configured for the branch"
    return True, "clean exit, evidence gate ok, feature branch with upstream"


def _upstream_exists(repo):
    r = subprocess.run(["git", "-C", repo, "rev-parse", "--abbrev-ref", "@{upstream}"],
                       capture_output=True, text=True)
    return r.returncode == 0


def _selftest():
    ok = ("feat/x", "main", True)
    assert decide(True, "passed", False, *ok)[0] is True
    assert decide(True, "skipped", False, *ok)[0] is True
    assert decide(False, "passed", False, *ok)[0] is False           # not converged
    assert decide(True, "blocked", False, *ok)[0] is False           # gate blocked
    assert decide(True, "passed", True, *ok)[0] is False             # unresolved skip
    assert decide(True, "passed", False, "main", "main", True)[0] is False   # default branch
    assert decide(True, "passed", False, "feat/x", "main", False)[0] is False  # no upstream
    print("ok")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--clean-exit", action="store_true")
    ap.add_argument("--gate-state", choices=["passed", "skipped", "blocked"], default="skipped")
    ap.add_argument("--unresolved-skip", action="store_true")
    ap.add_argument("--branch", default="")
    ap.add_argument("--default-branch", default="")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        _selftest()
        return 0
    push, reason = decide(a.clean_exit, a.gate_state, a.unresolved_skip,
                          a.branch, a.default_branch, _upstream_exists(a.repo))
    print(json.dumps({"push": push, "reason": reason}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
