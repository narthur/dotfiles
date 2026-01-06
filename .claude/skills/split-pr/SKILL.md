---
name: split-pr
description: Safely split changes from the current branch into a separate pull request. Use when asked to "split this PR", "extract changes into a separate PR", "create a separate PR for X", or when a PR is too large and needs to be broken up.
---

# Split PR Skill

Safely extracts a subset of changes from your current branch into a separate, focused pull request.

## Safety Rules (CRITICAL)

### Never Do This
- **NEVER** run `git stash`, `git checkout -- .`, or `git reset --hard` when there are staged or unstaged changes
- **NEVER** use `git checkout <ref> -- <path>` to investigate other branches - this modifies the working tree

### Always Do This
- **USE READ-ONLY COMMANDS** to investigate: `git show`, `git diff`, `git log`
- **COMMIT or confirm clean state** before any branch operations
- **CREATE new branch** before modifying files

## Workflow

### Phase 1: Analyze (Read-Only)

1. **Check current state**
   ```bash
   git status
   git branch --show-current
   ```

2. **Understand what's in the PR** (compare to target branch, usually `development` or `main`)
   ```bash
   git log origin/development..HEAD --oneline
   git diff origin/development --stat
   ```

3. **Identify split candidates** - Look for:
   - Independent features or fixes
   - Backend vs frontend changes
   - Changes that don't share file dependencies
   - Self-contained refactors

4. **Investigate specific changes** (READ-ONLY - use `git show`, not `git checkout`)
   ```bash
   # View a file from another branch without modifying working tree
   git show origin/development:path/to/file.ts

   # Compare specific files
   git diff origin/development -- path/to/file.ts
   ```

### Phase 2: Plan

Present the user with:
- Recommended files/changes to split out
- Reasoning (independence, reviewability, CI compatibility)
- Any concerns about dependencies between changes

Get user approval before proceeding.

### Phase 3: Execute

1. **Ensure clean state on source branch**
   ```bash
   git status  # Must be clean or committed
   ```

2. **Create new branch from target base**
   ```bash
   git checkout -b <new-feature-branch> origin/development
   ```

3. **Apply changes using `git checkout` from source branch**
   ```bash
   # Now safe because we're on a new branch with no uncommitted work
   git checkout <source-branch> -- path/to/file1.ts path/to/file2.ts
   ```

4. **Handle renames/deletions**
   ```bash
   # For files that were renamed: delete old, add new
   git rm path/to/old-name.js
   git checkout <source-branch> -- path/to/new-name.ts
   ```

5. **Make necessary adjustments for independence**
   - Add backward-compatible exports if splitting breaks imports
   - Update types if needed
   - Ensure the split changes work standalone

### Phase 4: Verify

1. **Check TypeScript compiles**
   ```bash
   npx tsc --noEmit
   ```

2. **Check linting passes**
   ```bash
   yarn lint:eslint:fix  # or project equivalent
   ```

3. **Run tests**
   ```bash
   yarn test  # or project equivalent
   ```

4. **Review the diff**
   ```bash
   git diff origin/development --stat
   git diff origin/development  # Full diff for review
   ```

### Phase 5: Complete

1. **Commit with clear message**
   ```bash
   git commit -m "refactor: descriptive message about the split changes"
   ```

2. **Push and create draft PR**
   ```bash
   git push -u origin <new-feature-branch>
   gh pr create --draft --base development --title "..." --body "..."
   ```

3. **Report back** with:
   - PR URL
   - Summary of what was split out
   - Any notes about the remaining changes on the original branch

## Handling Problems

### If you need to abort
```bash
# If on new branch with uncommitted changes you want to discard:
git checkout <original-branch>
git branch -D <new-feature-branch>
```

### If something goes wrong
```bash
# Find lost commits
git reflog

# Recover to a previous state
git reset --soft <commit-hash>
```

## Example Session

```
User: This PR is too big. Can we split out the TypeScript controller changes?

Claude: Let me analyze the PR to identify what can be split...

[Uses git diff origin/development --stat to see all changes]
[Uses git log to understand commit structure]
[Identifies controller files as independent]

Claude: I found 12 controller files that can be split. They have no
dependencies on the other 300+ component files. Want me to proceed?

User: Yes

Claude: Creating new branch and applying changes...

[Creates branch, applies changes safely, verifies compilation]

Claude: Done! Draft PR created: https://github.com/...
- 12 files, +459/-161 lines
- TypeScript compiles ✓
- Tests pass ✓
```
