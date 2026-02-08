---
userInvocable: true
---

# approve

Batch approve and execute queued orchestration actions.

All orchestration actions (creating issues, pushing branches, creating PRs, posting comments) are queued locally until you explicitly approve them with this command. This allows the orchestration system to work autonomously in the background while you maintain control over what gets published to GitHub.

## Usage

```bash
# Review and approve all queued actions
/approve

# Approve specific category only
/approve issues
/approve branches
/approve prs
/approve updates
/approve comments

# Auto-approve all without review (use with caution)
/approve --all
```

## Interactive Review

When you run `/approve`, you'll see an organized list of all pending actions grouped by category:

- **Issues to Create**: New issues captured from TODOs or manual creation
- **Branches to Push**: Local branches ready to push to GitHub
- **PRs to Create**: Pull requests ready to open
- **Issue Updates**: Label changes, status updates, comments
- **Comments to Post**: PR/issue comments

For each category, you can:
- **[a]** Accept all items in the category
- **[r]** Review individually (approve or skip each item)
- **[s]** Skip the entire category

## Safety

- All actions are queued locally first
- Nothing is published to GitHub until you approve it
- You can review each action before it executes
- Failed executions are logged and can be retried
- Completed actions are cleared from the queue

## Examples

```bash
# Run orchestration cycle, then approve everything it queued
/orchestrate-cycle
/approve

# Only approve PRs that are ready
/approve prs

# Emergency: approve everything without review
/approve --all
```
