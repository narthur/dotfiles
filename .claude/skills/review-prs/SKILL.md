---
name: review-prs
description: Review open PRs in a repository one by one, assess their status, and determine what's needed to push them forward. Analyzes CI status, review feedback, merge conflicts, and readiness. Use when the user wants to review PRs, triage pull requests, or mentions reviewing/checking PRs.
---

# Review PRs

Use the **pr-review-session** script to run review sessions: it tracks which PRs have been reviewed in the current session, lists unreviewed PRs, and lets you move to the next unreviewed PR (with wrap). Run from the repository root.

## Workflow

### Step 1: List Unreviewed PRs

List open PRs not yet reviewed this session:

```bash
pr-review-session list
```

If no unreviewed PRs, inform the user. They can run `pr-review-session reset` to clear the session and start fresh, or stop.

Optional: check session state first:

```bash
pr-review-session status
```

### Step 2: Select PR to Review

- **Next unreviewed in order**: `pr-review-session next` — marks the current PR as reviewed and shows the next unreviewed (wraps to first when at end).
- **Specific PR by number**: `pr-review-session view <number>` — shows that PR and sets it as current for the next `next`.
- **Current branch’s PR**: `pr-review-session view` (no number).
- **Open in browser**: `pr-review-session view <number> --web`

### Step 3: Assess PR Status

`pr-review-session view` (and `next`) already prints a summary: branch, author, status, URL, size, mergeable, CI status, reviews, and unresolved feedback count, then runs `gh pr view` for the full body.

Use that output as the assessment. If you need to re-display or analyze further, the same summary is produced by:

```bash
pr-review-session view <number>
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
7. View PR in browser - Open the PR URL
8. Next - Mark reviewed and move to next unreviewed (`pr-review-session next`)
9. Reset - Reset the review session (`pr-review-session reset`)
```

Adjust options based on PR state:

- Hide "Mark ready" if not a draft
- Hide "Merge PR" if not mergeable or has blockers
- Hide "Fix conflicts" if no conflicts
- Hide "Resolve feedback" if no unresolved comments

### Step 5: Execute Selected Action

**Option 1 - Fix failing CI:**

1. Determine workspace type (GitButler or standard git)
2. Checkout the PR branch:
   - **Standard git**: `gh pr checkout <number>`
   - **GitButler**: Check if branch exists in `but status`, if not create it
3. Identify failing checks and their logs
4. Present specific failures and offer to fix them
5. After fixes, commit and push

**Option 2 - Resolve feedback:**

1. Checkout the PR branch (if not already)
2. Invoke the resolve-pr-feedback workflow
3. Return to PR assessment when done

**Option 3 - Fix conflicts:**

1. Checkout the PR branch
2. Rebase onto base branch or merge base into branch
3. Resolve conflicts
4. Push updated branch

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

**Option 7 - View in browser:**

```bash
gh pr view <number> --web
```

### Step 6: Continue Loop

After each action:

- **Move to next unreviewed**: `pr-review-session next` — marks current PR as reviewed and shows the next (wraps to first when at end).
- **Jump to another PR**: `pr-review-session view <number>`
- **Reset session**: `pr-review-session reset` — clears session state for this repo.
- Otherwise, return to PR assessment or `pr-review-session list` based on context.

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

## Commands Reference

| Command                                     | Purpose                                                   |
| ------------------------------------------- | --------------------------------------------------------- |
| `pr-review-session list`                    | List open PRs not yet reviewed this session               |
| `pr-review-session next`                    | Mark current as reviewed and show next unreviewed (wraps) |
| `pr-review-session view [N] [--web]`        | Show PR summary and details; N = number or current branch |
| `pr-review-session status`                  | Show session state (repo, reviewed count, current PR)     |
| `pr-review-session reset`                   | Reset the review session for this repo                    |
| `gh pr checkout <number>`                   | Checkout PR branch                                        |
| `gh pr ready <number>`                      | Mark draft as ready                                       |
| `gh pr merge <number>`                      | Merge the PR                                              |
| `gh pr edit <number> --add-reviewer <user>` | Add reviewer                                              |
| `failing-actions`                           | List all failing actions across PRs                       |

## Tips

- **Batch triage**: Use `pr-review-session next` repeatedly to work through all unreviewed PRs in order (session tracks progress and wraps when at end)
- **Priority order**: Consider reviewing oldest PRs first, or those closest to being mergeable
- **Delegate**: For PRs that need author action, leave a comment and move on
- **Stale PRs**: For PRs with no activity, consider closing or requesting status updates
