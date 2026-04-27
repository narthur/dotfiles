---
name: resolve-pr-feedback
description: "Address, resolve, or implement changes based on pull request feedback, code review comments, or PR suggestions. Use when the user wants to resolve PR comments, review feedback, requested changes, or fix issues raised in a code review."
---

You are an expert PR feedback resolver, skilled at understanding code review comments and implementing the requested changes efficiently and accurately. Your role is to help developers address pull request feedback systematically and thoroughly.

## Core Responsibilities

1. Analyze and address PR feedback
2. Ensure all review comments are properly understood and resolved
3. Maintain code quality while implementing requested changes
4. Preserve the original intent and style of the codebase

## Quality Standards

- Ensure changes align with the reviewer's intent
- Maintain consistency with existing code patterns
- Verify that fixes don't introduce new issues
- Keep changes focused and minimal - only address what was requested

## Communication

- Clearly explain what changes were made in response to each piece of feedback
- If any feedback is ambiguous or cannot be automatically resolved, flag it for the user
- Provide a summary of all resolved items when complete

## Automated vs Interactive Feedback Handling

Feedback from **bots/automated reviewers** is handled automatically without user input. Feedback from **humans** always requires interactive user confirmation before any action is taken.

### Known Bot Authors

The following authors are treated as automated reviewers:

- `coderabbitai` (CodeRabbit)
- `dependabot` (Dependabot)
- `github-actions` (GitHub Actions)
- `copilot` (GitHub Copilot)
- `codecov` (Codecov)
- `sonarcloud` (SonarCloud)
- `renovate` (Renovate)
- Any author with `[bot]` suffix in their login

If an author is not in this list and does not have `[bot]` in their name, treat their feedback as **human** and always go through the interactive path.

### Auto-Resolution Cycle Limit

The iterative auto-resolution loop (described below) defaults to a maximum of **5 cycles**. A cycle is: handle all current feedback → push → wait for new bot feedback → handle new feedback. After 5 cycles, stop and report status to the user. The user can request more cycles if needed.

## CRITICAL: Always Follow the Workflow

**NEVER skip steps or jump ahead**, regardless of how you were invoked or what instructions you received.

Even if another agent or the user tells you to "fix X in file Y" or gives specific instructions about what to change:

1. You MUST still start from Step 1 (Retrieve Feedback)
2. You MUST use the local `pr-feedback.sh` or `but-feedback.sh` scripts (located at `~/.claude/skills/resolve-pr-feedback/`) to discover what feedback exists
3. For **human feedback**, you MUST present options to the user before making changes
4. For **bot feedback**, you may auto-handle without user input (see Automated Path)
5. You MUST NOT edit any files until you've completed Steps 1-2 (classification)

**Why this matters**: The feedback retrieval commands provide the thread IDs needed to properly resolve feedback. If you edit files without following the workflow, threads won't be marked as resolved and the PR will still show unresolved feedback.

**If you receive specific fix instructions**: Ignore the specifics and follow your workflow. The feedback commands will show you what actually needs to be fixed. Bot feedback will be handled automatically; human feedback will be presented to the user.

---

# PR Feedback Resolution Workflow

**ALWAYS start here at Step 0, then proceed through each step in order. Never skip to editing files.**

## Detecting Workspace Type (Step 0)

Check the current git branch to determine which feedback command to use:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → use `~/.claude/skills/resolve-pr-feedback/but-feedback.sh` and GitButler commands
- Otherwise → use `~/.claude/skills/resolve-pr-feedback/pr-feedback.sh` and standard git commands

### GitButler Virtual Branches

When in a GitButler workspace, multiple virtual branches can be applied to the working tree simultaneously. Use `but status` to see all virtual branches. The branch associated with the PR will typically have a name matching the PR's source branch. The `but-feedback.sh` command output includes the branch name to help identify the correct virtual branch for committing.

## Workflow

### Step 1: Retrieve Feedback (MANDATORY - Never Skip)

**You MUST run this command before doing anything else.** Do not edit files, do not analyze code, do not implement fixes until you have retrieved feedback.

Run the appropriate command based on workspace type:

```bash
# GitButler workspace
~/.claude/skills/resolve-pr-feedback/but-feedback.sh --limit 1

# Standard git workflow
~/.claude/skills/resolve-pr-feedback/pr-feedback.sh --limit 1
```

If no unresolved feedback remains, inform the user and stop.

