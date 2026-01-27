---
name: resolve-pr-feedback
description: Process and resolve PR review feedback comments. Retrieves feedback, validates it, implements fixes, and resolves threads. Use when the user wants to handle PR feedback, review comments, or mentions but-feedback, pr-feedback, or resolve-feedback.
---

# Resolve PR Feedback

## Detecting Workspace Type

Check the current git branch to determine which feedback command to use:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → use `but-feedback`
- Otherwise → use `pr-feedback`

## Workflow

### Step 1: Retrieve Feedback

Run the appropriate command based on workspace type:

```bash
# GitButler workspace
but-feedback --limit 1

# Standard git workflow  
pr-feedback --limit 1
```

If no unresolved feedback remains, inform the user and stop.

### Step 2: Validate Feedback

Analyze the feedback by:
1. Reading the referenced code
2. Understanding the reviewer's concern
3. Determining if the feedback is valid

**If clearly valid**: Proceed to offer options
**If clearly invalid**: Explain why and offer to resolve without changes
**If uncertain**: Present analysis and ask the user to decide

### Step 3: Present Options

Always present numbered options for next steps:

```
Next steps:
1. Fix, resolve, and commit - Implement the fix, resolve the thread, and create a commit
2. Fix only - Implement the fix without resolving or committing
3. Resolve without fix - Mark as resolved (feedback is invalid or already addressed)
4. Create follow-up issue - Create a GitHub issue to address this later
5. Skip - Move to the next feedback item
6. Stop - End the feedback review session
```

Adjust options based on context (e.g., offer "Create follow-up issue" when the fix is out of scope or requires broader changes).

### Step 4: Execute Selected Action

**Option 1 - Fix, resolve, and commit:**
1. Implement the code fix
2. Run `resolve-feedback <thread-id>`
3. Stage and commit changes using conventional commit format (see below)
4. Return to Step 1 for next feedback item

**Option 4 - Create follow-up issue:**
1. Create issue: `gh issue create --title "<title>" --body "<description>"`
2. Capture the issue number from output
3. Comment on PR: `pr-comment "Created follow-up issue #<number> to address this feedback"`
4. Resolve the thread: `resolve-feedback <thread-id>`
5. Return to Step 1 for next feedback item

### Step 5: Continue Loop

After each action, return to Step 1 to process the next feedback item until all feedback is resolved or the user chooses to stop.

## Conventional Commit Format

Use conventional commits for all commits:

```
<type>(<scope>): <description>
```

**Types:**
- `fix` - Bug fixes (most common for PR feedback)
- `feat` - New features
- `refactor` - Code changes that neither fix bugs nor add features
- `docs` - Documentation changes
- `test` - Adding or updating tests
- `chore` - Maintenance tasks

**Examples:**
```
fix(utils): add daystamp to misplaced flag detection
fix(auth): validate token expiry before API calls
refactor(api): extract common error handling logic
test(handlers): add coverage for edge cases
```

The scope should reflect the area of code changed (e.g., module name, feature area).

## Commands Reference

| Command | Purpose |
|---------|---------|
| `but-feedback [--limit N] [--all]` | Retrieve GitButler workspace feedback |
| `pr-feedback [--limit N] [--all]` | Retrieve standard PR feedback |
| `resolve-feedback <thread-id>` | Mark a feedback thread as resolved |
| `gh issue create --title "..." --body "..."` | Create a follow-up GitHub issue |
| `pr-comment "<message>"` | Add a comment to the current PR |
