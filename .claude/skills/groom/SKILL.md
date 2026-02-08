---
userInvocable: true
---

# groom

Automatically triage and label GitHub issues with intelligent analysis.

The groom skill fetches unlabeled or under-labeled issues, analyzes their content, suggests appropriate labels and priorities, detects if large issues need breakdown, and queues all updates for your approval.

## Usage

```bash
# Groom all issues in enabled projects
/groom auto

# Groom specific project
/groom project <project-id>

# Groom specific issue
/groom issue <issue-number> --project <project-id>

# Show analysis without queueing updates
/groom analyze <issue-number> --project <project-id>

# Groom only unlabeled issues
/groom auto --unlabeled-only
```

## How It Works

1. **Fetches issues** from GitHub (all or unlabeled only)
2. **Analyzes content** - title, body, age, activity
3. **Suggests labels** - bug, enhancement, documentation, tech-debt, etc.
4. **Calculates priority** - critical, high, medium, low
5. **Detects complexity** - uses same analyzer as `/execute`
6. **Checks for breakdown** - identifies issues that should be split
7. **Queues updates** - all changes queued in `issues-to-update.json`
8. **Caches analysis** - stores in `issues-analyzed.json` for `/execute` to use
9. **Updates project notes** - adds patterns discovered

## Label Suggestions

The system suggests labels based on content analysis:

- **bug** - Keywords: bug, error, crash, fail, broken, issue
- **enhancement** - Keywords: add, feature, enhance, improve, new
- **documentation** - Keywords: doc, readme, comment, guide
- **tech-debt** - Keywords: refactor, cleanup, tech debt
- **performance** - Keywords: slow, optimize, speed, faster
- **security** - Keywords: vulnerability, xss, sql injection, auth
- **testing** - Keywords: test, coverage, unit test
- **ui** - Keywords: interface, design, layout, style, css
- **dependencies** - Keywords: package, upgrade, update version
- **good first issue** - Keywords: typo, simple, easy, beginner

## Priority Calculation

Priority is calculated based on:

**High Priority (+):**
- Critical/urgent/blocker keywords (+3)
- Security issues (+3)
- Bugs and crashes (+2)
- Age > 90 days (+2)
- High activity (10+ comments) (+2)

**Low Priority (-):**
- "Nice to have" or "someday" keywords (-2)
- Enhancement requests (+1 baseline)

**Result:**
- **Critical**: Score ≥ 10
- **High**: Score 8-9
- **Medium**: Score 5-7 (default)
- **Low**: Score < 5

## Breakdown Detection

Issues should be broken down if they have:
- Very long description (> 2000 chars)
- Multiple "and" in title (≥ 2)
- Many bullet points (≥ 5)
- Many numbered steps (≥ 5)
- Multiple phases/stages mentioned
- Marked as "epic" or "initiative"

When breakdown is suggested:
- System extracts potential sub-issue titles
- Queues a comment with suggestions
- Adds "needs breakdown" label

## Integration with Execute

The grooming analysis is cached and used by `/execute`:
- Pre-calculated complexity scores
- Known blockers
- Priority levels
- Makes `/execute` faster and smarter

## Examples

```bash
# Groom all enabled projects
/groom auto

# Groom only unlabeled issues
/groom auto --unlabeled-only

# Groom specific project
/groom project example-api

# Analyze specific issue without applying
/groom analyze 42 --project example-api

# After grooming, approve the changes
/approve updates
```

## Output

```
=== Issue Grooming ===

Processing 2 project(s)

→ Grooming project: example-api
  Found 15 issues to groom

  Issue #5: Fix null check in auth handler
    Labels: bug, security
    Priority: high (score: 8)
    Complexity: low
    ✓ Ready for auto-execution

  Issue #7: Refactor authentication system
    Labels: tech-debt, refactoring
    Priority: medium (score: 5)
    Complexity: high
    ⚠ Too complex for auto-execution

  Issue #12: Add feature X, Y, and Z
    Labels: enhancement
    Priority: medium (score: 6)
    Complexity: medium
    ⚠ Should be broken down (multiple tasks in title)
    Suggested sub-issues:
      1. Add feature X
      2. Add feature Y
      3. Add feature Z

  ✓ Groomed 15 issues
  ✓ Queued 18 label updates
  ✓ Queued 3 breakdown comments

=== Grooming Complete ===

Review and approve updates:
  /approve updates
```

## Configuration

Projects can customize grooming via `portfolio-registry.json`:

```json
{
  "orchestration": {
    "auto_groom": true,
    "groom_interval_days": 7,
    "priority_keywords": {
      "critical": ["prod", "production", "urgent"],
      "low": ["nice-to-have", "future"]
    }
  }
}
```

## Queued Updates

All changes are queued for approval:

- **Label additions** - Queued in `issues-to-update.json`
- **Priority labels** - e.g., "priority:high"
- **Breakdown comments** - Suggestions for splitting
- **Complexity cache** - Stored for `/execute` use

## Safety

- ✅ No changes to GitHub until you approve
- ✅ Only suggests labels (doesn't remove existing ones)
- ✅ Analysis cached for reuse
- ✅ Project notes updated with patterns
- ✅ Full control via `/approve`

## Integration

Works with:
- `/execute` - Uses cached analysis for faster selection
- `/capture` - Grooms captured TODO issues
- `/approve` - Review and apply all changes
- GitHub CLI - Fetches and updates issues