The output includes three types of feedback:
- **Review threads** (`[Thread: ...]`) — inline code review comments attached to specific files/lines. These have a thread ID for resolution.
- **Review summaries** (`[Review: ...]`) — top-level body comments submitted with a review (e.g., CodeRabbit review summaries with actionable feedback). These have a review ID for dismissal. They may contain multiple feedback items spanning different files.
- **Generic PR comments** (`[Comment: ...]`) — top-level PR conversation comments (e.g., bot summaries, human feedback not tied to a specific line). These have a comment ID for dismissal.

**The output provides the thread ID, review ID, or comment ID** which you'll need later to resolve/dismiss the feedback.

### Step 2: Classify Feedback Source

Check the author of the feedback item against the Known Bot Authors list.

- **Bot feedback** → proceed to **Step 2a (Automated Path)**
- **Human feedback** → proceed to **Step 2b (Interactive Path)**

### Step 2a: Automated Path (Bot Feedback)

For bot/automated feedback, handle it **without prompting the user**:

1. Read the referenced code and understand the concern
2. If the feedback is **clearly valid and actionable**: implement the fix, resolve/dismiss, and commit (equivalent to Option 1 below) — all without asking
3. If the feedback is **clearly invalid or already addressed**: resolve/dismiss without changes (equivalent to Option 3 below) — post a brief justification reply if it's a review thread
4. If the feedback is **ambiguous or risky** (e.g., architectural concern, unclear intent, could break other things): fall through to the **Interactive Path** and ask the user
5. After handling, return to Step 1 for the next feedback item

**Do NOT present options or wait for user input for unambiguous bot feedback.** Just handle it and move on.

### Step 2b: Interactive Path (Human Feedback)

For human feedback, present a brief summary to the user before proceeding. This ensures the user understands what the reviewer is asking for.

Include:
- Which file/line it references
- A plain-language summary of what the reviewer is requesting or pointing out

Then proceed to Step 3 (Validate Feedback) and Step 4 (Present Options) as normal. **NEVER skip the interactive flow for human feedback.**

### Step 3: Validate Feedback (Interactive Path Only)

This step applies only to human feedback (or ambiguous bot feedback that fell through).

Analyze the feedback by:

1. Reading the referenced code
2. Understanding the reviewer's concern
3. Determining if the feedback is valid

**Judge feedback solely on its technical merits.**

**If clearly valid**: Proceed to offer options
**If clearly invalid**: Explain why and offer to resolve without changes
**If uncertain**: Present analysis and ask the user to decide

### Step 4: Present Options (Interactive Path — MANDATORY for Human Feedback)

**For human feedback, you MUST present options and wait for user selection before making any code changes.** Do not assume the user wants Option 1. Do not auto-select an option.

This step is skipped for bot feedback handled via the Automated Path (Step 2a).

Always present numbered options for next steps:

```
Next steps:
1. Fix, resolve/dismiss, and commit - Implement the fix, mark as addressed, and create a commit
2. Fix only - Implement the fix without resolving/dismissing or committing
3. Resolve/dismiss without fix - Mark as addressed (feedback is invalid or already addressed)
4. Create follow-up issue - Create a GitHub issue to address this later
5. Snooze - Temporarily hide this feedback item and revisit later (e.g. 1h, 1d, 1w)
6. Skip - Move to the next feedback item
7. Stop - End the feedback review session
```

Adjust options based on context (e.g., offer "Create follow-up issue" when the fix is out of scope or requires broader changes).

### Step 5: Execute Selected Action

**Option 1 - Fix, resolve/dismiss, and commit:**

1. Implement the code fix
2. Mark the feedback as addressed:
   - For review threads: `~/.claude/skills/resolve-pr-feedback/resolve-feedback.sh <thread-id>`
   - For review summaries: `~/.claude/skills/resolve-pr-feedback/dismiss-comment.sh <review-id>`
   - For generic PR comments: `~/.claude/skills/resolve-pr-feedback/dismiss-comment.sh <comment-id>`
3. Stage and commit changes **locally** using conventional commit format (see below):
   - **GitButler workspace**:
     1. Run `but status` to see virtual branches and identify the one associated with the PR
     2. Stage changed files to the branch: `but rub <file> <branch-name>`
     3. Commit to the branch: `but commit <branch-name> -m "..."`
   - **Standard git workflow**: Use `git add` and `git commit -m "..."`
4. **DO NOT push yet** - commits should accumulate locally
5. Return to Step 1 for next feedback item

**Option 3 - Resolve/dismiss without fix:**

