# Claude Code Token Tracking System

A custom system for tracking Claude Code token usage across repositories and clients.

## Overview

This system automatically tracks token usage from Claude Code sessions and provides detailed reporting capabilities. It's built using bash scripts, jq for JSON processing, and Claude's hook system.

## Components

### 1. Hook Script (`~/.claude/hooks/track-tokens.sh`)

Automatically triggered at the end of each Claude Code session via the `SessionEnd` hook.

**What it does:**

- Reads session data from Claude (session ID, working directory, transcript path)
- Parses the transcript file to extract token usage metrics
- Maps repository paths to client names using the client mapping file
- Logs usage data to JSONL files

**Token metrics tracked:**
- Input tokens
- Output tokens
- Cache creation tokens
- Cache read tokens
- Total tokens
- Model used
- Session type (session vs subagent)

**Log files created:**

- Repository-specific: `~/.claude/token-usage/{repo_slug}.jsonl`
- Global: `~/.claude/token-usage/all-repos.jsonl`

### 2. Client Mapping (`~/.claude/client-mapping.json`)

Maps repository paths to client/project names for organized reporting.

**Format:**

```json
{
  "clients": {
    "/path/to/repo": "client-name",
    "/another/repo": "another-client"
  }
}
```

### 3. Reporting Script (`~/bin/get-claude-code-report`)

Command-line tool for viewing token usage statistics.

**Commands:**

```bash
# Show per-repository usage grouped by client (default)
get-claude-code-report
get-claude-code-report summary

# Show combined totals across all repositories
get-claude-code-report all

# Show usage for a specific client
get-claude-code-report client <name>

# Show usage for a specific repository
get-claude-code-report repo <path>

# List all tracked repositories
get-claude-code-report list

# Show help
get-claude-code-report help
```

### 4. Sync Script (`~/bin/sync-claude-tokens`)

Periodic scanner that catches sessions missed by the hook (e.g., crashed sessions).

**Features:**
- Scans all transcript files in `~/.claude/projects/`
- Tracks both main sessions and subagents
- Catches sessions that didn't exit cleanly
- Avoids duplicate tracking using `.tracked-sessions` file
- Can be run on-demand or via cron

**Usage:**
```bash
# Run manually to sync all untracked sessions
sync-claude-tokens

# Or set up a daily cron job
0 0 * * * ~/bin/sync-claude-tokens
```

### 5. Settings Configuration (`~/.claude/settings.json`)

Enables the token tracking hook in Claude Code for real-time tracking.

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/track-tokens.sh"
          }
        ]
      }
    ]
  }
}
```

## How It Works

The system uses a **hybrid approach** with two tracking methods:

### Real-time Hook Tracking (Primary)
1. **Session End**: When a Claude Code session exits cleanly, the `SessionEnd` hook triggers
2. **Data Extraction**: The hook script reads the session transcript and extracts token usage
3. **Client Mapping**: The repository path is matched against the client mapping
4. **Logging**: Usage data is appended to both repo-specific and global JSONL logs

### Periodic Sync (Safety Net)
1. **Scan**: The sync script periodically scans all transcript files
2. **Detection**: Identifies sessions not yet tracked (crashed sessions, subagents)
3. **Deduplication**: Uses `.tracked-sessions` file to avoid duplicate logging
4. **Catchup**: Processes and logs any missed sessions

### Reporting
- The reporting script reads and aggregates the log data on demand
- Works with data from both hook and sync sources

## Token Cost Calculation

The system calculates "effective billable tokens" using typical Claude pricing ratios:

- **Input tokens**: 1.0x (baseline)
- **Output tokens**: 3.0x (3x more expensive)
- **Cache creation**: 1.25x (25% premium)
- **Cache read**: 0.1x (90% discount)

**Formula:**

```
effective_billable = input + (output × 3) + (cache_creation × 1.25) + (cache_read × 0.1)
```

## Data Storage

All token usage data is stored in `~/.claude/token-usage/`:

- `all-repos.jsonl` - Global log containing all sessions
- `{repo_slug}.jsonl` - Per-repository logs

**Log entry format:**

```json
{
  "timestamp": "2026-02-06T12:00:00Z",
  "session_id": "abc123",
  "repo_path": "/path/to/repo",
  "client": "client-name",
  "reason": "session",
  "model": "claude-3-5-sonnet-20241022",
  "tokens": {
    "input": 1000,
    "output": 500,
    "cache_creation": 200,
    "cache_read": 5000,
    "total": 6700
  }
}
```

## Adding New Clients

To track a new client/project:

1. Edit `~/.claude/client-mapping.json`
2. Add the repository path and client name:
   ```json
   {
     "clients": {
       "/path/to/new/repo": "new-client"
     }
   }
   ```
3. Client names are automatically normalized to lowercase

## Maintenance

### Viewing Logs Directly

```bash
# View all logs
cat ~/.claude/token-usage/all-repos.jsonl | jq

# View specific repo
cat ~/.claude/token-usage/{repo_slug}.jsonl | jq
```

### Backing Up Data

```bash
# Backup all token usage data
tar -czf claude-token-usage-backup-$(date +%Y%m%d).tar.gz ~/.claude/token-usage/
```

### Clearing Old Data

```bash
# Delete all logs (be careful!)
rm -rf ~/.claude/token-usage/

# Delete specific repo logs
rm ~/.claude/token-usage/{repo_slug}.jsonl
```

## Troubleshooting

**No data showing up:**
- Check that `~/.claude/settings.json` has the SessionEnd hook configured
- Verify the hook script is executable: `chmod +x ~/.claude/hooks/track-tokens.sh`
- Run `sync-claude-tokens` to catch any missed sessions
- Check for errors in the hook script by running it manually

**Sessions with large token usage missing:**
- Likely the session crashed or was killed before exiting cleanly
- Run `sync-claude-tokens` to retroactively track these sessions
- The sync script catches all sessions regardless of how they ended

**Subagent token usage not showing:**
- The hook only tracks main sessions by default
- Run `sync-claude-tokens` to track subagent usage
- Subagents are marked with `reason: "subagent"` in logs

**Client showing as "unknown":**
- Add the repository path to `~/.claude/client-mapping.json`
- Ensure the path exactly matches the working directory during sessions
- Run `sync-claude-tokens` after updating the mapping to reprocess with correct client

**Missing jq or bc:**

```bash
# Install required dependencies
sudo apt-get install jq bc  # Debian/Ubuntu
```

## Future Enhancements

Possible improvements to the system:

- Add cost estimates in dollars based on actual pricing
- Export data to CSV for spreadsheet analysis
- Add time-based filtering (show usage for specific date ranges)
- Create visualizations/charts of usage trends
- Add alerts when usage exceeds thresholds
- Integration with invoicing/billing systems
