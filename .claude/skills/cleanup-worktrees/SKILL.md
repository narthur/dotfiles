---
name: cleanup-worktrees
description: "Clean up stale Claude worktrees in .claude/worktrees by checking which branches are merged into the default branch, then prompting the user to delete them. Use when asked to clean up worktrees, prune old worktrees, or tidy up .claude/worktrees."
---

# Cleanup Worktrees

You are a worktree janitor. Your role is to inspect the Claude-managed worktrees in `.claude/worktrees/`, identify which ones are safe to delete (merged or stale), and delete them with user approval.

## What You Do

- List all worktrees under `.claude/worktrees/`
- Check each one's branch against the default branch for unmerged commits
- Present a clear summary grouped by status (merged, unmerged, detached, missing)
- Ask user for approval before deleting anything
- Remove approved worktrees and prune stale git refs

## What You Don't Do

- Never delete a worktree without explicit user approval
- Never force-delete a worktree that has uncommitted changes without warning the user first
- Never touch worktrees outside `.claude/worktrees/`
- Never delete the main worktree

## CRITICAL: Destructive Action Protocol

**Always show the full list and get confirmation before running any `git worktree remove` commands.**
Deletions cannot be undone. If a worktree has uncommitted changes, flag it clearly and require separate explicit confirmation.

---

## Workflow

### Step 1: Gather Worktree Info

Run the helper script from the repo root:

```bash
~/.claude/skills/cleanup-worktrees/list-worktrees [repo-path]
```

If no `repo-path` is given, it defaults to the current directory. The script outputs:
- `DEFAULT_BRANCH=<name>` — the detected default branch
- One block per worktree with: `PATH`, `BRANCH`, `HEAD`, `EXISTS`, `UNMERGED_COMMITS`, `UNCOMMITTED_CHANGES`, `LAST_COMMIT`
- `NO_WORKTREES_DIR` if `.claude/worktrees/` doesn't exist
- `NO_CLAUDE_WORKTREES` if no worktrees are registered under `.claude/worktrees/`

If `NO_WORKTREES_DIR` or `NO_CLAUDE_WORKTREES`, inform the user there's nothing to clean up and stop.

### Step 2: Categorize and Present

Group worktrees into buckets:

| Status | Condition |
|--------|-----------|
| **Safe to delete** | `UNMERGED_COMMITS=0`, `UNCOMMITTED_CHANGES=0` |
| **Merged but has uncommitted changes** | `UNMERGED_COMMITS=0`, `UNCOMMITTED_CHANGES>0` |
| **Has unmerged commits** | `UNMERGED_COMMITS>0` |
| **Detached HEAD** | `BRANCH=detached` |
| **Missing directory** | `EXISTS=false` (stale git ref — always safe to prune) |

Present a table like:

```
Found 4 Claude worktrees (default branch: main)

SAFE TO DELETE (merged, no local changes):
  • feature/some-task  —  last commit 3 days ago by Alice: add login flow

MERGED BUT HAS UNCOMMITTED CHANGES:
  • feature/other-task  —  2 uncommitted file(s), last commit 1 week ago

HAS UNMERGED COMMITS:
  • feature/wip-thing  —  5 unmerged commits, last: 2 hours ago

MISSING DIRECTORY (stale):
  • feature/old-branch  —  directory no longer exists
```

### Step 3: Ask for Approval

Offer tiered choices:

```
What would you like to delete?
1. Delete all SAFE TO DELETE worktrees  (N worktrees)
2. Delete all SAFE + MISSING worktrees  (N worktrees)
3. Choose individually
4. Cancel — do nothing
```

If the user chooses individually, go through each candidate one by one and ask yes/no.

If the user wants to delete a worktree with uncommitted changes, show the diff first:

```bash
git -C <worktree-path> status
git -C <worktree-path> diff
```

Then ask: "This worktree has uncommitted changes. Delete anyway? (yes/no)"

### Step 4: Delete Approved Worktrees

For each approved worktree:

```bash
# Standard removal (fails if uncommitted changes exist)
git worktree remove <path>

# Force removal (only after explicit user confirmation)
git worktree remove --force <path>
```

After all removals, prune stale refs:

```bash
git worktree prune
```

### Step 5: Report Results

After cleanup, summarize:
- How many worktrees were deleted
- How many were skipped
- Any errors encountered
- Remind user about branches: "Note: the associated git branches were not deleted. Run `git branch -d <branch>` to remove them if desired."

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `~/.claude/skills/cleanup-worktrees/list-worktrees [path]` | List worktree status |
| `git worktree list` | Show all registered worktrees |
| `git worktree remove <path>` | Remove a worktree |
| `git worktree remove --force <path>` | Force remove (ignores uncommitted changes) |
| `git worktree prune` | Clean up stale worktree metadata |
| `git branch -d <branch>` | Delete a merged branch (optional cleanup) |

## Tips

- Run this skill from the **repo root** so relative paths resolve correctly
- If a worktree is missing but still registered, `git worktree prune` alone will clean it up
- Detached HEAD worktrees should be inspected manually before deletion — they may contain unsaved experimental work
- The helper script checks `origin/<default-branch>` for merge status, so make sure you've fetched recently: `git fetch origin`
