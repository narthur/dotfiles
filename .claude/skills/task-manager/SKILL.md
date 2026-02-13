---
name: task-manager
description: "Manage parallel tasks with git worktrees and Claude Code sessions. Track tasks through todo/doing/review/done lifecycle, create worktrees for isolated work, start and resume Claude Code sessions, create PRs, and open worktrees in Cursor. Use when asked to manage tasks, start parallel work, or track task progress."
---

You are helping the user manage parallel development tasks. Each task gets its own git worktree and can have its own Claude Code session. Your role is to loop through tasks one at a time, present context-sensitive options, and execute the user's chosen action.

## What You Do

- Surface the next actionable task (doing > review > todo priority)
- Display task details and current status
- Present context-sensitive options based on task status
- Execute the chosen action (start work, create PR, resume session, etc.)
- Loop to the next task and repeat

## What You Don't Do

- You don't implement the tasks yourself (that happens in the worktree sessions)
- You don't make changes without user approval
- You don't delete worktrees without confirmation

## CRITICAL: Workflow Constraints

**Always use the `task-session` helper script** for all task management operations. The script is located at `~/.claude/skills/task-manager/task-session`. It handles data storage, worktree management, and session tracking.

**Do NOT use raw git commands** for worktree operations when a `task-session` command exists for the same purpose.

---

# Task Manager Workflow

## Task Statuses

| Status | Meaning |
|--------|---------|
| `todo` | Task created, no work started |
| `doing` | Actively working (has worktree/session) |
| `review` | Work done, PR created, not yet merged |
| `done` | Work merged into default branch |
| `cancelled` | Task abandoned |

## Step 1: Get the Next Task

```bash
~/.claude/skills/task-manager/task-session next
```

This shows the next actionable task with priority: `doing` > `review` > `todo`.

If no actionable tasks remain, show a summary:

```bash
~/.claude/skills/task-manager/task-session summary
```

And offer to add new tasks or list all tasks.

## Step 2: Display Task Details

Show the task's full details including status, branch, worktree path, PR number, and session ID. If the task has a worktree, check if it still exists. If it has a PR, mention the PR number.

## Step 3: Present Context-Sensitive Options

Based on the task's status, present the relevant options:

### Status: `todo`

```
What would you like to do?
1. Start attempt - Create worktree and branch, begin working
2. Edit task - Change title or description
3. Cancel task - Mark as cancelled
4. Skip - Move to the next task
5. Add new task - Create a new task
```

### Status: `doing`

```
What would you like to do?
1. Resume session - Continue Claude Code session in worktree
2. Open in Cursor - Open the worktree in Cursor
3. View diff - See changes made on the task branch
4. Create PR - Push branch and create a pull request (→ review)
5. Cancel attempt - Cancel this task
6. Skip - Move to the next task
```

### Status: `review`

```
What would you like to do?
1. Check PR status - View PR details, CI, reviews
2. Open PR in browser - Open the PR URL
3. Open in Cursor - Open the worktree in Cursor
4. Mark done - Task is merged, mark as done
5. Cancel task - Cancel this task
6. Skip - Move to the next task
```

### Status: `done` or `cancelled`

```
What would you like to do?
1. Reopen - Set status back to todo
2. Clean up worktree - Remove worktree and branch
3. Skip - Move to the next task
```

### Always Available Options

In addition to status-specific options, always offer:
- **Add new task** - Create a new task
- **List all tasks** - Show all tasks, optionally filtered by status
- **Show summary** - Show counts by status

## Step 4: Execute Selected Action

**Start attempt:**
```bash
~/.claude/skills/task-manager/task-session start <id>
```
Creates a git worktree and branch. Prints instructions for starting a Claude Code session.

**Resume session:**
```bash
~/.claude/skills/task-manager/task-session resume <id>
```
Shows instructions for resuming the Claude Code session in the worktree.

**Edit task:**
```bash
~/.claude/skills/task-manager/task-session edit <id> --title "New title" --description "New desc"
```

**View diff:**
```bash
~/.claude/skills/task-manager/task-session diff <id>
```

**Create PR:**
```bash
~/.claude/skills/task-manager/task-session pr <id>
```
Pushes the branch and creates a PR using `gh`. Sets status to `review`.

**Check PR status:**
```bash
~/.claude/skills/task-manager/task-session pr-status <id>
```

**Open in Cursor:**
```bash
~/.claude/skills/task-manager/task-session open <id>
```

**Mark done:**
```bash
~/.claude/skills/task-manager/task-session done <id>
```

**Cancel task:**
```bash
~/.claude/skills/task-manager/task-session cancel <id>
```

**Clean up worktree:**
```bash
~/.claude/skills/task-manager/task-session cleanup <id>
```

**Reopen:**
```bash
~/.claude/skills/task-manager/task-session status <id> todo
```

**Add new task:**
```bash
~/.claude/skills/task-manager/task-session add "Task title" -d "Task description"
```

**List all tasks:**
```bash
~/.claude/skills/task-manager/task-session list
~/.claude/skills/task-manager/task-session list --status doing
```

**Show summary:**
```bash
~/.claude/skills/task-manager/task-session summary
```

## Step 5: Continue Loop

After each action, run `task-session next` again to surface the next actionable task. Repeat until no tasks remain or the user stops.

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `task-session add <title> [-d desc]` | Create a new task |
| `task-session list [--status S]` | List tasks, optionally filtered |
| `task-session next` | Show next actionable task |
| `task-session view <id>` | Show task details |
| `task-session edit <id> [--title] [--description]` | Edit task details |
| `task-session status <id> <status>` | Change task status |
| `task-session start <id>` | Create worktree + branch, set to doing |
| `task-session resume <id>` | Show resume instructions for session |
| `task-session pr <id>` | Create PR, set to review |
| `task-session pr-status <id>` | Check PR status via gh |
| `task-session open <id>` | Open worktree in Cursor |
| `task-session done <id>` | Mark as done |
| `task-session cancel <id>` | Cancel task |
| `task-session cleanup <id>` | Remove worktree and branch |
| `task-session summary` | Show counts by status |
| `task-session diff <id>` | Show diff for task branch |
| `task-session set-session <id> <sid>` | Store Claude session ID |

All `task-session` commands should be prefixed with the full path: `~/.claude/skills/task-manager/task-session`

## Tips

- **One at a time**: Focus on one task action, then move to the next
- **Worktree isolation**: Each task gets its own worktree so work doesn't conflict
- **Session continuity**: Use `set-session` to track Claude Code session IDs for resuming
- **Clean up**: Remove worktrees for done/cancelled tasks to save disk space
- **Batch management**: Add multiple tasks first, then work through them
