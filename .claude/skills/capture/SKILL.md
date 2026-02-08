---
userInvocable: true
---

# capture

Scan code for TODO/FIXME/HACK comments and queue issue creation.

The capture skill scans your enabled projects for TODO comments in code, extracts context, and queues them as GitHub issues for your approval. It intelligently avoids capturing the same TODO twice.

## Usage

```bash
# Scan all enabled projects for TODOs
/capture scan-all

# Scan only enabled projects
/capture scan-all --enabled-only

# Scan a specific project
/capture scan <project-id>

# Scan with custom patterns
/capture scan <project-id> --pattern "TODO|FIXME|HACK"

# Show statistics without capturing
/capture stats

# Clear captured TODOs for a file (if file was modified)
/capture clear-file <file-path>
```

## How It Works

1. **Scans code** for TODO/FIXME/HACK/BUG comments in source files
2. **Extracts context**: surrounding code, file location, line number
3. **Tries to identify author** using git blame
4. **Generates issue data**: title, body with context, labels
5. **Queues locally** in approval queue (no GitHub API call)
6. **Tracks captured TODOs** to prevent duplicates
7. **Waits for approval** - you review and approve via `/approve`

## Supported Comment Types

- **TODO**: General tasks → labeled as "enhancement"
- **FIXME/BUG**: Bug fixes → labeled as "bug"
- **HACK**: Code that needs refactoring → labeled as "tech-debt", "refactoring"
- **OPTIMIZE**: Performance improvements → labeled as "performance"
- **XXX**: General attention needed → labeled as "enhancement"

## File Types Scanned

Default extensions: `.ts`, `.js`, `.tsx`, `.jsx`, `.py`, `.rb`, `.go`, `.php`, `.java`, `.c`, `.cpp`, `.h`, `.rs`, `.swift`, `.kt`

Excluded directories: `node_modules`, `vendor`, `dist`, `build`, `.git`, `.next`, `coverage`, `__pycache__`, `.venv`

## Deduplication

The system tracks which TODOs have been captured in `~/.claude/orchestration-state/todos-captured.json`. Each TODO is identified by `file:line`. If a file is modified, you can clear its captured state with `/capture clear-file`.

## Examples

```bash
# Scan all your enabled projects
/capture scan-all --enabled-only

# Check what would be captured without queueing
/capture stats

# Scan a specific project
/capture scan example-api

# After scanning, approve the captured issues
/approve issues
```

## Configuration

Projects can customize TODO scanning in their `.claude/orchestration.json`:

```json
{
  "todo_scanning": {
    "enabled": true,
    "patterns": "TODO|FIXME|HACK",
    "extensions": "ts|js|tsx|jsx",
    "exclude_paths": ["tests/*", "**/*.test.ts"]
  }
}
```

## Output

The skill will show:
- How many TODOs were found
- How many were already captured (skipped)
- How many were queued for approval
- File locations of queued TODOs

Then you can review with `/approve issues`.

## Safety

- ✅ No GitHub API calls during capture
- ✅ All issues queue locally first
- ✅ You review before anything is created
- ✅ Deduplication prevents duplicates
- ✅ Can safely re-run without creating duplicates
