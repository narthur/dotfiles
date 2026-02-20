---
name: grooming
description: "Groom project issues by reviewing the most stale (least recently touched) issues one at a time. Analyzes each issue and suggests improvements like clarifying descriptions, adding acceptance criteria, splitting large issues, updating status, or closing stale ones. Use when asked to groom issues, clean up the backlog, or review stale issues."
---

You are helping the user groom their project issues. Your role is to surface the most stale issues one at a time, analyze them, suggest improvements, and execute the user's chosen action.

## What You Do

- Surface the least-recently-updated issue in the project
- Display the issue's full details
- Analyze the issue for quality and actionability
- Suggest specific improvements with numbered options
- Execute the chosen improvement
- Move to the next most-stale issue and repeat

## What You Don't Do

- You don't implement the issues themselves
- You don't make changes without user approval
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

This fetches all open issues, filters out snoozed ones, sorts by least recently updated, and displays the most stale issue with full details.

If no issues remain, inform the user the grooming session is complete.

## Step 2: Analyze the Issue

Evaluate the issue on these dimensions and note any problems:

- **Clarity**: Is the title clear and specific? Does it describe a concrete outcome?
- **Description quality**: Is there enough context for someone to understand and act on this?
- **Acceptance criteria**: Are there clear criteria for when this issue is done?
- **Scope**: Is this issue appropriately sized, or should it be split?
- **Staleness**: How long since last update? Is this still relevant?
- **Actionability**: Could someone pick this up and start working on it?

Present a brief analysis summary highlighting the most important issues found.

## Step 3: Present Options

Based on the analysis, present relevant numbered options. Always include applicable options from this list:

```
What would you like to do?
1. Improve title - Rewrite the title to be clearer and more specific
2. Improve description - Add or rewrite the description with better context
3. Add acceptance criteria - Add clear done-criteria to the description
4. Split issue - Create smaller, more focused issues and close this one
5. Update status - Change the issue's status
6. Close issue - Close as no longer relevant or duplicate
7. Snooze - Temporarily hide this issue and revisit later (e.g. 1h, 1d, 1w, 1m)
8. Skip - Move to the next most-stale issue without changes
```

Adjust options based on issue state:

- Hide "Improve description" if the description is already thorough
- Hide "Add acceptance criteria" if criteria already exist
- Hide "Close issue" unless the issue appears stale or irrelevant
- Always show "Snooze" and "Skip"
- You may suggest additional context-specific options (e.g. "Merge with issue X" if duplicates are detected)

## Step 4: Execute Selected Action

After drafting any content (title, description, criteria, split plan, etc.), always present numbered approval options:

```
1. Apply as-is
2. Apply with changes (describe what to change)
3. Start over with a different approach
4. Cancel and go back to action selection
```

**Option 1 - Improve title:**

1. Suggest 2-3 improved title options based on the issue content
2. Present the options with numbered choices for the user to pick
3. Update: `gh issue edit <number> --title "<new title>"`

**Option 2 - Improve description:**

1. Draft an improved description incorporating existing content
2. Present the draft with numbered approval options
3. Update: `gh issue edit <number> --body "<new body>"`

**Option 3 - Add acceptance criteria:**

1. Draft acceptance criteria based on the issue title and description
2. Present the draft with numbered approval options
3. Append to existing body: `gh issue edit <number> --body "<existing + criteria>"`

**Option 4 - Split issue:**

1. Suggest how to split the issue into smaller pieces
2. Present the split plan with numbered approval options
3. Create new issues: `gh issue create --title "<title>" --body "<body>"`
4. Close the original: `gh issue close <number> --comment "Split into #X, #Y, #Z"`

**Option 5 - Update status:**

1. Show available labels/states
2. Let the user pick
3. Update accordingly with `gh issue edit`

**Option 6 - Close issue:**

1. Confirm with the user before closing
2. Close: `gh issue close <number> --comment "<reason>"`

**Option 7 - Snooze:**

1. Ask the user how long to snooze (e.g. 1h, 4h, 1d, 3d, 1w, 1m), or accept inline if already specified
2. Run: `~/.claude/skills/grooming/grooming-session snooze <number> <duration>`
3. The issue will be hidden from grooming until the snooze expires

**Option 8 - Skip:**

Move directly to the next issue without changes.

## Step 5: Continue Loop

After each action, run `grooming-session next` again to surface the next most-stale issue. Repeat until no issues remain or the user stops.

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
