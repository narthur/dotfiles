---
name: grooming
description: "Groom project issues by reviewing the most stale (least recently touched) issues one at a time. Runs a priority-ordered series of checks on each issue, summarizes results, then walks the user through each failing check's fix one at a time for approval. Use when asked to groom issues, clean up the backlog, or review stale issues."
---

You are helping the user groom their project issues. Your role is to surface the most stale issues one at a time, run a priority-ordered series of checks against each, summarize the results, then walk through each failing check's targeted fix one at a time for the user's approval.

## What You Do

- Surface the least-recently-updated issue
- Run all the ordered checks against it
- Summarize pass/fail across all checks in one short list
- Walk the user through the failing checks' fixes one at a time, in priority order, getting approval for each
- Execute each approved fix
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

**Prefer session helpers over inline GraphQL** for these specific actions — they wrap multi-step API dances that are easy to get wrong:
- `grooming-session block <N> <B>...` — add blockedBy link(s)
- `grooming-session unblock <N> <B>` — remove a blockedBy link
- `grooming-session unassign-copilot <N>` — remove the Copilot bot while preserving other assignees (works around `gh issue edit --remove-assignee Copilot` silently no-opping)
- `grooming-session snooze-next <N> <dur>` — snooze + surface next stale issue in one call

---

# Issue Grooming Workflow

## Step 1: Get the Most Stale Issue

```bash
~/.claude/skills/grooming/grooming-session next
```

This fetches all open issues, filters out snoozed ones, sorts by least recently updated, and displays the most stale issue with full details **including comments and (when present) a "Relationships" section listing parent / sub-issues / blocked-by / blocking links** with each related issue's number, state, and title.

Treat the Relationships section as authoritative for blocker / dependency info — `gh issue view` does not surface these fields, but they are first-class metadata on the issue and should drive label and validity judgments (see checks 1 and 6).

If no issues remain, inform the user the grooming session is complete.

### Repo-specific overlay (load once at session start)

Some repos have extra, repo-specific grooming checks beyond the standard list. Before running checks on the first issue of a session, look for an overlay file at:

```
~/.claude/skills/grooming/repos/<owner>-<repo>.md
```

(same `owner/repo` → hyphen convention as the browser session name — e.g. `repos/acme-webapp.md`). If it exists, **read it once** and treat its checks as **appended to the standard checklist** for every issue this session: include them in the Step 2 summary and walk their fixes in Step 3 alongside the built-in ones. If no overlay exists, just run the standard checks. `grooming-session next` prints a one-line pointer when an overlay is present so you don't forget to load it.

### Playwright browser for issue pages

`grooming-session next` opens the issue's GitHub page in a browser as a side effect, so you and the user can look at it together.

- **One window per repo grooming session:** Session name is `grooming-<owner>-<repo>` (slashes in `owner/repo` become hyphens). Each `next` navigates that session with `goto`, so you do not accumulate tabs while stepping through issues in one repository.
- **Multiple repos at once:** Each repo gets its own named Playwright session (separate browser context / window), so parallel grooming in different clones stays isolated.
- **GitHub login (persistent profile):** The browser launches with a persistent on-disk profile per repo (`~/.playwright-auth/profiles/<owner>-<repo>`, via `--persistent --profile`). The **first** time you groom a repo the window opens logged out — just sign in to GitHub in that window and it stays logged in across every future session automatically. No state-save ritual, no expiring file. (A legacy `~/.playwright-auth/github.json`, if present, seeds a brand-new profile once.)
- **Watch the browser:** `playwright-cli show`
- **Overrides:** `GROOMING_NO_PLAYWRIGHT=1` forces the legacy Firefox new-tab behavior. `PLAYWRIGHT_CLI` sets the path to `playwright-cli` (default `~/.local/bin/playwright-cli`, then `PATH`).

## Step 2: Run All Checks and Summarize

Go through every check below for the issue. For each, decide silently: **pass** or **fail**.

After running all checks, output a short summary listing each check's status (✅ / ❌ / N/A), keeping each line to a few words. Do not propose fixes yet — the summary just orients the user before the per-fix walkthrough begins.

If **all checks pass**, state that briefly and move directly to the next stale issue.

If any checks fail, proceed to Step 3 to walk through the failing checks' fixes one at a time, in priority order.

### The checks (in priority order)

