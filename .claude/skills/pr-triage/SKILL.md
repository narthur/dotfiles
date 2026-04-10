---
name: pr-triage
description: "Go through open pull requests, check their status, and take actions to move them forward. This includes triaging PRs, fixing CI, resolving feedback, merging, or managing PR workflow. Use when asked to triage PRs, go through open PRs, or manage PR workflow."
---

You are helping the user triage their open pull requests. Your role is to assess PR status, identify blockers, and take actions to move PRs forward toward merging.

## What You Do

- Help users work through their open PRs systematically
- Assess each PR's status (CI, reviews, conflicts, feedback)
- Identify what's blocking each PR
- Execute actions to unblock PRs (fix CI, resolve feedback, request reviews, merge)
- Track progress through review sessions

## What You Don't Do

- You don't perform code reviews yourself (the user has other tooling for that)
- You don't make judgment calls about code quality
- You focus on workflow and status, not review content

## CRITICAL: Workflow Constraints

**Always use the `pr-review-session` helper script** for managing PR triage sessions. The script is located at `~/.claude/skills/pr-triage/pr-review-session`. It tracks which PRs have been reviewed, maintains session state, and provides structured workflow - do NOT use raw `gh` commands when a session command exists for the same purpose.

| Instead of... | Use... |
|---------------|--------|
| `gh pr list` | `pr-review-session list` |
| `gh pr view <N>` | `pr-review-session view <N>` |
| Manually tracking which PRs you've seen | `pr-review-session next` |

The session commands track state across the triage session. Using `gh` directly bypasses this and breaks the workflow.

**Only use `gh` commands for actions that have no session equivalent:**
- `gh pr checkout` - OK (no session equivalent)
- `gh pr merge` - OK (no session equivalent)
- `gh pr close` - OK (no session equivalent)
- `gh pr ready` - OK (no session equivalent)
- `gh pr edit --add-reviewer` - OK (no session equivalent)

### Playwright browser for PR pages

`pr-review-session` opens the PR in **Playwright** via `playwright-cli` (see the `playwright` skill) when the CLI is available. Otherwise it falls back to Firefox.

- **One tab per repo triage session:** Session name is `pr-triage-<owner>-<repo>` (slashes in `owner/repo` become hyphens). Each `view` / `next` navigates that session with `goto`, so you do not accumulate tabs while stepping through PRs in one repository.
- **Multiple repos at once:** Each repo gets its own named Playwright session (separate browser context / window), so parallel triage in different clones stays isolated.
- **GitHub login:** Playwright does not use your system browser profile. Save auth once, then reuse it:
  1. `mkdir -p ~/.playwright-auth`
  2. `playwright-cli open --headed -s=github-auth`
  3. Sign in to GitHub in the window, then confirm with the user when done.
  4. `playwright-cli state-save ~/.playwright-auth/github.json -s=github-auth`
  5. `playwright-cli close -s=github-auth`
  The triage script loads `~/.playwright-auth/github.json` into each new `pr-triage-*` session the first time that session is created. If the file is missing, the PR page may show GitHub’s sign-in UI until you complete this setup.
- **Watch the browser:** `playwright-cli show`
- **Overrides:** `PR_REVIEW_NO_PLAYWRIGHT=1` forces the legacy Firefox new-tab behavior. `PLAYWRIGHT_CLI` sets the path to `playwright-cli` (default `~/.local/bin/playwright-cli`, then `PATH`).

The `view … --web` flag still uses `gh pr view --web` (system default browser), not Playwright.

---

# PR Triage Session Workflow

Use the **pr-review-session** script to run triage sessions: it tracks which PRs have been reviewed in the current session, lists unreviewed PRs, and lets you move to the next unreviewed PR (with wrap). Run from the repository root.

## Workflow

### Step 0: Reset Session (Optional)

Before starting a new triage session, you may want to reset any existing session state:

```bash
~/.claude/skills/pr-triage/pr-review-session reset
```

This clears the session state for the current repo, allowing you to start fresh. Only do this if the user wants to start over or if starting a new triage session.

### Step 1: List Unreviewed PRs

