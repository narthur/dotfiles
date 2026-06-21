# Token Attribution for Orchestration System

## Overview

The orchestration system tracks token usage per repository using **git repo identifiers** (`org/repo` from the origin remote) rather than filesystem paths. This naturally handles worktrees, monorepo subdirectories, and varying mount points.

## How It Works

### Git Repo Resolution

A shared resolver (`~/.claude/hooks/resolve-git-repo.sh`) extracts the `org/repo` identifier from a directory's git origin remote URL. If the directory isn't a git repo (or has no remote), it falls back to the absolute path.

Examples:
- `/mnt/backup/code/project-a` → `OrgName/project-a`
- `/var/tmp/worktrees/feature-branch/project-a` → `OrgName/project-a`
- `/mnt/backup/code/project-b/packages/api` → `OrgName/project-b`
- `/home/username` → `/home/username` (fallback, no git remote)

### Token Tracking Hook

`~/.claude/hooks/track-tokens.sh` runs on session end and:
1. Resolves the session's cwd to an `org/repo` identifier
2. Looks up the client in `client-mapping.json` using that identifier
3. Logs token usage to per-repo and global JSONL files

### Orchestration Changes

All orchestration skills **change directory** into each project before processing:

1. **`/capture`** - Changes to project directory before scanning TODOs
2. **`/groom`** - Changes to project directory before analyzing issues
3. **`/execute`** - Changes to project directory before implementing fixes

### Token Attribution Flow

```
/orchestrate-cycle runs from ~/
├─ Coordination overhead → tracked to /home/username
├─ /capture scan project-a
│  └─ cd /path/to/project-a → resolved to org/repo-a → tokens tracked
├─ /groom auto
│  ├─ cd /path/to/project-a → resolved to org/repo-a
│  ├─ cd /path/to/project-b → resolved to org/repo-b
│  └─ cd /path/to/project-c → resolved to org/repo-c
└─ /execute auto
   ├─ cd /path/to/project-a → resolved to org/repo-a
   └─ cd /path/to/project-b → resolved to org/repo-b
```

## Client Billing Setup

### Map Repos to Clients

Add to `~/.claude/client-mapping.json`:

```json
{
  "clients": {
    "OrgName/project-a": "client-a",
    "OrgName/project-b": "client-b",
    "OrgName/project-c": "client-c",
    "/home/username": "overhead"
  }
}
```

Keys are `org/repo` identifiers (or absolute paths for non-git directories).

### Token Reports

Log files are named using the repo identifier with `/` replaced by `_`:

- `~/.claude/token-usage/OrgName_project-a.jsonl` - Client A tokens
- `~/.claude/token-usage/OrgName_project-b.jsonl` - Client B tokens
- `~/.claude/token-usage/home_username.jsonl` - Overhead tokens

## Verification

```bash
# Check which projects got tokens
ls -lth ~/.claude/token-usage/*.jsonl | head -10

# See recent token entries for a project
tail ~/.claude/token-usage/OrgName_project-a.jsonl | jq .

# Total tokens per client
jq -s 'map(.tokens.total) | add' ~/.claude/token-usage/OrgName_project-a.jsonl

# Full report
get-claude-code-report summary

# Client-specific report
get-claude-code-report client client-a
```

## Important Notes

1. **Worktrees Resolve Correctly**: All worktrees of the same repo share the same origin remote, so they map to the same `org/repo` identifier automatically
2. **Monorepo Subdirectories**: Subdirectories (e.g., `project-b/packages/api`) resolve to the same repo as the root
3. **Coordination Costs**: ~10-20% overhead tokens are attributed to the home directory
4. **Accurate Billing**: 80-90% of tokens (project-specific work) are correctly attributed to individual projects
5. **Sync Script**: Run `sync-claude-tokens` to catch sessions that didn't exit cleanly
