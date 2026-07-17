#!/usr/bin/env python3
"""POC — intent-first (spec-reconciliation) review.

An excellent reviewer models what a PR *should* do from its purpose — features,
steps, edge cases, failure modes, invariants — BEFORE reading the code, then
reconciles that independent model against the implementation. The gap between
"my model says X must happen" and "the code doesn't" is the omission bug that
code-first review is structurally blind to (it's anchored by what the code
already shows).

Two stages, kept in separate agent contexts so stage 2 can't contaminate the
model with the implementation:
  1. SPEC:  intent (+ changed-file names for scope) -> expected-behavior list.
  2. RECON: spec + full code -> omissions / discrepancies / unhandled cases,
            framed as QUESTIONS to the author (not confirmed defects).

PRECONDITION (mirrors the live skill's sequencing): the intent must be accurate
and must reflect the GOAL, not the fixes. Merged-PR descriptions are contaminated
— they document the post-review fixes — so intent comes from redacted review-time
`intents.jsonl` (each entry carries a redaction_note), never the live PR body.

  intent-recon.py --repo ~/code/yourrepo [--only <id>,...] [--repeat N]
                  [--model opus] [--judge-model sonnet]
  intent-recon.py --selftest

Requires the `claude` CLI. Reuses replay.py's hardened helpers.
"""
import argparse
import json
import os
import sys
import tempfile
from collections import defaultdict

from replay import extract_json, run_claude, git, number_lines, JUDGE_TMPL

SPEC_TMPL = """You are reviewing a pull request BEFORE looking at its code. Build an
INDEPENDENT model of what this change must do to be correct and complete. Reason
from purpose only — do NOT guess at or assume the implementation.

PR purpose / intent:
{intent}

Changed files (names only, for scope):
{files}

Enumerate the behaviors this change must satisfy: the features and user-facing
steps, the state transitions, the edge cases, the failure modes, and the
invariants. Think like a careful engineer listing what could be forgotten or go
wrong — especially state that must be reset when inputs change, contracts that
must hold, and error paths that must surface. For each, say why it matters.

Output ONLY a JSON array:
[{{"behavior": "...", "why": "...", "check": "what to verify in the code"}}]"""

RECON_TMPL = """You independently modelled what this PR must do (below). Now reconcile that
model against the ACTUAL implementation and flag the gaps.

Your independent model of expected behavior:
{spec}

Actual change — full contents of the changed files at this revision, then the diff:
{code}

For each expected behavior, decide whether the implementation satisfies it. Flag:
- OMISSION: an expected behavior with no corresponding implementation.
- DISCREPANCY: implemented, but differently than the model expects.
- UNHANDLED: an edge case / failure mode the model raised that the code doesn't handle.
These are QUESTIONS about intent, not confirmed defects — frame each as a question.

Output ONLY a JSON array:
[{{"file": "...", "line_range": "start-end", "kind": "OMISSION|DISCREPANCY|UNHANDLED", "description": "...", "question": "..."}}]
If the implementation fully satisfies the model, output exactly: []"""


def build_code(worktree, repo, base, review, cap=6000):
    files = [f for f in git(repo, "diff", "--name-only", f"{base}..{review}").splitlines() if f.strip()]
    parts, total = [], 0
    for f in files:
        try:
            body = open(os.path.join(worktree, f), encoding="utf-8", errors="replace").read()
        except FileNotFoundError:
            continue  # deleted file
        nl = body.count("\n")
        if total + nl > cap:
            parts.append(f"===== {f} (omitted — context budget) =====")
            continue
        total += nl
        parts.append(f"===== {f} =====\n{number_lines(body)}")
    diff = git(repo, "diff", f"{base}..{review}")
    return "\n\n".join(parts) + "\n\n===== DIFF =====\n" + diff, files