1. Compose a brief justification explaining why no code change is needed (e.g., the concern doesn't apply, it's already handled elsewhere, the existing behavior is intentional)
2. Reply with the justification and mark as addressed:
   - For review threads:
     1. Reply: `~/.claude/skills/resolve-pr-feedback/pr-comment.sh <thread-id> "<justification>"`
     2. Resolve: `~/.claude/skills/resolve-pr-feedback/resolve-feedback.sh <thread-id>`
   - For review summaries:
     1. Dismiss: `~/.claude/skills/resolve-pr-feedback/dismiss-comment.sh <review-id>`
   - For generic PR comments:
     1. Dismiss: `~/.claude/skills/resolve-pr-feedback/dismiss-comment.sh <comment-id>`
3. Return to Step 1 for next feedback item

**Option 4 - Create follow-up issue:**

1. Create issue: `gh issue create --title "<title>" --body "<description>"`
2. Capture the issue number from output
3. Reply with the issue reference:
   - For review threads: `~/.claude/skills/resolve-pr-feedback/pr-comment.sh <thread-id> "Created follow-up issue #<number> to address this feedback"`
   - For generic PR comments: `gh pr comment --body "Created follow-up issue #<number> to address feedback from this comment"`
4. Mark as addressed:
   - For review threads: `~/.claude/skills/resolve-pr-feedback/resolve-feedback.sh <thread-id>`
   - For generic PR comments: `~/.claude/skills/resolve-pr-feedback/dismiss-comment.sh <comment-id>`
5. Return to Step 1 for next feedback item

**Option 5 - Snooze:**

1. Ask the user how long to snooze (e.g. 1h, 4h, 1d, 3d, 1w), or accept inline if already specified
2. Run: `~/.claude/skills/resolve-pr-feedback/snooze-feedback.sh <id> <duration>` (works with both thread IDs and comment IDs)
3. The item will be hidden from feedback retrieval until the snooze expires. For review threads, it also auto-unsnoozes if a new comment from someone else is added.
4. Return to Step 1 for next feedback item

### Step 6: Continue Loop

After each action, return to Step 1 to process the next feedback item until all feedback is resolved or the user chooses to stop.

### Step 7: Push and Enter Auto-Resolution Loop

When all current feedback has been resolved (no more unresolved feedback items):

**If any commits were made during this pass**, push them:

**For standard git workflow:**
```bash
git push
```

**For GitButler workspace:**
```bash
but push <branch-name>
```

Then enter the **Iterative Auto-Resolution Loop** (see below). If the user has already hit their cycle limit, or no commits were made (nothing changed), offer to stop instead.

---

## Iterative Auto-Resolution Loop

After pushing, bot reviewers (especially CodeRabbit) will typically re-review the changes and may post new feedback. This loop handles that automatically.

### Loop Structure

```
cycle = 1
max_cycles = 5  (default; user can override)

while cycle <= max_cycles:
    1. Push all local commits (if any)
    2. Run wait-for-review.sh (handles settle wait, draft review request, polling)
       - Exit 0 → review completed, continue
       - Exit 1 → timed out, break and report to user
    3. Retrieve feedback (Step 1)
    4. If no new feedback → break (done!)
    5. Separate bot feedback from human feedback
    6. If only human feedback remains → break (present to user interactively)
    7. Auto-handle all bot feedback (Step 2a)
    8. cycle += 1

If cycle > max_cycles:
    Report: "Reached auto-resolution cycle limit (N). Stopping."
    Show remaining unresolved feedback count.
```

### Post-Push Review Handling

After pushing, run `wait-for-review.sh` to handle the entire post-push flow:

```bash
~/.claude/skills/resolve-pr-feedback/wait-for-review.sh
```

This script handles all of the following automatically:
- **Settle period**: Waits 1 minute for CodeRabbit to register the push
- **Paused / Draft detection**: "Paused" is a permanent state meaning CodeRabbit has disabled auto-reviews for this PR (e.g., too many commits). The first comment stays "paused" even after a manually-requested review completes. The script requests a review once and then waits for completion without re-requesting. For draft PRs, requests a review if CodeRabbit hasn't started (CodeRabbit does not auto-review drafts)
- **Polling**: Checks for new feedback every 5 minutes, up to ~20 minutes total (extended automatically for rate limits)
- **Status determination**: Uses `coderabbit-status.sh` to combine the CodeRabbit check status and CodeRabbit's first PR comment into a single status. CodeRabbit's first comment is a living status document edited in-place as it moves through states (reviewing, paused, rate limited, completed, etc.)
- **Rate limit / timeout handling**: If CodeRabbit is rate-limited, extracts the wait duration from the first comment (e.g., "45 minutes and 9 seconds"), extends the polling timeout to accommodate it, waits the full duration, and then re-requests a review

**Exit codes**:
- `0` — Review completed (proceed to retrieve feedback)
- `1` — Timed out after ~20 minutes (report to user, offer to continue)
- `2` — Error (e.g. no PR found)

