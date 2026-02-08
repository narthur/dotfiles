# Token Attribution for Orchestration System

## Overview

The orchestration system has been modified to ensure proper token attribution for client billing.

## How It Works

### Token Tracking Hook

Your existing `~/.claude/hooks/track-tokens.sh` tracks tokens by the **current working directory (cwd)** when a Claude Code session starts.

### Orchestration Changes

All orchestration skills now **change directory** into each project before processing:

1. **`/capture`** - Changes to project directory before scanning TODOs
2. **`/groom`** - Changes to project directory before analyzing issues
3. **`/execute`** - Changes to project directory before implementing fixes

### Token Attribution Flow

```
/orchestrate-cycle runs from ~/
├─ Coordination overhead → tracked to /home/username
├─ /capture scan project-a
│  └─ cd /path/to/project-a → tokens tracked to project-a
├─ /groom auto
│  ├─ cd /path/to/project-a → tokens tracked to project-a
│  ├─ cd /path/to/project-b → tokens tracked to project-b
│  └─ cd /path/to/project-c → tokens tracked to project-c
└─ /execute auto
   ├─ cd /path/to/project-a → tokens tracked to project-a
   └─ cd /path/to/project-b → tokens tracked to project-b
```

## Token Distribution

### Coordination Overhead (~10-20%)

Tracked to: `/home/username` (or your client mapping for home directory)

- Reading portfolio registry
- Selecting projects
- Generating summaries
- Logging cycle history

### Project-Specific Work (~80-90%)

Tracked to: Individual project directories

- **Capture**: Scanning files, parsing TODOs, extracting context
- **Groom**: Fetching issues, analyzing content, calculating priorities
- **Execute**: Analyzing complexity, implementing fixes, running tests (most expensive)

## Client Billing Setup

### Map Home Directory to Overhead

Add to `~/.claude/client-mapping.json`:

```json
{
  "clients": {
    "/home/username": "overhead",
    "/path/to/client-project-1": "client-a",
    "/path/to/client-project-2": "client-b"
  }
}
```

### Token Reports

Your token logs will show:

- `~/.claude/token-usage/_path_to_client-project-1.jsonl` - Client A's tokens
- `~/.claude/token-usage/_path_to_client-project-2.jsonl` - Client B's tokens
- `~/.claude/token-usage/_home_username.jsonl` - Overhead tokens

## Verification

To verify proper attribution after an orchestration run:

```bash
# Check which projects got tokens
ls -lth ~/.claude/token-usage/*.jsonl | head -10

# See recent token entries for a project
tail ~/.claude/token-usage/_path_to_your_project.jsonl | jq .

# Total tokens per client
jq -s 'map(.tokens.total) | add' ~/.claude/token-usage/_path_to_client_project.jsonl
```

## Important Notes

1. **Sessions Start in Project Directories**: Each skill execution that works on a project changes to that directory first
2. **Subshells Preserve Original CWD**: The orchestration script uses `(cd ... && command)` which automatically returns to the original directory
3. **Coordination Costs**: ~10-20% overhead tokens will be attributed to home directory
4. **Accurate Billing**: 80-90% of tokens (project-specific work) correctly attributed to individual projects
