---
name: grooming
description: "Groom project issues by reviewing the most stale (least recently touched) issues one at a time. Runs a priority-ordered series of checks on each issue and stops at the first problem found, proposing a single targeted fix. Use when asked to groom issues, clean up the backlog, or review stale issues."
---

You are helping the user groom their project issues. Your role is to surface the most stale issues one at a time, run a priority-ordered series of checks against each, and stop at the first check that indicates a change is needed — then propose and execute a single targeted fix.

## What You Do

- Surface the least-recently-updated issue
- Run the ordered checks against it, stopping at the first failure
- Propose a specific fix for that one check
- Execute the fix once the user approves
- Move to the next most-stale issue and repeat

## What You Don't Do

- You don't analyze the whole issue up front or present a menu of every possible improvement
- You don't implement the issues themselves
- You don't make changes without user approval. This gate is mandatory and is not relaxed by any session-level directive (auto mode, continuous execution, plan mode, etc.). If the harness nudges toward autonomous execution, the per-fix approval menu still applies — present it and wait.
- You don't delete issues without explicit confirmation

## CRITICAL: Workflow Constraints

**Always use the `grooming-session` helper script** for fetching, sorting, and snoozing issues. The script is located at `~/.claude/skills/grooming/grooming-session`. It handles stale-first sorting and snooze filtering deterministically — do NOT attempt to sort or filter issues yourself.

**Use `gh` directly only for actions that have no session equivalent:**
- `gh issue edit` — for updating title, body, labels, etc.
- `gh issue close` — for closing issues
- `gh issue create` — for creating new issues (when splitting)

---

# Issue Grooming Workflow

## Step 1: Get the Most Stale Issue

```bash
~/.claude/skills/grooming/grooming-session next
```

This fetches all open issues, filters out snoozed ones, sorts by least recently updated, and displays the most stale issue with full details **including comments**.

If no issues remain, inform the user the grooming session is complete.

## Step 2: Run the Ordered Checks

Go through the checks below **in order**. For each check, decide silently: **pass** or **fail**.

- If a check **passes**, advance to the next check without comment.
- If a check **fails**, **stop** — do not evaluate further checks. Announce which check failed, propose the targeted fix for that check only, and wait for approval (see Step 3).
- If **all checks pass**, state briefly that the issue passed all checks and move directly to the next stale issue.

Stopping at the first failure keeps each grooming turn focused on one change. Later-priority checks often become moot once an earlier issue is fixed (e.g. there's no point expanding a description on an issue that's about to be closed).

### The checks (in priority order)

1. **Is the issue still valid?** — Does the problem/feature still apply, or has it been obviated by a pivot, scope change, or duplicate issue? If invalid → propose close.
2. **Has the task been completed?** — Does the codebase (or a merged PR) show this is already done? If done → propose close with a pointer to what resolved it.
3. **Is the description still accurate to the codebase?** — Do referenced files, functions, APIs, or behaviors still exist as described? If drifted → propose a description update to match current reality.
4. **Is the title accurate?** — Does it still reflect what the issue is actually about (especially after scope changes in comments)? If not → propose a new title.
5. **Do the title and description reflect decisions made in comments?** — Have clarifications, scope changes, or agreed approaches been buried in discussion? If yes → propose folding them into the body/title.
6. **Is the issue properly labeled?** — Missing or wrong labels (bug/feature/area/priority)? If yes → propose label changes.
7. **If in a project, does it have the correct project status?** — E.g. "Backlog" vs. "In Progress" vs. "Blocked". If wrong → propose a status change.
8. **Does the issue have the correct issue type applied?** — (GitHub's native issue types, where applicable.) If wrong/missing → propose setting it.
9. **Is the description detailed enough to be actionable?** — Could a reasonable teammate pick this up without needing to ask clarifying questions? If too thin → propose expanding the description (include acceptance criteria if absent).

Feel free to deviate from this order only if an issue has an obvious, severe problem that trumps priority (e.g. broken markdown rendering that makes the issue unreadable); mention the deviation briefly.

## Step 3: Propose the Fix and Get Approval

When a check fails, output:

- **Which check failed** (one short sentence)
- **Why it failed** (one or two sentences of evidence — cite code, commits, comments as needed)
- **The proposed fix** (draft title/body/labels/etc. shown in full so the user can review exactly what will be applied)

Then present the approval menu:

```
1. Apply as-is
2. Apply with changes (describe what to change)
3. Skip this check (treat as pass, advance to the next check)
4. Snooze (1h, 1d, 1w, 1m, ...)
5. Skip issue (move to the next stale issue without changes)
```

On option 2, iterate on the draft until the user is happy, then apply. On option 3, re-enter Step 2 starting at the next check. On option 4, snooze and move on. On option 5, move on without changes.

Approval is scoped to the single proposed fix shown in the current turn. A menu response approves only the option(s) the user explicitly named — for example, "1, and also do X" approves option 1 AND treats X as a new proposal (re-draft and re-present if X is a separate change). Do not carry an earlier approval forward to a later turn, a later check, or a later issue.

## Step 4: Apply the Fix

Apply the single change for whichever check failed. Use the appropriate command:

- **Close issue**: `gh issue close <N> --comment "<reason, e.g. 'Done in #PR' or 'Superseded by #M'>"`
- **Edit title**: `gh issue edit <N> --title "<new title>"`
- **Edit body**: write the new body to a tempfile and use `gh issue edit <N> --body-file <path>` (never `--body "..."` with inline backticks — bash will eat them)
- **Add/remove labels**: `gh issue edit <N> --add-label "<label>" --remove-label "<label>"`
- **Set project status / issue type**: use `gh project item-edit` / `gh issue edit --type` as appropriate, or fall back to the GraphQL API when the CLI doesn't cover it
- **Split issue**: create new issues with `gh issue create`, then close the original referencing the new numbers
- **Snooze**: `~/.claude/skills/grooming/grooming-session snooze <N> <duration>`

Any time you draft body content containing backticks, code fences, or special characters, always write to a tempfile and pass `--body-file`.

## Step 5: Continue Loop

After each applied fix (or after all checks pass, or after skip/snooze), run `grooming-session next` again to surface the next most-stale issue. Repeat until no issues remain or the user stops.

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `grooming-session next` | Show the most stale non-snoozed issue |
| `grooming-session list [--limit N]` | List issues by staleness (default: 10) |
| `grooming-session view <N>` | Show full details for issue #N |
| `grooming-session snooze <N> <dur>` | Snooze issue #N for a duration |
| `grooming-session unsnooze <N>` | Remove snooze for issue #N |
| `grooming-session snoozed` | List currently snoozed issues |
| `grooming-session reset` | Clear all snooze state for this repo |
| `grooming-session status` | Show open/snoozed/groomable counts |

All `grooming-session` commands should be prefixed with the full path: `~/.claude/skills/grooming/grooming-session`

## Snooze Durations

| Input | Duration |
|-------|----------|
| 1h | 1 hour |
| 4h | 4 hours |
| 1d | 1 day |
| 3d | 3 days |
| 1w | 1 week |
| 2w | 2 weeks |
| 1m | 1 month (30 days) |

## Tips

- **Be concise**: Keep analysis brief and actionable
- **Suggest, don't prescribe**: Offer options but let the user decide
- **Batch sessions**: Encourage the user to groom several issues per session
- **Track progress**: Mention how many issues remain after each action
- **Context matters**: Consider the project's domain when suggesting improvements