def recon_one(fx, intent, repo, worktree, model, judge_model):
    files_out = [f for f in git(repo, "diff", "--name-only",
                                f"{fx['base_sha']}..{fx['review_sha']}").splitlines() if f.strip()]
    # stage 1 — spec from intent only
    try:
        spec = extract_json(run_claude(
            SPEC_TMPL.format(intent=intent, files="\n".join(files_out)), model, worktree),
            prefer="array")
    except Exception as e:
        return {"status": f"spec-error: {e}", "matched": False}
    # stage 2 — reconcile against code (fresh context)
    code, _ = build_code(worktree, repo, fx["base_sha"], fx["review_sha"])
    try:
        findings = extract_json(run_claude(
            RECON_TMPL.format(spec=json.dumps(spec, indent=2), code=code), model, worktree),
            prefer="array")
    except Exception as e:
        return {"status": f"recon-error: {e}", "matched": False, "n_spec": len(spec)}
    # judge — did any reconciliation finding match the gold?
    try:
        verdict = extract_json(run_claude(
            JUDGE_TMPL.format(file=fx["file"], gold=fx["gold"],
                              findings=json.dumps(findings, indent=2)), judge_model, repo),
            prefer="object")
    except Exception as e:
        return {"status": f"judge-error: {e}", "matched": False,
                "n_spec": len(spec), "n_findings": len(findings)}
    return {"status": "ok", "matched": bool(verdict.get("matched")),
            "why": verdict.get("why", ""), "n_spec": len(spec),
            "n_findings": len(findings), "spec": spec, "findings": findings,
            "verdict": verdict}


def run(args):
    fixtures = {json.loads(l)["id"]: json.loads(l)
                for l in open(args.fixtures) if l.strip()}
    intents = {json.loads(l)["id"]: json.loads(l)["intent"]
               for l in open(args.intents) if l.strip()}
    ids = [i for i in intents if i in fixtures]
    if args.only:
        want = set(args.only.split(","))
        ids = [i for i in ids if i in want]
    if not ids:
        sys.exit("no fixtures with intents selected")

    repo = os.path.expanduser(args.repo)
    by_sha = defaultdict(list)
    for i in ids:
        by_sha[fixtures[i]["review_sha"]].append(i)

    results = {}
    for sha, group in by_sha.items():
        wt = tempfile.mkdtemp(prefix="rl-intent-", dir=tempfile.gettempdir())
        git(repo, "worktree", "add", "--detach", wt, sha)
        try:
            for fid in group:
                hits, last = 0, {"status": "not-run", "matched": False}
                for k in range(args.repeat):
                    tag = f" [{k+1}/{args.repeat}]" if args.repeat > 1 else ""
                    print(f"  · {fid}{tag} …", file=sys.stderr, flush=True)
                    try:
                        last = recon_one(fixtures[fid], intents[fid], repo, wt,
                                         args.model, args.judge_model)
                    except Exception as e:
                        last = {"status": f"crash: {e}", "matched": False}
                    if last.get("matched"):
                        hits += 1
                results[fid] = {**last, "hits": hits, "runs": args.repeat, "matched": hits > 0}
        finally:
            git(repo, "worktree", "remove", "--force", wt)

    journal = os.path.join(os.path.dirname(args.fixtures), "last-intent-run.jsonl")
    with open(journal, "w") as jf:
        for fid in ids:
            jf.write(json.dumps({"id": fid, **results.get(fid, {})}) + "\n")

    print("\n" + "=" * 72)
    print("INTENT-FIRST RECONCILIATION — does modelling intent catch omission bugs?")
    print("=" * 72)
    th = sum(results.get(i, {}).get("hits", 0) for i in ids)
    tr = sum(results.get(i, {}).get("runs", 1) for i in ids)
    for i in ids:
        r = results[i]
        runs = r.get("runs", 1)
        mark = f"{r.get('hits',0)}/{runs}" if runs > 1 else ("HIT " if r.get("matched") else "miss")
        if runs == 1 and r.get("status", "ok") != "ok":
            mark = "ERR "
        extra = r.get("why") or r.get("status", "")
        print(f"  [{mark:>4}] {i:<24} spec={r.get('n_spec','?'):<3} found={r.get('n_findings','?'):<3} {extra[:44]}")
    print(f"  recall (detections / attempts): {th}/{tr}" + (f"  ({100*th//tr}%)" if tr else ""))
    print(f"\n(spec + findings per fixture in {journal})", file=sys.stderr)


def selftest():
    # sanity: templates survive .format()
    assert "intent-x" in SPEC_TMPL.format(intent="intent-x", files="a.ts")
    assert '"kind"' in RECON_TMPL.format(spec="[]", code="code")
    print("ok")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo")
    here = os.path.dirname(__file__)
    ap.add_argument("--fixtures", default=os.path.join(here, "fixtures.jsonl"))
    ap.add_argument("--intents", default=os.path.join(here, "intents.jsonl"))
    ap.add_argument("--only")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--model", default="opus")
    ap.add_argument("--judge-model", default="sonnet")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        selftest()
        return 0
    if not args.repo:
        ap.error("--repo is required")
    run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
