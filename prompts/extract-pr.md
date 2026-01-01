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

   **May I run `pr-extract-rebase` to update your branch?**

   **Do not proceed with analyzing changes until the branch is up to date.**

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

6. **Provide numbered options** (only show these if branch is up to date):

   **Option 1: Create the PR automatically**

   - Run git commands to:
     - Create new branch from `origin/<base-branch>` (use appropriate prefix: `chore/`, `docs/`, `fix/`, etc.)
     - Apply the identified changes (use appropriate method):
       - For **whole file changes**: `git checkout - -- <file>`
       - For **partial file changes**: Provide specific instructions to manually edit or use `git add -p`
       - For **new files**: Show exact commands to create/modify the file
     - Commit with descriptive conventional commit message (include `Co-Authored-By: Warp <agent@warp.dev>`)
     - Push and create PR: `git push -u origin <branch-name> && gh pr create -fd`
   - Generate and show me the complete git commands to:
     - Create a new branch from `origin/<base-branch>` (use appropriate prefix: `chore/`, `docs/`, `fix/`, etc.)
     - Apply only the identified changes
     - Commit with a descriptive message (include `Co-Authored-By: Warp <agent@warp.dev>`)
     - Push and create a PR using `gh pr create -fd`

   **Option 2: Suggest a different change**

   - Find another small, standalone change from the diff

   **Option 3: Show me the specific diff**

   - Show only the diff for the files involved in the identified change

   **Option 4: List all potential extractions**

   - Provide a numbered list of all small changes that could become separate PRs

## Important Guidelines

- Use the helper scripts for consistency and safety
- If helper scripts aren't available, fall back to manual git commands
- Branch names should be descriptive and use conventional prefixes (`chore/`, `docs/`, `fix/`, `feat/`, `refactor/`, etc.)
- Commit messages should follow conventional commits format
- Always include the `Co-Authored-By: Warp <agent@warp.dev>` trailer
- If files need to be created/modified (like .gitignore), show the exact commands needed

## Example Output Format

**If branch is behind base branch:**

⚠️ **Your branch is X commits behind origin/<base-branch>. I need to rebase your branch before extracting PRs.**

**May I run `pr-extract-rebase` to update your branch?**

---

**If branch is up to date:**

**Identified Change:** [Brief description]

**Rebase Status:** ✓ Up to date

**Why this is a good candidate:** [1-2 sentence explanation]

**Files affected:** [List of files]

**Your options:**

1. **Create PR automatically** - I'll generate the complete git workflow
2. **Suggest different change** - I'll find another extraction candidate
3. **Show specific diff** - I'll show just this change's diff
4. **List all candidates** - I'll show all possible extractions

**What would you like to do?**
