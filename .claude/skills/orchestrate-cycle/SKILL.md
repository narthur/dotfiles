---
userInvocable: true
---

# orchestrate-cycle

Run the complete autonomous orchestration workflow in one command.

This skill executes the full workflow: TODO capture → issue grooming → autonomous execution, then shows a summary and prompts you to approve all queued actions.

## Usage

```bash
# Run full cycle (execute up to 3 issues)
/orchestrate-cycle

# Run with more executions
/orchestrate-cycle --max 5

# Run with custom max executions
/orchestrate-cycle --max-execute 10
```

## What It Does

The orchestration cycle runs three phases automatically:

### Phase 1: TODO Capture
- Scans all enabled projects for TODO/FIXME/HACK comments
- Extracts context and generates issue data
- Queues issues for creation
- **Output**: N TODOs captured and queued

### Phase 2: Issue Grooming
- Fetches open issues from GitHub
- Analyzes content and suggests labels
- Calculates priorities
- Detects issues that need breakdown
- Queues label updates and comments
- **Output**: N issues groomed, M updates queued

### Phase 3: Autonomous Execution
- Selects executable issues (low complexity, unblocked)
- Creates local branches via GitButler
- Implements fixes (framework ready)
- Runs quality checks
- Queues branches and PRs
- **Output**: N issues executed and queued

### Summary & Approval
- Shows complete statistics
- Displays approval queue summary
- Prompts you to run `/approve`

## Example Output

```
=== Orchestration Cycle ===

Started at Sat Feb  8 04:00:00 PM EST 2026

Processing 5 enabled project(s)

=== Phase 1: TODO Capture ===

→ Scanning 5 enabled project(s) for TODOs...
→ Scanning: example-api
→ Scanning: example-web
→ Scanning: ProjectB-mobile
→ Scanning: third-project
→ Scanning: fourth-project-utils
✓ Capture phase complete
  → Projects scanned: 5
  → TODOs captured: 12

=== Phase 2: Issue Grooming ===

→ Grooming issues in 5 enabled project(s)...
✓ Grooming phase complete
  → Label updates queued: 24

=== Phase 3: Autonomous Execution ===

→ Executing up to 3 issue(s)...
✓ Execution phase complete
  → Issues executed: 3

=== Orchestration Cycle Summary ===

Cycle ID: cycle-1738956000
Started: 2026-02-08T16:00:00-05:00
Completed: 2026-02-08T16:05:32-05:00

Statistics:
  Projects processed: 5
  TODOs captured: 12
  Issues groomed: 24
  Issues executed: 3
  Errors: 0

Approval Queue:
  Issues to create: 12
  Branches to push: 3
  PRs to create: 3
  Issue updates: 24
  Comments to post: 2
  Total pending: 44

Ready for approval!

Review and approve queued actions:
  /approve

Full log: ~/.claude/logs/orchestration-cycle-20260208-160000.log

Orchestration cycle complete!
```

## Workflow Integration

This command ties together all the individual skills:

```
/orchestrate-cycle
    ↓
Runs /capture scan-all --enabled-only
    ↓
Runs /groom auto
    ↓
Runs /execute auto --max 3
    ↓
Shows summary
    ↓
Prompts: /approve
```

## Configuration

The cycle respects all project settings from the portfolio registry:

- **auto_capture_todos**: If true, project is scanned for TODOs
- **auto_execute**: If true, project's issues can be executed
- **priority**: high/medium/low affects processing
- **auto_execute_max_complexity**: Limits which issues get executed

## Safety

- ✅ Everything runs locally first
- ✅ All actions queued for approval
- ✅ Nothing pushed to GitHub until you approve
- ✅ Complete visibility into what was done
- ✅ Detailed logs for debugging
- ✅ Cycle history tracked

## When to Run

**Good Times:**
- Daily/weekly automated run (via cron)
- Before standup meetings
- End of day to prep work for review
- After major code changes
- When you want to clear TODO debt

**Skip If:**
- No projects enabled yet
- You want manual control of each step
- You're in the middle of complex work

## Advanced Usage

### Manual Workflow (More Control)
```bash
# Run phases individually
/capture scan-all --enabled-only
/groom auto
/execute auto --max 5
/approve
```

### Automated Workflow (Less Control)
```bash
# One command does it all
/orchestrate-cycle --max 5
/approve
```

### Scheduled Automation
```bash
# Add to crontab for daily runs
0 9 * * * cd ~ && ~/.claude/scripts/orchestration-cycle.sh 5
```

## Logs

Each cycle creates a detailed log:
- Location: `~/.claude/logs/orchestration-cycle-YYYYMMDD-HHMMSS.log`
- Contains: Full output from all phases
- Useful for: Debugging, auditing, understanding what happened

## Cycle History

All cycles are tracked in `~/.claude/orchestration-state/cycle-history.json`:

```json
[
  {
    "cycle_id": "cycle-1738956000",
    "started_at": "2026-02-08T16:00:00-05:00",
    "completed_at": "2026-02-08T16:05:32-05:00",
    "stats": {
      "projects_processed": 5,
      "todos_captured": 12,
      "issues_groomed": 24,
      "issues_executed": 3,
      "errors": 0
    }
  }
]
```

## Error Handling

If a phase encounters errors:
- Error is logged
- Error counter incremented
- Cycle continues (doesn't stop)
- Summary shows error count
- Check log file for details

## Complete System

With Phase 5, the full system is:

1. **Manual Configuration**
   - `/orchestrate-config` - Enable projects

2. **Individual Skills** (manual control)
   - `/capture` - Scan TODOs
   - `/groom` - Triage issues
   - `/execute` - Auto-fix issues

3. **Automated Workflow** (this skill)
   - `/orchestrate-cycle` - Run everything

4. **Approval & Publishing**
   - `/approve` - Review and publish

The orchestration cycle represents complete autonomous operation! 🚀