1. **Is the issue still valid?** — Does the problem/feature still apply, or has it been obviated by a pivot, scope change, or duplicate issue? Also check Relationships: if a `parent` is closed and this is a sub-issue, the parent epic may have been completed/abandoned without cleaning up children. If invalid → propose close.
2. **Has the task been completed?** — Does the codebase (or a merged PR) show this is already done? If done → propose close with a pointer to what resolved it.
3. **Is the description still accurate to the codebase?** — Do referenced files, functions, APIs, or behaviors still exist as described? If drifted → propose a description update to match current reality.
4. **Is the title accurate?** — Does it still reflect what the issue is actually about (especially after scope changes in comments)? If not → propose a new title.
5. **Do the title and description reflect decisions made in comments?** — Have clarifications, scope changes, or agreed approaches been buried in discussion? If yes → propose folding them into the body/title.
6. **Is the issue properly labeled?** — Missing or wrong labels (bug/feature/area/priority)? If yes → propose label changes. Cross-check the `blocked` label against the Relationships section: `blocked` should imply at least one open `blockedBy` link, and an open `blockedBy` link should imply the `blocked` label. Mismatches (label without link, or link without label, or label with all blockers closed) are check failures — propose either removing/adding the label or recording the missing relationship.
7. **If in a project, does it have the correct project status?** — E.g. "Backlog" vs. "In Progress" vs. "Blocked". If wrong → propose a status change.
8. **Does the issue have the correct issue type applied?** — (GitHub's native issue types, where applicable.) Don't default to one type reflexively — classify by the issue's *nature*:
   - **Bug** — describes incorrect/unexpected behavior on a real code path: wrong output, crashes, unhandled errors, silent data inconsistency, stuck/broken UI, races, leaks. If the issue narrates a way the software *misbehaves*, it's a Bug even when the fix is one line.
   - **Feature** — new functionality, a request, or an enhancement that adds capability.
   - **Task** — work with no current misbehavior: refactors, cleanup, type-tightening, extracting helpers, tests, docs, or *latent* risks the issue itself flags as "currently safe."
   The trap to avoid: small hardening / error-handling / "tighten this" issues read like chores but are **Bugs** if they fix observable broken behavior on some path. When unsure between Bug and Task, ask "does something actually misbehave today (or on a reachable error path)?" — yes → Bug, no → Task. If wrong/missing → propose setting it.
9. **Is the description detailed enough to be actionable?** — Could a reasonable teammate pick this up without needing to ask clarifying questions? If too thin → propose expanding the description (include acceptance criteria if absent).

When walking through fixes in Step 3, present them in priority order (lower-numbered checks first). The order matters because earlier fixes can make later ones moot (e.g. there's no point expanding a description on an issue that's about to be closed). Mention briefly if you skip ahead because an early fix obviates a later one.

## Step 3: Walk Through Each Failing Check's Fix

After the Step 2 summary, take the failing checks one at a time, in priority order (lowest check number first). For each, output:

- **Which check failed** (one short sentence — e.g. "Fix 1 of 3 — labels missing")
- **Why it failed** (one or two sentences of evidence — cite code, commits, comments as needed)
- **The proposed fix** (draft title/body/labels/etc. shown in full so the user can review exactly what will be applied)

Then present the approval menu:

```
1. Apply as-is
2. Apply with changes (describe what to change)
3. Skip this fix (move to the next failing check on this issue)
4. Snooze (1h, 1d, 1w, 1m, ...) — skips remaining fixes on this issue
5. Skip issue — skips remaining fixes on this issue
```

On option 1, apply the fix (Step 4), then move to the next failing check on the same issue.
On option 2, iterate on the draft until the user is happy, then apply, then move to the next failing check.
On option 3, move directly to the next failing check without applying.
On option 4, snooze the issue and stop walking through fixes for it.
On option 5, move on without changes and stop walking through fixes for it.

If applying an earlier fix obviates remaining failing checks (e.g. closing the issue makes label/body fixes moot), say so and skip them — don't waste turns proposing fixes that no longer apply.

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
- **Add blockedBy link(s)**: `~/.claude/skills/grooming/grooming-session block <N> <blocker> [<blocker>...]`
- **Remove blockedBy link**: `~/.claude/skills/grooming/grooming-session unblock <N> <blocker>`
- **Unassign Copilot**: `~/.claude/skills/grooming/grooming-session unassign-copilot <N>` (preserves other assignees)

Any time you draft body content containing backticks, code fences, or special characters, always write to a tempfile and pass `--body-file`.

## Step 5: Continue Loop

Once all failing checks for the current issue have been addressed (each one applied, skipped, or short-circuited via snooze/skip-issue) — or after Step 2 confirms all checks pass — run `grooming-session next` again to surface the next most-stale issue. Repeat until no issues remain or the user stops.

If a "passed all checks" issue surfaces again on the next call (because nothing was modified, so its position in the staleness queue didn't change), snooze it briefly to advance the queue.

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `grooming-session next` | Show the most stale non-snoozed issue |
| `grooming-session list [--limit N]` | List issues by staleness (default: 10) |
| `grooming-session view <N>` | Show full details for issue #N |
| `grooming-session snooze <N> <dur>` | Snooze issue #N for a duration |
| `grooming-session snooze-next <N> <dur>` | Snooze #N and immediately surface the next stale issue |
| `grooming-session unsnooze <N>` | Remove snooze for issue #N |
| `grooming-session snoozed` | List currently snoozed issues |
| `grooming-session block <N> <B> [<B>...]` | Add blockedBy link(s) from #N to one or more blocker issue numbers |
| `grooming-session unblock <N> <B>` | Remove a blockedBy link from #N to blocker #B |
| `grooming-session unassign-copilot <N>` | Remove Copilot bot from #N's assignees (works around gh no-op bug) |
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
