#!/usr/bin/env python3
"""Replay curated past review findings through review-loop's subagents and
measure recall — did the agent that OWNS a finding independently surface it?

For each fixture we check out its review-time commit in a throwaway git
worktree (so the agent sees the code the human/CodeRabbit reviewer saw, not the
already-fixed tip), hand the owning agent that cycle's diff, then an LLM judge
decides whether any finding matches the gold. Recall is reported over the
substantive accepted findings; blind-spot and dismissed fixtures are bucketed
separately (see README).

  replay.py --repo ~/code/yourrepo [--only <fixture-id>,...] [--repeat N]
            [--include-optional] [--agent-model sonnet] [--judge-model sonnet]
  replay.py --selftest

Requires the `claude` CLI on PATH. Runs serially — ~1 agent + 1 judge call per
fixture. ponytail: serial is fine for a hand-run eval; parallelize when the set
outgrows patience.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict

# Agent focus text, kept in sync with SKILL.md Step 5. ponytail: duplicated
# rather than parsed out of the markdown — the source of truth is the skill; if
# an agent's focus changes there, update it here too.
STYLE_DEFAULT = (
    "The user prefers an immutable style as the default: const over let-reassignment, "
    "expression forms over accumulate-and-mutate. Flag diff-introduced mutable patterns "
    "ONLY when they collapse cleanly into an immutable form with identical behavior."
)
AGENTS = {
    "2-bugs": (
        "You are a bug-scan reviewer. Look for correctness bugs in the diff: off-by-ones, "
        "null/undefined access, async race conditions, wrong loop bounds, copy-paste errors, "
        "mutation-of-arguments, missing returns, incorrect error handling, silently-dropped "
        "inputs, and contract violations (a documented behavior the code fails to honor). "
        "Ignore linter/typechecker territory and formatting."
    ),
    "5-security": (
        "You are a security reviewer. Look for injection, hardcoded secrets, missing auth "
        "checks, unsafe deserialization, path traversal, missing CSRF/CORS, broken access "
        "control, and sensitive data (secrets/tokens/PII) leaking to logs, error reporters, "
        "or third parties. Be specific about the vulnerability class and how it is triggered."
    ),
    "7-structural": (
        "You are a structural-simplification and scalability reviewer. You may and should "
        "read beyond the diff. Look for restructurings that make a branch/helper/layer "
        "disappear, needless indirection, feature logic leaking into shared modules, "
        "duplicated logic that will drift, unbounded scans, and avoidable round-trips / "
        "redundant I/O that a local computation would remove."
    ),
}

AGENT_TMPL = """{focus}

{style}

Review scope — this is the diff under review:
```diff
{diff}
```

The primary file is {file}. You are in a checkout at the state under review; you
MAY open other files with your tools to confirm a finding. Report every real
issue you find in the scope.

Output ONLY a JSON array (no prose, no code fence) of objects:
[{{"file": "...", "line_range": "start-end", "description": "...", "suggested_fix": "...", "reasoning": "..."}}]
If you find nothing, output exactly: []"""

JUDGE_TMPL = """You are grading whether a code-review agent independently found a specific known issue.

KNOWN ISSUE (gold), in file {file}:
{gold}

AGENT FINDINGS (JSON):
{findings}

A finding MATCHES only if it identifies the SAME underlying issue as the gold —
same root cause and same location/region — not merely the same file or a
vaguely related concern. Paraphrase is fine; a different bug in the same file is
NOT a match.

