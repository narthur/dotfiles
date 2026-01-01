# PR Extractor - Warp AI Saved Prompt

You are helping me extract small, self-contained changes from a larger feature branch into separate PRs.

## Prerequisites

This workflow uses helper scripts. Ensure these are installed and in your PATH:

- `pr-extract-context` - Gathers branch context (base branch, rebase status, diff stats)
- `pr-extract-rebase` - Safely rebases current branch

## Your Task

1. **Gather context**: Run `pr-extract-context` to get:

   - Base branch name (main/master/development)
   - Current branch name
   - Rebase status (commits behind)
   - Diff statistics
   - Changed files summary

2. **Check rebase status FIRST**: If the branch is behind the base branch (commits behind > 0), immediately ask the user for permission to rebase before proceeding:

   **⚠️ Your branch is X commits behind origin/<base-branch>. I need to rebase your branch before extracting PRs.**

   **Your options:**

   1. **Yes, rebase now** - I'll run `pr-extract-rebase` to update your branch
   2. **Skip rebase** - Continue without rebasing (not recommended)

   **Do not proceed with analyzing changes until the branch is up to date or user explicitly chooses to skip.**

3. **Analyze the diff** (only if branch is up to date): Run `git --no-pager diff origin/<base-branch>` to see detailed changes
4. **Identify one small change**: Find a single, self-contained change that could be its own PR.

   **Target PR size**: Aim for changes affecting **1-3 files** or **fewer than 50 lines of changes** (additions + deletions combined). Smaller is better for quick reviews.

   Prioritize changes that are:

   - Non-breaking
   - Independent of other changes
   - Low-risk (e.g., config updates, .gitignore additions, documentation, formatting, dependency updates)
   - Can be merged without the rest of the branch

5. **Explain your selection**: Briefly describe:

   - What the change is
   - Why it's a good candidate for extraction
   - What files are affected

6. **CHECKPOINT 1 - Ask permission to proceed**: After explaining the identified change, ask the user if they want to proceed with creating a branch for this change:

   **"I've identified a change to extract. Would you like me to create a new branch with these changes?"**

   **Your options:**

   1. **Yes, proceed** - I'll create a new branch and apply these changes
   2. **Show me the diff first** - I'll show only the diff for the files involved
   3. **Suggest a different change** - I'll find another extraction candidate
   4. **List all candidates** - I'll show all possible extractions

   **Do not create the branch until the user explicitly approves (option 1).**

7. **Create branch and apply changes** (only after user approval): Once approved, create the branch and apply the changes:

   - Create new branch from `origin/<base-branch>` (use appropriate prefix: `chore/`, `docs/`, `fix/`, etc.)
   - Apply the identified changes using appropriate method:
     - For **whole file changes**: `git checkout - -- <file>`
     - For **partial file changes**: Use `git add -p` or provide specific edit instructions
     - For **new files**: Create/modify the file with exact content
   - Show the user what branch was created and what changes were applied
   - **Do NOT commit, push, or create PR yet**

8. **CHECKPOINT 2 - Ask permission to create PR**: After creating the branch and applying changes, ask the user if they want to proceed with committing, pushing, and creating the PR:

   **"I've created branch `<branch-name>` and applied the changes. Would you like me to commit, push, and create the PR?"**

   **Your options:**

   1. **Yes, create the PR** - I'll commit with descriptive conventional commit message (include `Co-Authored-By: Warp <agent@warp.dev>`), push, and create PR using `gh pr create -fd`
   2. **Let me review the changes first** - I'll show the current diff/staging area
   3. **Modify the changes** - Provide feedback and I'll adjust
   4. **Cancel** - Abandon this extraction

   **Do not commit, push, or create PR until the user explicitly approves (option 1).**

9. **Create the PR** (only after user approval): Once approved, commit, push, and create the PR:

   - Commit with descriptive conventional commit message (include `Co-Authored-By: Warp <agent@warp.dev>`)
   - Push: `git push -u origin <branch-name>`
   - Create PR: `gh pr create -fd`

## Important Guidelines

- Use the helper scripts for consistency and safety
- If helper scripts aren't available, fall back to manual git commands
- **Always provide numbered options (1, 2, 3, etc.) whenever asking a question or requesting permission**
- **Always ask for permission at two checkpoints:**
  1. After identifying a change (before creating branch)
  2. After creating branch and applying changes (before committing/pushing/creating PR)
- This allows the user to provide feedback and iterate between change identification and PR creation
- Branch names should be descriptive and use conventional prefixes (`chore/`, `docs/`, `fix/`, `feat/`, `refactor/`, etc.)
- Commit messages should follow conventional commits format
- Always include the `Co-Authored-By: Warp <agent@warp.dev>` trailer
- If files need to be created/modified (like .gitignore), show the exact commands needed

## Example Output Format

**If branch is behind base branch:**

⚠️ **Your branch is X commits behind origin/<base-branch>. I need to rebase your branch before extracting PRs.**

**Your options:**

1. **Yes, rebase now** - I'll run `pr-extract-rebase` to update your branch
2. **Skip rebase** - Continue without rebasing (not recommended)

**What would you like to do?**

---

**If branch is up to date - Phase 1 (Change Identification):**

**Identified Change:** [Brief description]

**Rebase Status:** ✓ Up to date

**Why this is a good candidate:** [1-2 sentence explanation]

**Files affected:** [List of files]

**I've identified a change to extract. Would you like me to create a new branch with these changes?**

**Your options:**

1. **Yes, proceed** - I'll create a new branch and apply these changes
2. **Show me the diff first** - I'll show just this change's diff
3. **Suggest different change** - I'll find another extraction candidate
4. **List all candidates** - I'll show all possible extractions

**What would you like to do?**

---

**Phase 2 (After Branch Creation):**

**Branch created:** `<branch-name>` from `origin/<base-branch>`

**Changes applied:** [Brief summary of what was applied]

**I've created branch `<branch-name>` and applied the changes. Would you like me to commit, push, and create the PR?**

**Your options:**

1. **Yes, create the PR** - I'll commit, push, and create the PR
2. **Let me review the changes first** - I'll show the current diff/staging area
3. **Modify the changes** - Provide feedback and I'll adjust
4. **Cancel** - Abandon this extraction

**What would you like to do?**
