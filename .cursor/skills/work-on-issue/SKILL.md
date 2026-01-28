---
name: work-on-issue
description: Find a GitHub issue to work on, implement the fix, commit changes, and create a PR. Guides through issue selection, branch creation, implementation, and PR submission. Use when the user wants to pick up an issue, work on a bug, implement a feature, or mentions working on issues.
---

# Work on Issue

## Detecting Workspace Type

Check the current git branch to determine which git commands to use:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → use GitButler commands
- Otherwise → use standard git commands

## Workflow

### Step 1: Find Issues

Present options for finding issues:

```
How would you like to find an issue?
1. List open issues assigned to me
2. List unassigned open issues
3. List all open issues
4. Search issues by keyword
5. Enter a specific issue number
```

Execute the selected option:

| Option | Command |
|--------|---------|
| 1 | `gh issue list --assignee @me --state open` |
| 2 | `gh issue list --no-assignee --state open` |
| 3 | `gh issue list --state open --limit 20` |
| 4 | `gh issue list --search "<keyword>" --state open` |
| 5 | Skip to Step 2 with provided number |

### Step 2: Select Issue

If multiple issues were listed, present them as numbered options:

```
Select an issue to work on:
1. #42 - Fix login timeout error
2. #38 - Add dark mode support
3. #35 - Update documentation
4. Enter a different issue number
5. Search again with different criteria
6. Cancel
```

Once an issue is selected, fetch full details:

```bash
gh issue view <number>
```

### Step 3: Assess Scope

Analyze the issue to determine if it can be completed in a single PR or should be broken down.

**Signs an issue may be too large:**
- Multiple distinct features or changes required
- Touches many unrelated files or modules
- Includes both refactoring and new functionality
- Has several acceptance criteria or subtasks
- Would result in a PR that's hard to review (500+ lines)

**If the issue appears manageable**, confirm and proceed:

```
Ready to work on #<number>: <title>?
1. Yes, start working
2. View comments and discussion
3. Choose a different issue
4. Cancel
```

**If the issue appears too large**, present scoped-down options:

```
This issue looks like it may be too large for a single PR. 
Here are some ways to break it down:

1. <subset 1> - <brief description of first logical chunk>
2. <subset 2> - <brief description of second logical chunk>
3. <subset 3> - <brief description of third logical chunk>
4. Work on the full issue anyway
5. Choose a different issue
```

When presenting subsets:
- Each subset should be a coherent, independently valuable change
- Order subsets by dependency (prerequisites first)
- Include rough scope indicator (e.g., "~100 lines", "2-3 files")

**Example for a "Add user settings page" issue:**
```
This issue looks like it may be too large for a single PR.
Here are some ways to break it down:

1. Add settings route and empty page scaffold (~50 lines, 2 files)
2. Add theme preference toggle with persistence (~150 lines, 4 files)
3. Add notification preferences UI and API (~200 lines, 5 files)
4. Work on the full issue anyway
5. Choose a different issue
```

If user selects a subset, note this in the eventual PR description (e.g., "This PR addresses part of #42: adds the settings page scaffold").

### Step 4: Create Branch

**Standard git workflow:**

```bash
# Ensure we're on main and up to date
git checkout main
git pull origin main

# Create and checkout feature branch
git checkout -b <branch-name>
```

**GitButler workspace:**

```bash
# Create a new virtual branch
but branch create "<branch-name>"
```

**Branch naming convention:**
- Use format: `<issue-number>-<short-description>`
- Example: `42-fix-login-timeout`
- Keep it lowercase with hyphens

Present the proposed branch name and confirm:

```
Proposed branch name: 42-fix-login-timeout
1. Use this name
2. Use a different name
3. Cancel
```

### Step 5: Implement Changes

Analyze the issue requirements and implement the fix:

1. Read relevant code files
2. **If project has test infrastructure**: Follow TDD approach
   - Write a failing test first
   - Run tests to confirm failure
   - Implement the fix
   - Run tests to confirm pass
3. **If no test infrastructure**: Implement the fix directly
4. Verify the changes work as expected

After implementation, present options:

```
Implementation complete. What next?
1. Review changes before committing
2. Run tests
3. Commit and continue to PR
4. Make additional changes
5. Discard changes and start over
```

### Step 6: Commit Changes

**Standard git workflow:**

```bash
git add <files>
git commit -m "<message>"
```

**GitButler workspace:**

```bash
# Stage files to the branch
but rub <file> <branch-name>

# Commit to the branch
but commit <branch-name> -m "<message>"
```

**Commit message format:**
Use conventional commits referencing the issue:

```
<type>(<scope>): <description>

<issue-reference>
```

**Issue reference:**
- Use `Fixes #<number>` if this fully resolves the issue
- Use `Relates to #<number>` if this is a partial implementation (subset of the work)

**Examples:**
```
fix(auth): resolve login timeout after 30 seconds of inactivity

Fixes #42
```

```
feat(ui): add settings page scaffold

Relates to #38
```

Present commit message and confirm:

```
Proposed commit:
---
fix(auth): resolve login timeout after 30 seconds of inactivity

Fixes #42
---
1. Use this message
2. Edit the message
3. Add more changes before committing
4. Cancel
```

### Step 7: Push and Create PR

**Standard git workflow:**

```bash
git push -u origin <branch-name>
```

**GitButler workspace:**
GitButler handles pushing when creating PRs via `but pr create`.

**Create the PR:**

```bash
# Standard workflow
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<brief description of changes>

## Test Plan
<how to verify the changes work>

<issue-reference>
EOF
)"

# GitButler workflow
but pr create <branch-name>
```

**Issue reference in PR:**
- Use `Fixes #<number>` if this PR fully resolves the issue
- Use `Relates to #<number>` if this is a partial implementation (subset of the work)

Present PR details for confirmation:

```
Ready to create PR:
Title: Fix login timeout error
Body: [summary and test plan]
Issue: Fixes #42 (or "Relates to #42" if partial)

1. Create PR
2. Edit title
3. Edit body
4. Add reviewers
5. Cancel
```

After PR creation, display the PR URL.

### Step 8: Next Steps

```
PR created successfully: <url>

What would you like to do next?
1. Work on another issue
2. View the PR in browser
3. Add additional commits to this PR
4. Done
```

## Commands Reference

| Command | Purpose |
|---------|---------|
| `gh issue list` | List repository issues |
| `gh issue view <number>` | View issue details |
| `gh pr create` | Create a pull request |
| `but branch create "<name>"` | Create GitButler virtual branch |
| `but pr create <branch>` | Create PR from GitButler branch |

### Git Operations by Workspace Type

| Operation | GitButler Workspace | Standard Git |
|-----------|---------------------|--------------|
| Create branch | `but branch create "<name>"` | `git checkout -b <name>` |
| Stage files | `but rub <file> <branch>` | `git add <file>` |
| Commit | `but commit <branch> -m "..."` | `git commit -m "..."` |
| Push | (handled by `but pr create`) | `git push -u origin <branch>` |

## Tips

- **Scope creep**: If the issue reveals more work than expected, offer to create follow-up issues for out-of-scope items
- **Blocked issues**: If the issue depends on other work, inform the user and offer to find a different issue
- **Large issues**: For complex issues, offer to break them into smaller PRs