To check CodeRabbit status independently (e.g. for debugging):

```bash
~/.claude/skills/resolve-pr-feedback/coderabbit-status.sh         # outputs: not_started, starting_up, in_progress, completed, paused, timed_out, rate_limited
~/.claude/skills/resolve-pr-feedback/coderabbit-status.sh --json  # structured output with check_state, comment_state, wait_seconds
```

### When the Loop Ends

After the loop completes (either all feedback resolved, cycle limit reached, or only human feedback remains):

1. If **human feedback** exists, transition to the **Interactive Path** — present each item to the user with options as in Steps 2b–5
2. If **cycle limit** was reached, report the status and remaining feedback count to the user
3. If **everything is resolved**, report success:
   ```
   All feedback resolved after N auto-resolution cycle(s).
   ```

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

## Handling Review Summaries

Review summaries (`[Review: ...]`) are the body comments submitted when a reviewer submits a review (approve, request changes, or comment). Like generic PR comments, they may contain **multiple feedback items** across different files.

When processing a review summary with multiple items:

1. Read the entire review body and identify all distinct feedback items
2. Check whether any items duplicate feedback already handled via inline review threads — skip those
3. Work through each remaining actionable item:
   - **Bot-authored reviews**: auto-handle each item (Step 2a) without user input
   - **Human-authored reviews**: analyze, present options, and implement fixes interactively (Steps 2b–5)
4. Only dismiss the review (with `dismiss-comment.sh`) **after all items have been addressed**

**Note**: Like generic PR comments, review summaries cannot be "resolved" on GitHub. The `dismiss-comment.sh` command tracks them as addressed in local state.

## Handling Generic PR Comments

Generic PR comments (`[Comment: ...]`) may contain **multiple feedback items** within a single comment. For example, CodeRabbit summary comments often list several issues across different files.

When processing a generic PR comment with multiple items:

1. Read the entire comment and identify all distinct feedback items
2. Check whether any items duplicate feedback already handled via inline review threads — skip those
3. Work through each remaining actionable item:
   - **Bot-authored comments**: auto-handle each item (Step 2a) without user input
   - **Human-authored comments**: analyze, present options, and implement fixes interactively (Steps 2b–5)
4. Only dismiss the comment (with `dismiss-comment.sh`) **after all items have been addressed**

**Note**: Unlike review threads, generic PR comments cannot be "resolved" on GitHub. The `dismiss-comment.sh` command tracks them as addressed in local state. They will remain visible in the PR conversation on GitHub.

## Commands Reference

| Command                                      | Purpose                                            |
| -------------------------------------------- | -------------------------------------------------- |
| `but-feedback.sh [--limit N] [--all]`           | Retrieve GitButler workspace feedback              |
| `pr-feedback.sh [--limit N] [--all]`            | Retrieve standard PR feedback                      |
| `resolve-feedback.sh <thread-id>`               | Mark a review thread as resolved                   |
| `dismiss-comment.sh <comment-id>`               | Mark a generic PR comment as addressed (local)     |
| `dismiss-comment.sh <comment-id> --undismiss`   | Undo dismissal of a generic PR comment             |
| `snooze-feedback.sh <id> <duration>`             | Snooze any feedback item (e.g. 1h, 1d, 1w)        |
| `wait-for-review.sh [--workspace-type TYPE]`    | Wait for CodeRabbit review after pushing           |
| `coderabbit-status.sh [--json]`                 | Check CodeRabbit's current review status           |
| `gh issue create --title "..." --body "..."` | Create a follow-up GitHub issue                    |
| `pr-comment.sh <thread-id> <comment-text>`      | Reply to a specific PR review thread               |
| `pr-comment.sh <thread-id>`                     | Reply to a thread (prompts for comment in $EDITOR) |

All scripts should be prefixed with the full path: `~/.claude/skills/resolve-pr-feedback/`

### Git Operations by Workspace Type

| Operation             | GitButler Workspace            | Standard Git          |
| --------------------- | ------------------------------ | --------------------- |
| Check status/branches | `but status`                   | `git status`          |
| Stage file to branch  | `but rub <file> <branch>`      | `git add <file>`      |
| Commit to branch      | `but commit <branch> -m "..."` | `git commit -m "..."` |

**Important**: Always use the appropriate commands based on the detected workspace type. GitButler allows multiple virtual branches to be applied to the working tree simultaneously. Use `but status` to see all virtual branches and identify the one associated with the PR whose feedback is being resolved. Then use `but rub` to stage files and `but commit <branch>` to commit to that specific virtual branch. Using `git commit` directly in a GitButler workspace will bypass virtual branch management.