Output ONLY JSON: {{"matched": true or false, "which": <0-based index or null>, "why": "<=25 words"}}"""


def _spans(text, opener, closer):
    """Yield top-level balanced opener..closer substrings, ignoring brackets
    inside JSON strings. Models pad answers with prose that contains stray
    brackets (`security: [bearerAuth]`), so a naive first-to-last slice breaks."""
    depth = start = 0
    started = False
    in_str = esc = False
    for i, ch in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == opener:
            if depth == 0:
                start, started = i, True
            depth += 1
        elif ch == closer and depth > 0:
            depth -= 1
            if depth == 0 and started:
                yield text[start:i + 1]


def extract_json(text, prefer=None):
    """Pull JSON out of a model reply. prefer='array' returns the last valid
    [...], 'object' the last valid {...} (the judge echoes the findings array
    before its verdict, so type matters). Default tries array then object.
    'Last valid' because the real answer trails any reasoning preamble."""
    fence = re.search(r"```(?:json)?\s*(.+?)```", text, re.S)
    if fence:
        text = fence.group(1).strip()
    pairs = {"array": [("[", "]")], "object": [("{", "}")]}.get(
        prefer, [("[", "]"), ("{", "}")])
    for opener, closer in pairs:
        best = None
        for span in _spans(text, opener, closer):
            try:
                best = json.loads(span)
            except json.JSONDecodeError:
                pass
        if best is not None:
            return best
    raise ValueError("no JSON found")


def run_claude(prompt, model, cwd, timeout=300):
    p = subprocess.run(
        ["claude", "-p", "--model", model, "--dangerously-skip-permissions"],
        input=prompt, cwd=cwd, capture_output=True, text=True, timeout=timeout,
    )
    if p.returncode != 0:
        raise RuntimeError(f"claude exited {p.returncode}: {p.stderr[:300]}")
    return p.stdout


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args],
                          capture_output=True, text=True).stdout


def review_one(fx, repo, worktree, agent_model, judge_model):
    # Focused probe: the fixture file's diff as the review scope, and the agent
    # sits in a worktree at review state so it can open sibling files itself for
    # context. Deliberately NOT the whole-PR diff — that drags in generated/lock
    # files that swamp the signal, and per-fixture it conflates recall with
    # prioritization on multi-finding PRs (measured: whole-diff tanked recall).
    diff = git(repo, "diff", f"{fx['base_sha']}..{fx['review_sha']}", "--", fx["file"])
    if not diff.strip():
        return {"status": "no-diff", "matched": False}
    focus = AGENTS[fx["agent"]]
    prompt = AGENT_TMPL.format(focus=focus, style=STYLE_DEFAULT, diff=diff, file=fx["file"])
    findings = raw = None
    # one retry: `claude -p` occasionally narrates instead of emitting bare JSON.
    for attempt in (1, 2):
        p = prompt if attempt == 1 else prompt + "\n\nReminder: output the JSON array ONLY. No prose."
        try:
            raw = run_claude(p, agent_model, worktree)
            findings = extract_json(raw, prefer="array")
            break
        except Exception as e:
            last = e
    if findings is None:
        dbg = os.path.join(tempfile.gettempdir(), f"rl-eval-raw-{fx['id']}.txt")
        try:
            open(dbg, "w").write(raw or "<no output>")
        except Exception:
            pass
        return {"status": f"agent-error: {last} (raw: {dbg})", "matched": False}
    if not isinstance(findings, list):
        findings = [findings]
    jprompt = JUDGE_TMPL.format(file=fx["file"], gold=fx["gold"],
                                findings=json.dumps(findings, indent=2))
    try:
        verdict = extract_json(run_claude(jprompt, judge_model, repo), prefer="object")
    except Exception as e:
        return {"status": f"judge-error: {e}", "matched": False, "n_findings": len(findings)}
    return {
        "status": "ok",
        "matched": bool(verdict.get("matched")),
        "why": verdict.get("why", ""),
        "n_findings": len(findings),
        "findings": findings,
        "verdict": verdict,
    }


def run(args):
    fixtures = [json.loads(l) for l in open(args.fixtures) if l.strip()]
    if args.only:
        wanted = set(args.only.split(","))
        fixtures = [f for f in fixtures if f["id"] in wanted]
    if not args.include_optional:
        fixtures = [f for f in fixtures if f["expect"] != "optional"]
    if not fixtures:
        sys.exit("no fixtures selected")

    repo = os.path.expanduser(args.repo)
    by_sha = defaultdict(list)
    for f in fixtures:
        by_sha[f["review_sha"]].append(f)

    results = {}
    for sha, group in by_sha.items():
        wt = tempfile.mkdtemp(prefix="rl-eval-", dir=args.workdir)
        git(repo, "worktree", "add", "--detach", wt, sha)
        try:
            for fx in group:
                hits, last = 0, {"status": "not-run", "matched": False}
                for k in range(args.repeat):
                    tag = f" [{k+1}/{args.repeat}]" if args.repeat > 1 else ""
                    print(f"  · {fx['id']} ({fx['agent']}){tag} …", file=sys.stderr, flush=True)
                    try:
                        last = review_one(fx, repo, wt, args.agent_model, args.judge_model)
                    except Exception as e:  # never let one fixture sink the batch
                        last = {"status": f"crash: {e}", "matched": False}
                    if last.get("matched"):
                        hits += 1
                results[fx["id"]] = {**last, "hits": hits, "runs": args.repeat,
                                     "matched": hits > 0}
        finally:
            git(repo, "worktree", "remove", "--force", wt)

    journal = os.path.join(os.path.dirname(args.fixtures), "last-run.jsonl")
    with open(journal, "w") as jf:
        for fx in fixtures:
            jf.write(json.dumps({"id": fx["id"], **results.get(fx["id"], {})}) + "\n")
    print(f"\n(agent findings + verdicts written to {journal})", file=sys.stderr)
    report(fixtures, results)


def report(fixtures, results):
    buckets = {"recall": [], "blind_spot": [], "optional": []}
    for f in fixtures:
        if f["expect"] == "optional":
            buckets["optional"].append(f)
        elif f.get("blind_spot"):
            buckets["blind_spot"].append(f)
        else:
            buckets["recall"].append(f)

    def line(f):
        r = results.get(f["id"], {})
        runs = r.get("runs", 1)
        h = r.get("hits", 0)
        mark = f"{h}/{runs}" if runs > 1 else ("HIT " if r.get("matched") else "miss")
        if runs == 1 and r.get("status", "ok") != "ok":
            mark = "ERR "
        extra = r.get("why") or r.get("status", "")
        return f"    [{mark:>4}] {f['id']:<24} {f['category']:<14} {extra[:58]}"

    print("\n" + "=" * 72)
    print("RECALL — substantive accepted findings the owning agent should catch")
    print("=" * 72)
    tot_hits = sum(results.get(f["id"], {}).get("hits", 0) for f in buckets["recall"])
    tot_runs = sum(results.get(f["id"], {}).get("runs", 1) for f in buckets["recall"])
    for f in buckets["recall"]:
        print(line(f))
    print(f"  recall (detections / attempts): {tot_hits}/{tot_runs}"
          + (f"  ({100*tot_hits//tot_runs}%)" if tot_runs else ""))

    if buckets["blind_spot"]:
        print("\n" + "-" * 72)
        print("BLIND SPOTS — no agent truly owns these; a miss is diagnostic, not a regression")
        print("-" * 72)
        for f in buckets["blind_spot"]:
            print(line(f))

    if buckets["optional"]:
        print("\n" + "-" * 72)
        print("DISMISSED — surfacing is OK but must route to ASK, not auto-fix (v1 measures surfacing only)")
        print("-" * 72)
        for f in buckets["optional"]:
            r = results.get(f["id"], {})
            mark = "raised " if r.get("matched") else "quiet  "
            print(f"    [{mark}] {f['id']:<24} {f['category']:<14} {(r.get('why') or '')[:50]}")
    print()


def selftest():
    assert extract_json('[{"a":1}]') == [{"a": 1}]
    assert extract_json('here you go:\n[{"a":1}]\nthanks') == [{"a": 1}]
    assert extract_json('```json\n[1,2,3]\n```') == [1, 2, 3]
    assert extract_json('{"matched": true, "which": 0}')["matched"] is True
    # judge echoes the findings array before its verdict object: prefer='object' must skip it
    noisy = 'findings were [1,2] so: {"matched": false, "which": null}'
    assert extract_json(noisy, prefer="object")["matched"] is False
    assert extract_json('[{"a":1}]', prefer="array") == [{"a": 1}]
    # prose with stray brackets then the real empty-findings answer (the tr-1017 case)
    prose = 'security: [bearerAuth] and security: [] are correct.\n\n[]'
    assert extract_json(prose, prefer="array") == []
    # a string containing a bracket must not fool the balanced scan
    assert extract_json('[{"desc": "arr[0] out of bounds"}]', prefer="array")[0]["desc"] == "arr[0] out of bounds"
    try:
        extract_json("no json here")
        assert False, "should have raised"
    except ValueError:
        pass
    print("ok")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo")
    ap.add_argument("--fixtures", default=os.path.join(os.path.dirname(__file__), "fixtures.jsonl"))
    ap.add_argument("--only")
    ap.add_argument("--include-optional", action="store_true")
    ap.add_argument("--agent-model", default="sonnet")
    ap.add_argument("--judge-model", default="sonnet")
    ap.add_argument("--repeat", type=int, default=1,
                    help="runs per fixture; >1 gives a stable per-fixture hit-rate (recall is noisy at n=1)")
    ap.add_argument("--workdir", default=tempfile.gettempdir())
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        selftest()
        return 0
    if not args.repo:
        ap.error("--repo is required (path to the source checkout)")
    run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
