---
userInvocable: true
---

# execute

Autonomously execute issues by implementing fixes, running tests, and queuing PRs for approval.

The execute skill selects executable issues from GitHub, implements fixes on local branches, runs quality checks, and queues everything for your approval via `/approve`. Nothing is pushed to GitHub until you approve it.

## Usage

```bash
# Auto-select and execute a ready issue
/execute auto

# Execute a specific issue
/execute issue <issue-number>

# Execute with specific project
/execute auto --project <project-id>

# Dry run (analyze without executing)
/execute analyze

# Execute multiple issues (up to N)
/execute auto --max <N>
```

## How It Works

1. **Fetches open issues** from GitHub for enabled projects
2. **Analyzes complexity** - calculates scores based on scope, clarity, blockers
3. **Selects executable issue** - picks simplest, clearest, unblocked issue
4. **Reads context** - loads project notes and learnings from previous attempts
5. **Creates local branch** - via GitButler (e.g., `issue-123-fix-bug`)
6. **Implements fix** - autonomously writes/modifies code
7. **Runs quality checks** - tests, linting, type checking
8. **Commits locally** - with descriptive message
9. **Queues for approval** - branch push and PR creation queued
10. **Records attempt** - logs success/failure with learnings

## Issue Selection Criteria

An issue is considered executable if ALL of these are true:

### Scope Check ✓
- Estimated lines of code < 200
- Affects ≤ 3 files
- No architectural changes mentioned
- Complexity ≤ project's max complexity setting

### Blocker Check ✓
- No "blocked" label or mentions of "blocked by"
- No open "needs clarification" comments
- Not tagged with "discussion", "design", "help wanted"
- No unresolved dependencies

### Requirements Check ✓
- Title and description are clear and specific
- Has concrete acceptance criteria OR small focused change
- No unanswered questions in recent comments

### Technical Feasibility ✓
- Relevant code files exist in repository
- Tests exist for related code (if require_tests: true)
- No mentions of missing infrastructure/access

### Project Settings ✓
- Project has `auto_execute: true`
- Project priority is "high" or "medium"
- Issue not in project's blocked_keywords list

## Complexity Levels

- **Low**: Typos, comments, logging, simple bug fixes
  - Auto-captured TODOs usually fall here
  - Estimated: < 20 lines changed

- **Medium**: Bug fixes, small features, test additions, refactoring single modules
  - Estimated: 20-100 lines changed
  - May affect 2-3 files

- **High**: New features, architectural changes, database migrations, multi-file refactors
  - Estimated: 100+ lines changed
  - Typically requires manual implementation

## Quality Checks

Before queuing, the skill runs:
- **Tests**: Detected automatically (npm test, pytest, go test, cargo test, etc.)
- **Linter**: eslint, rubocop, golangci-lint, flake8, clippy, etc.
- **Type checking**: tsc, mypy (if configured)
- **Formatting**: prettier, black, rustfmt, gofmt (if configured)

If any check fails, the skill will:
1. Analyze the error
2. Attempt to fix (up to 2 retries)
3. If still failing, record as failed attempt and move to next issue

## Learning & Memory

The skill learns from each execution:

**Successful Execution:**
- Records patterns that worked
- Notes effective approaches
- Updates project-specific insights

**Failed Execution:**
- Records why it failed
- Marks issue as too complex
- Avoids retrying same issue for 7 days

**Project Context:**
- Reads from `~/.claude/orchestration-memory/project-notes/<project>.md`
- Updates with new learnings
- Builds understanding of project conventions

## Examples

```bash
# Let the system pick and execute an issue
/execute auto

# Execute up to 3 issues
/execute auto --max 3

# Execute specific issue #42
/execute issue 42

# Analyze issues without executing
/execute analyze
```

## Configuration

Projects can configure execution in `portfolio-registry.json`:

```json
{
  "orchestration": {
    "auto_execute": true,
    "auto_execute_max_complexity": "medium",
    "require_tests": true,
    "blocked_keywords": ["needs discussion", "unclear"]
  }
}
```

## Output

The skill shows:
- Issues analyzed and their complexity scores
- Selected issue and reasoning
- Implementation progress
- Quality check results
- What was queued for approval

Then you review and approve via `/approve`.

## Safety

- ✅ All work stays local until you approve
- ✅ Creates isolated branches (never touches main)
- ✅ Runs full test suite before queuing
- ✅ Records all attempts for learning
- ✅ Won't retry recently-failed issues
- ✅ Respects project's complexity limits
- ✅ You control what gets pushed/merged

## Integration

Works seamlessly with:
- `/capture` - Execute issues created from TODOs
- `/approve` - Review and publish the work
- `/groom` - Execute groomed and labeled issues
- GitButler - Branch management
- GitHub CLI - Fetch issues, create PRs
