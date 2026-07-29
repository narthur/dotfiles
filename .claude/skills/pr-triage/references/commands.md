# Status indicators, review decisions, worktrees, and command reference

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

`pr-review-session view`/`next` automatically checks out the PR into a per-repo triage worktree at `${XDG_CACHE_HOME:-~/.cache}/pr-triage-worktrees/<owner>-<repo>` and prints the path as `Worktree: <path>` in the summary. Use that path for any action that touches the code.

If the PR's branch is already checked out in another worktree (e.g. vibe kanban created one), the script reports that path instead of creating a duplicate. If the triage worktree has uncommitted changes, the script refuses to switch and reports the existing path — clean it up (commit/stash/discard) and re-run `view <N>` to switch.

To opt out entirely (e.g. if you don't want the script touching disk), set `PR_TRIAGE_NO_WORKTREE=1`; then fall back to `gh pr checkout <number>` in the main repo.

## Commands Reference

| Command                                     | Purpose                                                   |
| ------------------------------------------- | --------------------------------------------------------- |
| `pr-review-session list`                    | List open PRs not yet triaged this session                |
| `pr-review-session next`                    | Mark current as triaged and show next unreviewed (auto-resets when all reviewed) |
| `pr-review-session view [N]`                | Show PR summary and details; N = number or current branch |
| `pr-review-session status`                  | Show session state (repo, triaged count, current PR)      |
| `session-view pr-triage`                    | Follow the live PR view in a second terminal (PATH command; `pr-review-session watch` is an alias) |
| `pr-review-session snooze [N] <dur>`        | Snooze a PR for a duration (e.g. 1h, 1d, 1w)             |
| `pr-review-session reset`                   | Reset the triage session for this repo                    |
| `gh pr checkout <number>`                   | Manual checkout (only needed when `PR_TRIAGE_NO_WORKTREE=1`) |
| `gh pr ready <number>`                      | Mark draft as ready                                       |
| `gh pr merge <number>`                      | Merge the PR                                              |
| `gh pr close <number>`                      | Close without merging                                     |
| `gh pr edit <number> --add-reviewer <user>` | Add reviewer                                              |
| `dependabot-bump-type <number>`             | Classify a Dependabot PR's bump: `minor-patch`/`major`/`unknown` |
| `dependabot-overlap <number>`               | Exit 0 if an open human PR touches the same manifest (defer auto-merge); exit 1 if clear |
| `failing-actions`                           | List all failing actions across PRs                       |

All `pr-review-session`, `dependabot-bump-type`, and `dependabot-overlap` commands should be prefixed with the full path: `~/.claude/skills/pr-triage/`

