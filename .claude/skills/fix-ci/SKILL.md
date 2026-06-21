---
name: fix-ci
description: "Address failing CI checks for the PR associated with the currently-checked-out git branch. Use when asked to fix CI, address failing checks, fix the build, or investigate why CI is failing — including when checks fail to *start* (startup_failure, 0 jobs, 'workflow file issue'), which is often an account-level GitHub Actions budget/minutes block rather than a code problem (it diagnoses this before trying to fix code)."
---

# Fix CI Skill

You are a CI debugging specialist. Your role is to identify which CI checks are failing for the PR associated with the current branch, fetch and analyze the failure logs, fix the underlying issues, commit, push, and repeat until CI passes — up to a configurable cycle limit.

## What You Do

- Detect the PR for the current branch using `gh`
- Identify failing CI checks and fetch their logs
- Analyze failure output to understand root causes
- Fix the code issues causing failures
- Commit and push the fix
- After pushing, start fixing the next failure as soon as one appears — do not wait for the rest of CI to finish
- Stop when CI passes or the cycle limit is reached

## What You Don't Do

- Fix issues unrelated to CI failures — stay focused
- Re-run flaky checks repeatedly without investigating; check run history first
- Skip the log analysis step — never guess what failed

## Iterative Mode (Default)

By default, this skill runs in an **iterative loop**: fix → commit → push → poll for the first failure → repeat if still failing.

- **Default cycle limit: 3** (override by telling the agent a different limit)
- Each cycle is one round of: diagnose failures → fix → commit → push → poll
- The loop exits early when all checks pass
- If the limit is reached and CI is still failing, stop and report what remains broken

## CRITICAL: Act on Failures Immediately

**Do not wait for all CI jobs to finish before starting to fix.** As soon as any required check has reported a `failure` (or `cancelled`/`timed_out`) conclusion, begin diagnosing and fixing it — even if other jobs are still `in_progress` or `queued`. Waiting for green-or-red on every job wastes minutes when the failure signal is already in hand.

When polling:
- Treat any check with `conclusion` in {`failure`, `cancelled`, `timed_out`, `action_required`} as actionable now.
- Only wait longer if **zero** checks have failed yet and **none** have completed — i.e., there is no failure signal to act on.
- If a fix lands and a previously-pending job later fails, the next cycle will pick it up.

## CRITICAL: Check Run History Before Re-Running

**Always check whether the failing check has already failed multiple times.** Use `gh run list --branch <branch> --limit 5` to see recent runs. If the same check has failed across multiple runs, it's a real bug — investigate and fix it. Only consider a re-run if the failure looks transient (timeout, network error, resource exhaustion) **and** it hasn't failed in the prior run.

## CRITICAL: Workspace Detection

At the start, always check workspace type:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → **GitButler mode**: use `but` CLI for staging/committing/pushing
- Otherwise → **Standard git mode**: use `git add`, `git commit`, `git push`

---

## Workflow

### Step 1: Verify Git Context

Confirm you're inside a git repository and get the current branch:

```bash
git rev-parse --is-inside-work-tree 2>/dev/null && git branch --show-current
```

If not in a git repo, stop and inform the user.

### Step 2: Find the Associated PR

```bash
gh pr view --json number,title,url,headRefName,headRefOid,baseRefName,state
```

If no PR is found for the current branch, inform the user. If the PR is already merged or closed, note that.

Capture:
- PR number
- Head commit SHA (`headRefOid`)
- Branch name (`headRefName`)

### Step 2.5: Triage — Did the checks even *start*? (may be unfixable in code)

**Before** entering the fix loop, rule out an account-level block. This skill assumes there are failure *logs* to analyze — but when an org/user hits an Actions **spending budget** (with "block further usage" on) or runs out of included **minutes**, GitHub fails every new run at *startup*: `conclusion: startup_failure`, **0 jobs**, **0s** duration, and a misleading "this run likely failed because of a workflow file issue." There are no logs, and no code change fixes it.

The tell vs. genuinely-broken workflow YAML: broken YAML fails only the *one* bad workflow, whereas a budget/minutes block fails **≥2 different workflows at once**. If you see that pattern (or any `startup_failure` with 0 jobs), run the checker (`~/bin/gh-budget`, also available as `gh budget`) — it reads the real billing budgets + usage (works with a `read:org` token) and combines them with the live run signature:

```bash
gh-budget
```

- **Exit code 2** → Actions is blocked (budget/minutes). **Stop. Do not enter the fix loop** — there is nothing to fix in code. Report the verdict to the user verbatim (it includes the budget settings URL) and let them raise/disable the budget or wait for the monthly reset.
- **Exit code 0** → not blocked at startup; proceed to the fix loop normally.
- **Exit code 65** → couldn't read billing (token scope). Fall back to the heuristic above and tell the user; don't burn cycles re-running.

### Step 3: Begin Fix Cycle (loop up to cycle limit)

Track the current cycle number starting at 1. For each cycle:

---

#### 3a: List CI Check Runs

```bash
gh run list --branch <headRefName> --limit 10 --json databaseId,name,status,conclusion,headSha,url,createdAt
```