List open PRs not yet triaged this session:

```bash
~/.claude/skills/pr-triage/pr-review-session list
```

If no unreviewed PRs, inform the user. They can run `~/.claude/skills/pr-triage/pr-review-session reset` to clear the session and start fresh, or stop.

Optional: check session state first:

```bash
~/.claude/skills/pr-triage/pr-review-session status
```

### Step 2: Select PR to Triage

- **Next unreviewed in order**: `~/.claude/skills/pr-triage/pr-review-session next` — marks the current PR as reviewed and shows the next unreviewed (wraps to first when at end).
- **Specific PR by number**: `~/.claude/skills/pr-triage/pr-review-session view <number>` — shows that PR and sets it as current for the next `next`.
- **Current branch's PR**: `~/.claude/skills/pr-triage/pr-review-session view` (no number).
- **Open in browser**: `~/.claude/skills/pr-triage/pr-review-session view <number> --web`

### Step 3: Assess PR Status

`pr-review-session view` (and `next`) already prints a summary: branch, author, status, URL, size, mergeable, CI status, reviews, and unresolved feedback count, then runs `gh pr view` for the full body. The PR is automatically opened in Playwright (named session per repo, single tab reused) when `playwright-cli` is available; otherwise Firefox. See **Playwright browser for PR pages** above.

Use that output as the assessment. If you need to re-display or analyze further, the same summary is produced by:

```bash
~/.claude/skills/pr-triage/pr-review-session view <number>
```

Infer blockers from the summary (e.g. failing CI, unresolved feedback, merge conflicts) and present them when suggesting actions.

### Step 4: Present Actions

Based on assessment, present relevant options:

```
What would you like to do?
1. Fix failing CI - Checkout branch and fix issues
2. Resolve feedback - Process unresolved review comments
3. Fix conflicts - Rebase/merge to resolve conflicts
4. Request review - Add reviewers to the PR
5. Mark ready - Convert from draft to ready for review
6. Merge PR - Merge the pull request
7. Close PR - Close without merging
8. Run CodeRabbit review - Run a local AI code review on this PR's changes
9. Request CodeRabbit review - Trigger a remote CodeRabbit review via PR comment
10. View PR in browser - Open the PR URL
11. Snooze - Temporarily hide this PR and revisit later (e.g. 1h, 1d, 1w)
12. Next - Mark reviewed and move to next unreviewed (`pr-review-session next`)
13. Reset - Reset the triage session (`pr-review-session reset`)
```

Adjust options based on PR state:

- Hide "Mark ready" if not a draft
- Hide "Merge PR" if not mergeable or has blockers
- Hide "Fix conflicts" if no conflicts
- Hide "Resolve feedback" if no unresolved comments
- Only show "Run CodeRabbit review" if the PR author is NOT the current user (check with `gh api user -q .login`; i.e., it's someone else's code)
- Only show "Request CodeRabbit review" when (1) PR author IS the current user, and (2) the `cr-needs-review` script confirms unreviewed commits exist. **Always run this check** when presenting options for the user's own PRs:
  ```bash
  ~/.claude/skills/pr-triage/cr-needs-review <number>
  # Exit 0 → needs review, SHOW the option
  # Exit 1 → already reviewed, HIDE the option
  ```

### Step 5: Execute Selected Action

**Option 1 - Fix failing CI:**

1. **Review CI run history first.** Before re-running or fixing anything, check whether the failing check has already been re-run previously. Use `gh run list --branch <branch> --limit 5` to see recent runs. If a check has already failed multiple times across different runs, it's almost certainly a real bug — don't re-run, investigate and fix instead. Only re-run if this is the first failure and it looks transient (e.g. timeout, network error, resource exhaustion).
2. Determine workspace type (GitButler or standard git)
3. Checkout the PR branch (see "Handling Git Worktrees" section if checkout fails due to worktree conflict):
   - **Standard git**: `gh pr checkout <number>`
   - **GitButler**: Check if branch exists in `but status`, if not create it
4. Identify failing checks and their logs
5. Fix the issues directly
6. After fixes, commit and push

