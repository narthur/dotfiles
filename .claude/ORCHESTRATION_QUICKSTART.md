# Orchestration System Quick Start Guide

## What's Been Implemented

✅ **Phase 1 Complete**: Queue Infrastructure & Batch Approval System

The foundation is in place for autonomous development task orchestration across your 173 projects.

## How It Works

1. **Enable Projects**: Choose which projects should be orchestrated
2. **Queue Actions**: Work happens autonomously, actions queue locally
3. **Batch Approve**: Review and approve queued actions when convenient
4. **Publish**: Approved actions execute (create issues, push branches, create PRs)

## Getting Started

### 1. Enable Your First Project

```bash
# Enable a project for orchestration
claude-code /orchestrate-config enable example-api

# Set it to high priority (enables auto-execution)
claude-code /orchestrate-config priority example-api high

# Enable auto-execution of issues
claude-code /orchestrate-config auto-execute example-api on

# Verify settings
claude-code /orchestrate-config show example-api
```

### 2. Enable Projects by Family

```bash
# Enable all ProjectA projects at once
claude-code /orchestrate-config enable-family ProjectA

# Enable all ProjectB projects
claude-code /orchestrate-config enable-family ProjectB
```

### 3. View Enabled Projects

```bash
# List all projects
claude-code /orchestrate-config list

# List only enabled projects
claude-code /orchestrate-config list --enabled-only

# Count enabled projects
claude-code /orchestrate-config count
```

### 4. Approve Queued Actions

```bash
# Review and approve all queued actions
claude-code /approve

# Approve only PRs
claude-code /approve prs

# Auto-approve everything (use with caution!)
claude-code /approve --all
```

## Available Commands

### /orchestrate-config

Manage orchestration settings:

```bash
/orchestrate-config enable <project-id>           # Enable a project
/orchestrate-config disable <project-id>          # Disable a project
/orchestrate-config priority <project> <level>    # Set priority (high/medium/low)
/orchestrate-config auto-execute <project> on     # Enable auto-execution
/orchestrate-config enable-family <family>        # Enable whole family
/orchestrate-config list [--enabled-only]         # List projects
/orchestrate-config show <project-id>             # Show project details
/orchestrate-config count                         # Count enabled projects
```

### /approve

Batch approve queued actions:

```bash
/approve              # Interactive review of all queued actions
/approve issues       # Approve only issue creation
/approve branches     # Approve only branch pushes
/approve prs          # Approve only PR creation
/approve updates      # Approve only issue updates
/approve comments     # Approve only comments
/approve --all        # Auto-approve everything (no review)
```

## Priority Levels

- **high**: Process every cycle, auto-execute issues (for your most important projects)
- **medium**: Process every cycle, but no auto-execute (default, safe choice)
- **low**: Process every 3rd cycle, capture TODOs only (for low-priority projects)

## Product Families

Your projects are organized into families:

- **ProjectA**: 6+ projects (task management, API, web, SDK)
- **ProjectB**: 15+ projects (API, web, mobile, GraphQL, etc.)
- **ProjectC**: 5+ projects (integrations and tools)
- **ProjectD**: Bug tracking projects
- **ProjectE**: Garden planning projects

## File Locations

All orchestration data is stored in `~/.claude/`:

```
~/.claude/
├── approval-queue/          # Queued actions waiting for approval
├── orchestration-state/     # State tracking (TODOs, analysis, attempts)
├── orchestration-memory/    # Agent learnings and project notes
├── portfolio-registry.json  # All 173 projects metadata
└── logs/                    # Approval session logs
```

## What Happens When You Enable a Project?

1. **TODO Scanning**: The system can scan your code for TODO/FIXME comments
2. **Issue Grooming**: Open GitHub issues get analyzed and labeled (coming in Phase 2)
3. **Auto-Execution**: Simple issues get fixed automatically (coming in Phase 3)
4. **All Actions Queue**: Nothing goes to GitHub until you `/approve`

## Safety Features

✅ All actions queue locally first
✅ Nothing published to GitHub until you explicitly approve
✅ Interactive review - approve individually or by category
✅ Detailed logging of all actions
✅ Can skip any queued action
✅ Failed actions are logged and can be retried

## Coming Soon

### Phase 2: Issue Capture (Next)
- `/capture` skill to scan TODOs and create issue queue
- Smart deduplication (won't capture the same TODO twice)

### Phase 3: Autonomous Execution
- `/execute` skill to automatically fix simple issues
- Creates local branches, runs tests, queues PRs
- Learns from successes and failures

### Phase 4: Issue Grooming
- `/groom` skill to triage and label issues
- Complexity analysis
- Priority suggestions

### Phase 5: Full Orchestration Cycle
- `/orchestrate-cycle` skill to run everything
- One command: capture → groom → execute → queue → approve

### Phase 6: Cross-Project Coordination
- `/orchestrate` skill for multi-project changes
- Dependency analysis
- Coordinated releases

## Testing the System

Try manually adding a queued action to test `/approve`:

```bash
# Source the queue manager
source ~/.claude/lib/queue-manager.sh

# Add a test issue to the queue
queue_add ~/.claude/approval-queue/issues-to-create.json '{
  "id": "test-001",
  "project": "example-api",
  "type": "create-issue",
  "data": {
    "title": "Test issue from orchestration system",
    "body": "This is a test to verify the approval workflow works correctly.",
    "labels": ["test", "orchestration"]
  }
}'

# Now approve it
claude-code /approve
```

## Recommended First Steps

1. **Start Small**: Enable 1-2 high-priority projects first
   ```bash
   /orchestrate-config enable example-api
   /orchestrate-config priority example-api high
   ```

2. **Test the System**: Manually queue a test action and approve it
   ```bash
   /approve
   ```

3. **Expand Gradually**: Enable more projects as you get comfortable
   ```bash
   /orchestrate-config enable-family ProjectA
   ```

4. **Wait for Phase 2**: Once `/capture` is implemented, you can start capturing TODOs
   ```bash
   claude-code /capture scan-all --enabled-only
   ```

## Need Help?

- View this guide: `cat ~/.claude/ORCHESTRATION_QUICKSTART.md`
- View implementation status: `cat ~/.claude/orchestration-memory/IMPLEMENTATION_STATUS.md`
- Check logs: `ls -lht ~/.claude/logs/ | head`
- View registry: `jq '.projects[] | select(.orchestration.enabled == true)' ~/.claude/portfolio-registry.json`

## Questions?

The system is designed to be safe and non-blocking. You maintain full control over what gets published to GitHub. Start with a single project, test the approval workflow, and expand from there.
