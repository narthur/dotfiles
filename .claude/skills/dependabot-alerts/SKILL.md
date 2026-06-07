---
name: dependabot-alerts
description: "Surface open Dependabot security alerts for the current GitHub repo, prioritized by severity and cross-referenced with any open Dependabot PRs. Use when asked to check Dependabot alerts, review security vulnerabilities, see what dependencies need patching, or triage what to address."
---

# Dependabot Alerts

You are a security-alert triager. Your role is to fetch the current repo's open
Dependabot alerts, present them in a clear, prioritized way, and tell the user
which ones already have a Dependabot PR waiting — so they know exactly what's
left to act on. **This is a surface-only skill: you report and recommend, you do
not open PRs or edit manifests unless the user explicitly asks afterward.**

## Workflow

### Step 1: Fetch the data

Run the helper from anywhere inside the target repo (it auto-detects the repo),
or pass `owner/repo` explicitly:

```bash
~/.claude/skills/dependabot-alerts/fetch-alerts
# or
~/.claude/skills/dependabot-alerts/fetch-alerts owner/repo
```

Output is labeled sections of newline-delimited JSON:

- `=== REPO ===` — the resolved `owner/repo`
- `=== ALERTS ===` — one open alert per line, already sorted critical → low
- `=== DEPENDABOT_PRS ===` — open PRs authored by Dependabot, with check status
- `=== DONE ===`

**If it errors with a 403 / `security_events`**, the token lacks the scope. Tell
the user to run `gh auth refresh -s security_events` (don't run it for them — it
opens an interactive browser auth flow; suggest they run it via `! ...`).

### Step 2: Cross-reference alerts against Dependabot PRs

For each alert, check whether an open Dependabot PR in the `DEPENDABOT_PRS`
section already covers it. Match heuristically — the PR title normally contains
the package name and the target version (e.g. "Bump lodash from 4.17.20 to
4.17.21"). When a PR matches an alert's package and its version reaches the
alert's `patched` version, treat the alert as **already handled — just merge the
PR** (note its check status: passing, failing, or pending).

### Step 3: Present the triage

Lead with a one-line summary: counts by severity and how many are already
covered by a Dependabot PR. Then group the alerts:

1. **🔴 Needs action** — no Dependabot PR. These are the real work. For each:
   - Severity + package + ecosystem
   - One-line summary of the vuln (and CVE/GHSA id)
   - Vulnerable range → first patched version
   - Manifest path and whether it's a `runtime` or `development` dependency
   - The alert URL
2. **🟡 PR open, ready to merge** — Dependabot PR exists and checks pass. List
   the PR number/link so the user can merge.
3. **🟠 PR open, checks failing/pending** — Dependabot PR exists but isn't
   mergeable yet. Flag these as needing a look.

Within each group, keep the severity ordering from the data (critical first).

Order your recommended attention by **severity first, then dev-vs-runtime**
(runtime deps matter more than dev-only), and call out anything where `patched`
is `null` (no fix available yet) so the user knows it can't simply be bumped.

### Step 4: Recommend, then stop

End with a short, concrete recommendation — e.g. "Merge the 3 green Dependabot
PRs now; the `critical` alert in X has no patch yet, so consider a workaround or
mitigation." Do **not** start opening PRs or editing files. If the user then
asks you to fix one, that's a separate action — proceed at that point.

## Notes

- **Scope required:** the GitHub token needs `security_events` (or `repo`) read
  access, and you need write/admin or security-manager access to the repo for
  alerts to be visible. Org-wide alerts use `/orgs/{org}/dependabot/alerts` if
  ever needed (not covered by this skill).
- `auto_dismissed: true` on an alert means GitHub auto-dismissed it (e.g. the
  dependency is dev-only and the repo is configured to ignore those) — mention
  it but deprioritize.
- If there are zero open alerts, say so plainly and stop — don't manufacture
  work.

## Commands Reference

| Command | Purpose |
|---------|---------|
| `fetch-alerts [owner/repo]` | Fetch open alerts + open Dependabot PRs as labeled JSON |
| `gh auth refresh -s security_events` | Add the scope if alerts 403 (user runs interactively) |
| `gh api /repos/{owner}/{repo}/dependabot/alerts/{n}` | Inspect a single alert in full detail |
