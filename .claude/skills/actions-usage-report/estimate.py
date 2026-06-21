#!/usr/bin/env python3
"""Estimate GitHub Actions billable minutes per workflow for an org.

Usage: estimate.py <org> [--days N] [--sample S] [--include-public]

Why this exists: GitHub deprecated the billing/timing API after migrating to the
new billing platform. /orgs/{org}/settings/billing/actions returns HTTP 410 and
/repos/.../runs/{id}/timing returns all-zeros. So we reconstruct billable minutes
from per-job durations, applying GitHub's real billing rule:

    each job is billed SEPARATELY, rounded UP to a whole minute
    (a 20-second job still costs 1 full minute; skipped jobs cost 0).

Only PRIVATE, non-archived repos consume billable minutes by default — public
repos run free regardless of volume (pass --include-public to count them anyway).

Absolute numbers are modeled estimates; the ranking/relative magnitudes are solid.
"""
import subprocess, json, math, sys, argparse
from collections import defaultdict
from datetime import datetime, timedelta, timezone


def gh(path):
    r = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


def parse(t):
    return datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc) if t else None


def norm(name):
    """Collapse dynamic per-PR / per-dependency workflow names into stable buckets."""
    if not name or not name.strip():
        return "(unnamed)"
    if name.startswith("Code Quality: PR"):
        return "Code Quality: PR (per-PR)"
    if name.startswith(("npm_and_yarn", "github_actions in", "pip in", "bundler in", "docker in")):
        return "Dependabot version PRs"
    return name


def billed_for_run(org, repo, rid):
    """Sum of ceil(job_seconds/60), min 1 per job that actually ran."""
    d = gh(f"/repos/{org}/{repo}/actions/runs/{rid}/jobs?per_page=100")
    if not d:
        return None
    tot = 0
    for j in d.get("jobs", []):
        s, c = parse(j.get("started_at")), parse(j.get("completed_at"))
        if not s or not c:
            continue
        secs = (c - s).total_seconds()
        if secs <= 0:
            continue  # skipped / never started
        tot += max(1, math.ceil(secs / 60))
    return tot


def repo_report(org, repo, cutoff, sample):
    runs, page = [], 1
    while page <= 40:
        d = gh(f"/repos/{org}/{repo}/actions/runs?per_page=100&page={page}")
        if not d or not d.get("workflow_runs"):
            break
        batch = d["workflow_runs"]
        runs += batch
        if parse(batch[-1]["created_at"]) < cutoff:
            break
        page += 1
    runs = [r for r in runs if parse(r["created_at"]) >= cutoff]
    if not runs:
        return None

    bywf = defaultdict(list)
    for r in runs:
        bywf[norm(r["name"])].append(r["id"])

    rows, grand = [], 0.0
    for wf, ids in bywf.items():
        vals = [billed_for_run(org, repo, i) for i in ids[:sample]]
        vals = [v for v in vals if v is not None]
        if not vals:
            continue
        avg = sum(vals) / len(vals)
        total = avg * len(ids)
        grand += total
        rows.append((total, len(ids), avg, wf))
    rows.sort(reverse=True)
    return {"repo": repo, "runs": len(runs), "total": grand, "rows": rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("org")
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--sample", type=int, default=5, help="runs sampled per workflow for billed-min/run")
    ap.add_argument("--include-public", action="store_true", help="also count public repos (normally free)")
    args = ap.parse_args()

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    since = cutoff.strftime("%Y-%m-%d")

    # discover candidate repos, most-recently-pushed first
    repos, page = [], 1
    while page <= 10:
        d = gh(f"/orgs/{args.org}/repos?per_page=100&sort=pushed&page={page}")
        if not d:
            break
        repos += d
        if len(d) < 100:
            break
        page += 1
    if not repos:
        print(f"No repos found for org '{args.org}' (check name / auth).", file=sys.stderr)
        sys.exit(1)

    candidates = [r for r in repos if not r.get("archived") and (args.include_public or r.get("private"))]
    print(f"Scanning {len(candidates)} {'repos' if args.include_public else 'private repos'} "
          f"in {args.org} over last {args.days}d (public repos run free)...", file=sys.stderr)

    reports, skipped = [], 0
    for r in candidates:
        name = r["name"]
        cnt = gh(f"/repos/{args.org}/{name}/actions/runs?created=%3E{since}&per_page=1")
        n = (cnt or {}).get("total_count", 0)
        if not n:
            continue
        print(f"  - {name}: {n} runs, estimating...", file=sys.stderr)
        rep = repo_report(args.org, name, cutoff, args.sample)
        if rep and rep["total"] > 0:
            reports.append(rep)

    reports.sort(key=lambda x: -x["total"])
    grand = sum(r["total"] for r in reports)
    cat = defaultdict(float)

    def cat_of(wf):
        w = wf.lower()
        if w.startswith("ci") or w == "ci":
            return "CI"
        if "coverage" in w:
            return "Coverage"
        if "copilot" in w:
            return "Copilot review"
        if "release" in w or "deploy" in w or w == "merge":
            return "Release/Deploy"
        if "code quality" in w or "codeql" in w or "lint" in w:
            return "Code Quality"
        if "dependabot" in w or "lockfile" in w:
            return "Dependabot"
        return "Other"

    print("\n" + "=" * 64)
    print(f"  GitHub Actions billable-minute estimate — {args.org}")
    print(f"  Last {args.days} days · {'incl. public' if args.include_public else 'private repos only (public = free)'}")
    print("  Modeled from per-job durations (each job ceil-ed to >=1 min);")
    print("  GitHub's billing/timing API is deprecated and returns zeros.")
    print("=" * 64)
    for rep in reports:
        print(f"\n### {rep['repo']}  —  ~{rep['total']:.0f} billed min/{args.days}d  ({rep['runs']} runs)")
        print(f"    {'billed-min':>10} {'runs':>5} {'min/run':>8}  workflow")
        for total, n, avg, wf in rep["rows"]:
            if total < 0.5:
                continue
            cat[cat_of(wf)] += total
            print(f"    {total:10.0f} {n:5d} {avg:8.1f}  {wf}")

    print("\n" + "-" * 64)
    print(f"  By category (all repos):")
    for c, v in sorted(cat.items(), key=lambda x: -x[1]):
        pct = 100 * v / grand if grand else 0
        print(f"    {v:8.0f} min  ({pct:4.1f}%)  {c}")
    print("-" * 64)
    print(f"  TOTAL billable estimate: ~{grand:.0f} min / {args.days} days")
    print(f"  Free plan includes 2,000 min/mo; Team 3,000. Overage ~$0.008/min (Linux).")
    if grand > 2000:
        over = grand - 2000
        print(f"  ~{over:.0f} min over free allowance ≈ ${over*0.008:.0f}/mo, "
              f"and a likely cause of 'checks won't start' budget blocks.")


if __name__ == "__main__":
    main()
