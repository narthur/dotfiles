---
name: coderabbit-status
description: "Report CodeRabbit's current review status for the current PR (or a given PR). Use when the user asks where CodeRabbit is, whether CodeRabbit has finished reviewing, if CodeRabbit is rate limited/paused/still running, or for a quick CodeRabbit status check."
---

# CodeRabbit Status

You report CodeRabbit's current review state for a pull request. This is a **read-only, single-shot** status check — you determine where CodeRabbit is in its review and explain it plainly. You do **not** resolve feedback, wait/poll, request reviews, or edit any files.

## What You Do

- Resolve the target PR (current branch by default, or a PR passed as an argument)
- Run this skill's `coderabbit-status.sh` detector and report the result
- Translate the raw status into a plain-English explanation and a suggested next step

## What You Don't Do

- **Do not poll or wait** for the review to finish — that's the `wait-for-review.sh` script in the `drive-pr` skill. Report the status once and stop.
- **Do not** resolve threads, dismiss comments, request reviews, or post anything to the PR.
- **Do not** edit files or run a review loop.
- **Do not** switch branches unless the user passed an explicit PR argument (see Step 1).

If the user wants to act on CodeRabbit's feedback, point them at the `drive-pr` skill. If they want to block until the review completes, point them at `wait-for-review.sh`.

## The Detector Script

This skill **owns** the status detector — the single source of truth for combining the check signal with CodeRabbit's living first-comment status document:

```
~/.claude/skills/coderabbit-status/coderabbit-status.sh
```

The `drive-pr` skill's `wait-for-review.sh` also consumes this same script (via a sibling-skill relative path), so keep its CLI (`[--json]`) and output shape stable. Do not reimplement the detection logic anywhere else — always call this script.

## Workflow

### Step 1: Resolve Target PR

If the user passed a PR number or URL (e.g. `/coderabbit-status 123`, `/coderabbit-status #123`, or a full PR URL), switch to it first — otherwise the status reflects whatever PR matches the current branch, which may not be what they meant:

1. Extract the trailing integer as the PR number.
2. Confirm it exists and capture its head branch:
   ```bash
   gh pr view <number> --json number,headRefName,isDraft,url
   ```
3. Check it out:
   - **Standard git**: `gh pr checkout <number>`
   - **GitButler workspace** (current branch is `gitbutler/workspace`): do **not** use `gh pr checkout`. Find the matching virtual branch with `but status`; if none is applied, stop and ask rather than reporting on the wrong PR.

If **no** argument was given, use the current branch as-is — do not change branches.

### Step 2: Get the Status

Run the detector in JSON mode so you have the full picture (combined status, the two underlying signals, and any rate-limit wait time):

```bash
~/.claude/skills/coderabbit-status/coderabbit-status.sh --json
```

This returns:

```json
{ "status": "...", "check_state": "...", "comment_state": "...", "wait_seconds": 0 }
```

If the script exits non-zero (e.g. "Could not fetch PR data"), there is no PR for the current branch — tell the user that plainly and stop. Do not guess.

### Step 3: Report

Translate the `status` field into a one-line headline plus a short plain-English explanation, and suggest the natural next step. Use this mapping:

| `status`       | Headline                          | What it means / suggested next step                                                                                   |
| -------------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `not_started`  | ⚪ Not started                     | No CodeRabbit check and no comment yet. On a draft PR, CodeRabbit won't auto-review — a review must be requested.       |
| `starting_up`  | 🟡 Starting up                    | Check is pending but CodeRabbit hasn't posted yet. Give it a moment.                                                   |
| `in_progress`  | 🟡 Reviewing                      | CodeRabbit is actively reviewing right now. Check back shortly, or use `wait-for-review.sh` to block until it's done.  |
| `completed`    | 🟢 Review complete                | CodeRabbit has finished. If they want to act on findings, suggest the `drive-pr` skill.                     |
| `rate_limited` | 🟠 Rate limited                   | CodeRabbit hit a rate limit. Report the wait time from `wait_seconds` (e.g. "retry in ~Xm Ys") if it's > 0.            |
| `timed_out`    | 🔴 Timed out                      | CodeRabbit's review timed out. A fresh review would need to be requested.                                              |
| `paused`       | ⏸️ Paused                         | Auto-reviews are disabled for this PR; a manual review (`@coderabbitai review`) is needed to get one.                  |

Keep the report tight — headline, one or two sentences of explanation, and the suggested next step. Mention the underlying `check_state`/`comment_state` only if they disagree in a way worth flagging (e.g. the check passed but the comment still says reviewing) or if the user asks for detail.

For `rate_limited`, format `wait_seconds` into minutes/seconds when reporting the retry window.

Do not take any further action unless the user explicitly asks.
