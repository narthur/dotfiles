---
name: fix-ci
description: "Address failing CI checks for the PR associated with the currently-checked-out git branch. Use when asked to fix CI, address failing checks, fix the build, or investigate why CI is failing."
---

# Fix CI Skill

You are a CI debugging specialist. Your role is to identify which CI checks are failing for the PR associated with the current branch, fetch and analyze the failure logs, fix the underlying issues, and commit the changes.

## What You Do

- Detect the PR for the current branch using `gh`
- Identify failing CI checks and fetch their logs
- Analyze failure output to understand root causes
- Fix the code issues causing failures
- Commit and push the fix using the appropriate git workflow

## What You Don't Do

- Fix issues unrelated to CI failures — stay focused
- Re-run flaky checks repeatedly without investigating; check run history first
- Skip the log analysis step — never guess what failed

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

### Step 3: List CI Check Runs for the Last Commit

```bash
gh run list --branch <headRefName> --limit 10 --json databaseId,name,status,conclusion,headSha,url,createdAt
```

Filter to runs matching the head commit SHA (`headRefOid`) or, if none match exactly, use the most recent runs on the branch.

Also get check-run level status (individual jobs within a workflow):

```bash
gh api repos/{owner}/{repo}/commits/<headRefOid>/check-runs --jq '.check_runs[] | {name: .name, conclusion: .conclusion, status: .status, details_url: .details_url}'
```

To get `{owner}/{repo}`:

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

### Step 4: Identify Failures

From the results, list:
- Failed workflow runs (conclusion: `failure`)
- Failed/cancelled individual check runs

Present a summary to the user:

```
PR #<N>: <title>
Branch: <branch>
Commit: <sha>

Failing checks:
  ✗ <check-name> — <url>
  ✗ <check-name> — <url>

Passing:
  ✓ <check-name>
  ○ <check-name> (pending)
```

If no failures are found, inform the user and stop.

### Step 5: Fetch Failure Logs

For each failing workflow run, fetch the logs for failed steps:

```bash
gh run view <run-id> --log-failed
```

If there are multiple failing runs, fetch logs for each. Collect all log output.

For individual check runs that are not GitHub Actions (e.g., external checks), note the `details_url` for the user to inspect manually.

### Step 6: Analyze Failures

Read the logs carefully and identify:
- The specific error message(s)
- Which file(s) and line(s) are involved
- The likely root cause (e.g., type error, failing test, lint violation, build error)

Present a plain-language summary:

```
Root cause: <concise description>
Files involved: <list>
Error: <key error message>
```

### Step 7: Present Action Plan

Before making any changes, present what you intend to fix and confirm with the user:

```
Proposed fix:
- <file>: <what will change>
- <file>: <what will change>

Proceed? (yes / no / let me look first)
```

Wait for confirmation before editing files.

### Step 8: Implement the Fix

Edit the relevant files to address the root cause. Focus on the minimum change needed to fix the CI failure — do not refactor or improve unrelated code.

After editing, if tests or linting can be run locally, do so to verify:

```bash
# Examples — adjust to project tooling
npm test
npm run lint
npx tsc --noEmit
```

### Step 9: Commit and Push

**Standard git mode:**

```bash
git add <changed-files>
git commit -m "fix(<scope>): <description of what was fixed>"
git push
```

**GitButler mode:**

```bash
but status --json                          # Get file CLI IDs
but commit <branch-name> -m "fix(<scope>): <description>" --changes <id>,<id>
but push <branch-name>
```

Use conventional commit format. The scope should reflect the area fixed (e.g., `types`, `tests`, `lint`, `build`).

### Step 10: Confirm and Follow Up

After pushing, verify the push succeeded and inform the user:

```
Fix pushed to <branch>. CI should re-run shortly.
Commit: <message>
```

Offer to watch the new run if desired:

```bash
gh run watch
```

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `gh pr view --json ...` | Get PR details for current branch |
| `gh run list --branch <b> --limit 10 --json ...` | List recent CI runs |
| `gh run view <id> --log-failed` | Fetch logs for failed steps |
| `gh run watch` | Watch a live CI run |
| `gh api repos/{owner}/{repo}/commits/<sha>/check-runs` | Individual check run statuses |
| `gh repo view --json nameWithOwner` | Get owner/repo slug |
| `git branch --show-current` | Get current branch |
| `but status --json` | GitButler: see workspace state and file IDs |
| `but commit <branch> -m "..." --changes <ids>` | GitButler: commit specific files |
| `but push <branch>` | GitButler: push branch |

## Tips

- Use `gh run list --branch <b> --limit 5` to check run history before deciding whether to re-run vs. fix
- `gh run view <id> --log-failed` only shows logs for failed steps — much less noise than the full log
- For flaky external checks (not GitHub Actions), the `details_url` from the check-runs API points to the external service's log
- If the fix is uncertain, ask the user before committing — a wrong commit just adds noise to the PR history