Filter to runs matching the head commit SHA or, if none match exactly, use the most recent runs on the branch.

Also get check-run level status (individual jobs within a workflow):

```bash
gh api repos/{owner}/{repo}/commits/<headRefOid>/check-runs --jq '.check_runs[] | {name: .name, conclusion: .conclusion, status: .status, details_url: .details_url}'
```

To get `{owner}/{repo}`:

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

#### 3b: Identify Failures

From the results, list:
- Failed workflow runs (conclusion: `failure`)
- Failed/cancelled/timed-out individual check runs

Present a summary:

```
[Cycle N/limit] PR #<N>: <title>
Branch: <branch>
Commit: <sha>

Failing checks:
  ✗ <check-name> — <url>

Passing:
  ✓ <check-name>
  ○ <check-name> (pending)
```

**Decision rules:**
- If **any** failures exist → proceed to 3c immediately, even if other checks are still pending. Do not wait for the rest of CI.
- If **all** checks have completed and none failed → CI is green, exit the loop and inform the user.
- If **no failures yet but checks are still pending** → poll (see 3g) until either a failure appears or all checks complete.

#### 3c: Fetch Failure Logs

For each failing workflow run:

```bash
gh run view <run-id> --log-failed
```

If there are multiple failing runs, fetch logs for each. For external checks (not GitHub Actions), note the `details_url` for the user.

#### 3d: Analyze Failures

Read the logs and identify:
- The specific error message(s)
- Which file(s) and line(s) are involved
- The likely root cause

Present a plain-language summary:

```
Root cause: <concise description>
Files involved: <list>
Error: <key error message>
```

#### 3e: Implement the Fix

Edit the relevant files to address the root cause. Focus on the minimum change needed — do not refactor or improve unrelated code.

After editing, if tests or linting can be run locally, do so to verify:

```bash
# Adjust to project tooling
npm test
npm run lint
npx tsc --noEmit
```

#### 3f: Commit and Push

**Standard git mode:**

```bash
git add <changed-files>
git commit -m "fix(<scope>): <description of what was fixed>"
git push
```

**GitButler mode:**

```bash
but status --json
but commit <branch-name> -m "fix(<scope>): <description>" --changes <id>,<id>
but push <branch-name>
```

Use conventional commit format. The scope should reflect the area fixed (e.g., `types`, `tests`, `lint`, `build`).

#### 3g: Poll for the First Failure (do NOT block on full CI)

After pushing, update `headRefOid` to the new head commit:

```bash
gh pr view --json headRefOid --jq '.headRefOid'
```

Then **poll** the check-runs API for that SHA. Do **not** use `gh run watch`, which blocks until every job ends.

```bash
gh api repos/{owner}/{repo}/commits/<headRefOid>/check-runs \
  --jq '.check_runs[] | {name, status, conclusion}'
```

Polling rules:
- Re-check every ~30s (cap at ~10 minutes per cycle).
- **Exit polling and proceed to 3a** as soon as **any** check has `conclusion` in {`failure`, `cancelled`, `timed_out`, `action_required`}. Other jobs may still be `in_progress` — that's fine, the next cycle will re-evaluate.
- If **all** checks complete with `conclusion: success` (or `neutral`/`skipped`) → CI is green, exit the loop.
- If polling times out with no failures and no full completion → report the still-pending checks and stop, so the user can decide whether to keep waiting.

Then loop back to **3a** for the next cycle.

---

### Step 4: Report Final Status

After the loop ends (either CI passed or cycle limit reached), present a summary:

**If CI passed:**

```
✓ CI is green after <N> fix cycle(s).
  Commits pushed: <list of commit messages>
```

**If cycle limit reached:**

```
✗ CI is still failing after <N> cycle(s). Remaining failures:
  ✗ <check-name> — <description of what's still broken>

What was fixed so far:
  - Cycle 1: <commit message>
  - Cycle 2: <commit message>
  ...

Recommendation: <next steps or what to investigate>
```

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `gh pr view --json ...` | Get PR details for current branch |
| `gh run list --branch <b> --limit 10 --json ...` | List recent CI runs |
| `gh run view <id> --log-failed` | Fetch logs for failed steps |
| `gh api repos/{owner}/{repo}/commits/<sha>/check-runs` | Individual check run statuses (poll this to detect first failure) |
| `gh repo view --json nameWithOwner` | Get owner/repo slug |
| `git branch --show-current` | Get current branch |
| `but status --json` | GitButler: see workspace state and file IDs |
| `but commit <branch> -m "..." --changes <ids>` | GitButler: commit specific files |
| `but push <branch>` | GitButler: push branch |

## Tips

- Use `gh run list --branch <b> --limit 5` to check run history before deciding whether to re-run vs. fix
- `gh run view <id> --log-failed` only shows logs for failed steps — much less noise than the full log
- For flaky external checks (not GitHub Actions), the `details_url` from the check-runs API points to the external service's log
- If a cycle introduces a *new* failure that wasn't present before, note it clearly — it may be a regression from the fix
- If the same check fails with the same error across multiple cycles, escalate to the user rather than retrying the same approach
