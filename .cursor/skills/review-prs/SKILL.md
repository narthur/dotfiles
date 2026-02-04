---
name: review-prs
description: Review open PRs in a repository one by one, assess their status, and determine what's needed to push them forward. Analyzes CI status, review feedback, merge conflicts, and readiness. Use when the user wants to review PRs, triage pull requests, or mentions reviewing/checking PRs.
---

# Review PRs

## Workflow

### Step 1: List Open PRs

Fetch open PRs for the current repository:

```bash
gh pr list --state open --json number,title,headRefName,author,isDraft,mergeable,reviewDecision,statusCheckRollup,url
```

If no open PRs, inform the user and stop.

Present the list with status indicators:

```
Open PRs in this repository:
1. #42 [draft] fix-login-timeout - Fix login timeout error (@alice)
2. #38 [ready] add-dark-mode - Add dark mode support (@bob)
3. #35 [changes requested] update-docs - Update documentation (@alice)
```

### Step 2: Select PR to Review

```
Select a PR to review:
1-N. Select a specific PR
A. Review all PRs in sequence
Q. Quit
```

### Step 3: Assess PR Status

For the selected PR, gather comprehensive status:

```bash
# Get full PR details
gh pr view <number> --json number,title,body,headRefName,author,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,reviews,url,additions,deletions,changedFiles

# Check for unresolved review feedback
gh api repos/{owner}/{repo}/pulls/<number>/comments --jq '[.[] | select(.resolved == false or .resolved == null)] | length'
```

Analyze and present findings:

```
PR #42: Fix login timeout error
Branch: fix-login-timeout
Author: @alice
Status: Draft
URL: https://github.com/owner/repo/pull/42

Assessment:
- CI Status: ✗ 2 failing checks
- Reviews: No reviews yet
- Feedback: 3 unresolved comments
- Mergeable: Has conflicts
- Size: +150 / -20 (5 files)

Blockers:
1. [CI] test-suite is failing
2. [CI] lint-check is failing
3. [Feedback] 3 unresolved review comments
4. [Conflicts] Branch has merge conflicts
```

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
8. Skip - Move to next PR
9. Stop - End the review session
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
- If reviewing all PRs, automatically move to the next one
- Otherwise, return to PR assessment or PR list based on context

## Status Indicators

| Symbol | Meaning |
|--------|---------|
| ✓ | Passing / Approved / Ready |
| ✗ | Failing / Blocked |
| ○ | Pending / In progress |
| ? | Unknown / No data |

## Review Decision Values

| Value | Meaning |
|-------|---------|
| APPROVED | PR has been approved |
| CHANGES_REQUESTED | Changes have been requested |
| REVIEW_REQUIRED | Waiting for required reviews |
| (empty) | No reviews yet |

## Commands Reference

| Command | Purpose |
|---------|---------|
| `gh pr list --state open` | List open PRs |
| `gh pr view <number>` | Get PR details |
| `gh pr checkout <number>` | Checkout PR branch |
| `gh pr ready <number>` | Mark draft as ready |
| `gh pr merge <number>` | Merge the PR |
| `gh pr edit <number> --add-reviewer <user>` | Add reviewer |
| `failing-actions` | List all failing actions across PRs |

## Tips

- **Batch triage**: Use "Review all PRs" to quickly assess the state of all open PRs
- **Priority order**: Consider reviewing oldest PRs first, or those closest to being mergeable
- **Delegate**: For PRs that need author action, leave a comment and move on
- **Stale PRs**: For PRs with no activity, consider closing or requesting status updates