**Option 2 - Resolve feedback:**

1. Checkout the PR branch: `gh pr checkout <number>` (see "Handling Git Worktrees" section if checkout fails)
2. Invoke the `/resolve-pr-feedback` skill to handle the rest. It has its own interactive workflow for retrieving feedback, presenting options, and implementing fixes.
3. After the skill completes, return to PR assessment.

**Option 3 - Fix conflicts:**

**IMPORTANT: Detect GitButler workspace before rebasing**

First, check if you're in a GitButler workspace:
```bash
git branch --show-current
```

**If on `gitbutler/workspace` branch (GitButler mode):**

1. Use the `/gitbutler` skill to handle the rebase:
   - The skill knows how to work with GitButler virtual branches
   - It will use `but` CLI commands to rebase the virtual branch
   - Example: `/gitbutler rebase <branch-name> onto <base-branch>`

**If on a regular git branch (standard git mode):**

1. Checkout the PR branch: `gh pr checkout <number>` (see "Handling Git Worktrees" section if checkout fails)
2. Determine the PR's actual base branch from the PR metadata — **never assume `main`**:
   ```bash
   gh pr view <number> --json baseRefName -q '.baseRefName'
   ```
3. Fetch and rebase onto `origin/<base-branch>` (always use the remote base branch, never the local one, to avoid stale state): `git fetch origin <base-branch> && git rebase origin/<base-branch>`
4. Resolve conflicts
5. Push updated branch: `git push --force-with-lease`

**Option 4 - Request review:**

```bash
gh pr edit <number> --add-reviewer <username>
```

**Option 5 - Mark ready:**

```bash
gh pr ready <number>
```

**Option 6 - Merge PR:**

```bash
gh pr merge <number> --squash  # or --merge, --rebase based on repo settings
```

**Option 7 - Close PR:**

```bash
gh pr close <number>
```

**Option 8 - Run CodeRabbit review:**

1. Checkout the PR branch: `gh pr checkout <number>` (see "Handling Git Worktrees" section if checkout fails)
2. Run the `/coderabbit:review` skill to perform a local AI code review of the PR's changes.
3. After the review completes:
   a. Write the findings to `/tmp/cr-review-pr<number>.md` wrapped in a `<details><summary>CodeRabbit Review Notes</summary>` spoiler block. Use real markdown code blocks (triple backticks with language) for any code snippets inside.
   b. Tell the user to run one of the following to copy to clipboard:
      ```bash
      cat /tmp/cr-review-pr<number>.md | xclip -selection clipboard
      # or if using xsel:
      cat /tmp/cr-review-pr<number>.md | xsel --clipboard --input
      ```
4. Present findings and offer to act on them.
5. Return to PR assessment.

**Option 9 - Request CodeRabbit review:**

1. Comment on the PR to trigger a remote CodeRabbit review:
   ```bash
   gh pr comment <number> --body "@coderabbitai review"
   ```
2. Inform the user that CodeRabbit will process the review asynchronously and results will appear as PR comments.
3. Return to PR assessment or move to next PR.

**Option 10 - View in browser:**

- **Playwright (same window as triage):** from the repo root, session name is `pr-triage-$(gh repo view --json nameWithOwner -q .nameWithOwner | tr / -)`:

  ```bash
  playwright-cli goto "$(gh pr view <number> --json url -q .url)" -s=pr-triage-$(gh repo view --json nameWithOwner -q .nameWithOwner | tr / -)
  ```

  Or run `~/.claude/skills/pr-triage/pr-review-session view <number>` again to open the current PR in that session.

- **System browser:** `gh pr view <number> --web`

**Option 11 - Snooze:**

1. Ask the user how long to snooze (e.g. 1h, 4h, 1d, 3d, 1w), or accept inline if already specified
2. Run: `~/.claude/skills/pr-triage/pr-review-session snooze <number> <duration>`
3. The PR will be hidden from the triage list until the snooze expires, then automatically reappear

### Step 6: Continue Loop

After each action:

