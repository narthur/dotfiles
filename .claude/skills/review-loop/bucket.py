#!/usr/bin/env python3
"""Deterministic score->bucket routing for review-loop (Steps 6d / 8a).

The LLM keeps the judgment — the Haiku score (Step 6), the Step 8a risk
classification, and the always-ask hard rules. This script only does the
mechanical bucketing, so the thresholds land identically every run.

  echo '<findings-json>' | bucket.py
  bucket.py --selftest

Input: JSON array of findings, each {id, agent, score, risk, always_ask}.
- agent "7-structural" or "9-intent" -> always ask (a proposal, never auto-applied), even at >=80.
- agent "5-security-authz" -> always ask (an authz fix locks real users out if wrong).
- security agents -> nothing below 80 is actioned; see SECURITY_AGENTS below.
- always_ask true -> ask (unclear/conflicting fix, or CLAUDE.md / learnings 'always ask about X').
- risk "low"/"high" is consulted only for 50-79; missing risk defaults to ask (safe).
Output: {auto_fix, ask, skip} lists, each entry tagged with its routing reason.
"""
import json
import sys

# Security findings are scored by the Stage-2 false-positive filter, not Haiku
# (score = filter confidence x 10). Upstream's threshold is 8/10, and honoring it
# is most of what buys the low false-positive rate — so security has no 50-79 ask
# band. Sub-80 is skipped here but NOT lost: Step 14 lists it in the report, which
# is the only place a wrongly-dropped security finding can surface for a non-expert.
SECURITY_AGENTS = {"5-security", "5-security-authz"}
SECURITY_FLOOR = 80

ASK_ALWAYS_AGENTS = {"7-structural", "9-intent", "5-security-authz"}


def route(f):
    agent = f.get("agent", "")
    score = int(f.get("score", 0))
    if agent in SECURITY_AGENTS and score < SECURITY_FLOOR:
        return "skip", "security: filter confidence < 8/10 (report-only, Step 14)"
    if agent in ASK_ALWAYS_AGENTS:
        return "ask", f"{agent}: proposal, never auto-applied"
    if f.get("always_ask"):
        return "ask", "hard rule: unclear/conflicting fix or 'always ask' guidance"
    if score >= 80:
        return "auto_fix", "score >= 80"
    if score >= 50:
        if f.get("risk") == "low":
            return "auto_fix", "50-79, low-risk (Step 8a)"
        return "ask", "50-79, high-risk (Step 8a)"
    return "skip", "score < 50"


def bucket(findings):
    out = {"auto_fix": [], "ask": [], "skip": []}
    for f in findings:
        b, reason = route(f)
        out[b].append({**f, "bucket": b, "reason": reason})
    return out


def _selftest():
    assert route({"agent": "2-bugs", "score": 85})[0] == "auto_fix"
    assert route({"agent": "2-bugs", "score": 60, "risk": "low"})[0] == "auto_fix"
    assert route({"agent": "2-bugs", "score": 60, "risk": "high"})[0] == "ask"
    assert route({"agent": "2-bugs", "score": 60})[0] == "ask"          # missing risk -> ask
    assert route({"agent": "2-bugs", "score": 40})[0] == "skip"
    assert route({"agent": "7-structural", "score": 95})[0] == "ask"    # overrides >=80
    assert route({"agent": "9-intent", "score": 90})[0] == "ask"
    assert route({"agent": "2-bugs", "score": 90, "always_ask": True})[0] == "ask"
    # Security: no 50-79 band — sub-80 is report-only, never an interruption.
    assert route({"agent": "5-security", "score": 70, "risk": "low"})[0] == "skip"
    assert route({"agent": "5-security", "score": 60, "risk": "high"})[0] == "skip"
    assert route({"agent": "5-security", "score": 80, "risk": "low"})[0] == "auto_fix"
    # Authz always asks above the floor, and is still floored below it.
    assert route({"agent": "5-security-authz", "score": 100, "risk": "low"})[0] == "ask"
    assert route({"agent": "5-security-authz", "score": 70})[0] == "skip"
    print("ok")


def main(argv):
    if argv and argv[0] == "--selftest":
        _selftest()
        return 0
    print(json.dumps(bucket(json.load(sys.stdin)), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
