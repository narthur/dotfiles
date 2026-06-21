---
name: actions-usage-report
description: "Analyze GitHub Actions usage for a GitHub org and identify ways to cut billable minutes. Estimates billable minutes per workflow (private repos only — public repos run free), ranks the biggest cost drivers, compares CI vs Copilot review, and recommends concrete efficiency fixes. Use when asked which CI checks use the most minutes, how to reduce Actions costs/usage, why CI won't start (budget/minutes block), or for a periodic Actions spend review. Accepts an org name."
---

# GitHub Actions Usage Report

You produce an Actions-efficiency report for a GitHub org: where the billable minutes
go, which checks dominate, how Copilot review compares, and what to fix.

## Inputs

- **org** (required): the GitHub org/login (e.g. `PinePeakDigital`). If the user
  didn't give one, ask, or infer from the current repo's remote.
- Optional: lookback window (default 30 days), sample size per workflow (default 5).

## Why this skill exists (read before trusting any number)

GitHub **deprecated the billing/timing API** after migrating to its new billing
platform:
- `/orgs/{org}/settings/billing/actions` → HTTP 410 ("endpoint moved"), and needs
  `admin:org` scope anyway.
- `/repos/.../actions/runs/{id}/timing` → returns **all zeros** (`total_ms: 0`).

So you **cannot** read billable minutes directly. Instead, reconstruct them from
per-job durations using GitHub's real billing rule:

> **Each job is billed separately, rounded UP to a whole minute.** A 20-second
> lint job still costs 1 full minute. Skipped jobs (no `started_at`) cost 0.

This makes **job fan-out the dominant cost factor**: a workflow with 20 sub-minute
jobs bills ~20 minutes for ~3 minutes of real work. Wall-clock run duration badly
*under*-counts; always compute from jobs.

Only **private, non-archived** repos consume billable minutes. **Public repos run
free** regardless of volume — exclude them from cost analysis (the script does by
default).

The numbers are **modeled estimates**; state that. The *ranking and relative
magnitudes* are reliable and are what the recommendations rest on.

## Steps

1. **Check auth.** `gh auth status` — needs at least `repo` + `read:org` scope.
2. **Run the estimator** (it discovers repos, filters private, samples job timings):
   ```bash
   python3 ~/.claude/skills/actions-usage-report/estimate.py <org>
   # options: --days N (default 30), --sample S (default 5), --include-public
   ```
   It prints a per-repo workflow table, a by-category rollup (CI / Coverage /
   Copilot review / Release-Deploy / Code Quality / Dependabot / Other), and a grand
   total vs the free allowance. Progress goes to stderr. Large orgs take a few
   minutes (one job-list API call per sampled run) — fine to background it.
3. **Read the top workflows' YAML** for the biggest cost drivers to find *why*
   they're expensive (don't guess):
   ```bash
   gh api /repos/<org>/<repo>/contents/.github/workflows/<file>.yml --jq .content | base64 -d
   ```
   Look specifically for: missing `concurrency` / `cancel-in-progress`; one-job-per-check
   fan-out that could be grouped per package; duplicated test runs (e.g. a separate
   Coverage workflow re-running the suite CI already ran); `runs-on` macos/windows
   (10×/2× multipliers); broad triggers that should be path-filtered.
4. **Distinguish the two "Copilot" things** when reporting the comparison:
   - A **custom Actions workflow** (often named "Running Copilot Code Review") —
     genuinely bills Actions minutes; redundant if native review is on.
   - GitHub's **native Copilot code review** (dynamic `copilot-pull-request-reviewer`)
     — billed under the Copilot subscription, ~0 real Actions cost; the job-duration
     heuristic may over-count it. Say so.

## Reporting

Produce a tight report:
- A ranked table: workflow (repo) · runs · billed min/run · **billed min/mo** · % share.
- The by-category rollup and grand total vs plan allowance (free = 2,000 min/mo,
  Team = 3,000; overage ≈ $0.008/min Linux, 2× Windows, 10× macOS).
- Answer directly: **which checks cost the most**, **how Copilot review compares**
  (usually a small fraction), **what's inefficient or unnecessary**.
- Concrete fixes ordered by effort-to-payoff, each with an estimated saving. The
  usual high-value levers, in order:
  1. `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }`
     to kill superseded PR runs — lowest effort, low risk.
  2. Eliminate duplicated work (e.g. fold a separate Coverage workflow's test run
     into the existing CI test jobs).
  3. Consolidate one-job-per-check fan-out into ~one job per package — directly
     attacks the per-minute rounding tax.
  4. Drop redundant custom Copilot-review workflow if native review is enabled.
  5. Path-filter / gate frequently-firing deploy/release workflows.
- Offer to open a tracking issue and/or implement the safe wins.

Note the connection to budget blocks: an org far over its minute allowance is the
common cause of "checks won't start / startup_failure / 0 jobs" — the same symptom
the `fix-ci` skill flags.