- **Move to next unreviewed**: `~/.claude/skills/pr-triage/pr-review-session next` — marks current PR as reviewed and shows the next (wraps to first when at end).
- **Jump to another PR**: `~/.claude/skills/pr-triage/pr-review-session view <number>`
- **Reset session**: `~/.claude/skills/pr-triage/pr-review-session reset` — clears session state for this repo.
- Otherwise, return to PR assessment or `~/.claude/skills/pr-triage/pr-review-session list` based on context.

## Status Indicators

| Symbol | Meaning                    |
| ------ | -------------------------- |
| ✓      | Passing / Approved / Ready |
| ✗      | Failing / Blocked          |
| ○      | Pending / In progress      |
| ?      | Unknown / No data          |

## Review Decision Values

| Value             | Meaning                      |
| ----------------- | ---------------------------- |
| APPROVED          | PR has been approved         |
| CHANGES_REQUESTED | Changes have been requested  |
| REVIEW_REQUIRED   | Waiting for required reviews |
| (empty)           | No reviews yet               |

## Handling Git Worktrees

When using vibe kanban or similar tools that create git worktrees for feature branches, `gh pr checkout` will fail with an error like `fatal: '<branch>' is already checked out at '<path>'`.

**When checking out a PR branch, always use this approach:**

1. First try `gh pr checkout <number>`
2. If it fails due to a worktree conflict, find the existing worktree:
   ```bash
   git worktree list
   ```
3. Identify which worktree has the PR's branch checked out
4. `cd` to that worktree path and work from there instead
5. When done, `cd` back to the original repository root

This applies to all actions that require checking out a branch (Fix CI, Resolve feedback, Fix conflicts, Run CodeRabbit review).

## Commands Reference

| Command                                     | Purpose                                                   |
| ------------------------------------------- | --------------------------------------------------------- |
| `pr-review-session list`                    | List open PRs not yet triaged this session                |
| `pr-review-session next`                    | Mark current as triaged and show next unreviewed (wraps)  |
| `pr-review-session view [N] [--web]`        | Show PR summary and details; N = number or current branch |
| `pr-review-session status`                  | Show session state (repo, triaged count, current PR)      |
| `pr-review-session snooze [N] <dur>`        | Snooze a PR for a duration (e.g. 1h, 1d, 1w)             |
| `pr-review-session reset`                   | Reset the triage session for this repo                    |
| `gh pr checkout <number>`                   | Checkout PR branch (see worktree handling above)          |
| `gh pr ready <number>`                      | Mark draft as ready                                       |
| `gh pr merge <number>`                      | Merge the PR                                              |
| `gh pr close <number>`                      | Close without merging                                     |
| `gh pr edit <number> --add-reviewer <user>` | Add reviewer                                              |
| `cr-needs-review <number>`                  | Check if PR has commits not yet reviewed by CodeRabbit    |
| `failing-actions`                           | List all failing actions across PRs                       |
| `playwright-cli show`                       | Open Playwright dashboard (watch PR browser)              |
| `playwright-cli goto <url> -s=pr-triage-…`  | Open a PR in the repo’s triage Playwright session         |

All `pr-review-session` and `cr-needs-review` commands should be prefixed with the full path: `~/.claude/skills/pr-triage/`

## Tips

- **Playwright PR window**: Use `playwright-cli show` if you need to see the headed browser; triage still drives navigation via `goto` in the background.
- **Actionable only**: The session only shows PRs where you have something to do. Non-actionable PRs (e.g., waiting on someone else, no review requested from you) are automatically excluded.
- **Priority order**: PRs are automatically sorted by action priority: review > resolve conflicts > fix ci > respond > merge > add reviewers > work on. `next` always picks the highest-priority unreviewed PR.
- **Batch triage**: Use `pr-review-session next` repeatedly to work through all actionable PRs in priority order (session tracks progress)
- **Delegate**: For PRs that need author action, leave a comment and move on
- **Stale PRs**: For PRs with no activity, consider closing or requesting status updates
- **Stacked PRs**: The session only surfaces PRs targeting the default branch, so if a PR is part of a stack, it's already the next one that can land. Don't worry about the rest of the stack — treat it as an independent PR.
