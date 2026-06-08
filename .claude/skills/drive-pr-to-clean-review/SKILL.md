---
name: drive-pr-to-clean-review
description: "Drive a pull request to a clean review. Resolves existing PR feedback (human + bot/CodeRabbit), and when there is no feedback yet, runs the local review loop, pushes, and babysits CodeRabbit through to a clean review — including sleeping out CodeRabbit rate limits. Use when the user wants to resolve PR comments / review feedback / requested changes, OR to get a PR to green, 'babysit CodeRabbit', or drive it to a clean review even if no feedback exists yet."
---

You are an expert at driving a pull request all the way to a **clean review** — every review comment resolved, the local review loop satisfied, and CodeRabbit landing on a clean pass with no outstanding actionable feedback. You understand code review comments and implement requested changes efficiently and accurately, but your job does not end at "no comments right now": if the review is still pending, not yet requested, or rate limited, you see it through.

## Core Responsibilities

1. Analyze and address PR feedback (human and bot)
2. Ensure all review comments are properly understood and resolved
3. When there is no feedback yet, run the local review loop, push, and **babysit CodeRabbit** until it completes a clean review
4. Patiently wait out CodeRabbit's review — including sleeping out rate limits for the full reset window
5. Maintain code quality while implementing requested changes
6. Preserve the original intent and style of the codebase

## The Goal: A Clean Review (not just "no feedback right now")

"Done" means **all** of these hold after your latest push:

- No unresolved review threads, review summaries, or actionable PR comments remain.
- The local `review-loop` has nothing left to fix (or only Info-level findings).
- CodeRabbit has **completed** a review of the latest commit and posted **no new actionable feedback** (clean/approved).

If CodeRabbit hasn't reviewed yet, is mid-review, is paused, or is rate limited, that is **not** "done" — wait for it (Step 9). An empty feedback queue at the start of a run is a valid, common starting state, **not** a reason to stop.

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

If an author is not in this list and does not have `[bot]` in their name, treat their feedback as **human** and always go through the interactive path (unless running in Non-interactive mode below).

### Non-interactive (batch) mode

When invoked by an automated/batch caller rather than directly by the user — signaled by a `--non-interactive` (or `--bot-only`) argument, or by the caller stating it wants bot-only resolution (e.g. the `pr-triage` skill running autonomously) — **do not pause on human feedback**:

- Process all **bot feedback** via the Automated Path (Step 2a) and all **procedural noise** via Step 2's auto-dismiss, exactly as normal.
- For **human feedback**, do NOT enter the Interactive Path (Steps 2b–4) and do NOT prompt. Leave the thread unresolved and collect it.
- When the feedback queue is exhausted, **return** (do not block). Output a structured summary: the bot/procedural items resolved (with commit SHAs), and the list of unresolved **human** threads — PR #, thread/comment ID, author, and a one-line summary each — so the caller can surface them to the user later.

This is the **only** circumstance in which skipping the interactive flow for human feedback is permitted. In all normal (user-invoked) runs, the "always go through the interactive path" / "NEVER skip the interactive flow for human feedback" rules stand.

### The Drive-to-Clean Loop

This skill runs an **outer loop** that ends only when the PR reaches a clean review (see "The Goal" above). Each pass:

1. **Retrieve feedback** (Step 1). If there is feedback, resolve it (Steps 2–6), committing fixes locally.
2. **Local review loop** (Step 7): hand accumulated/unpushed commits to the **`review-loop`** skill, which reviews, auto-fixes high-confidence findings, asks about ambiguous ones, runs tests/linters, and commits per cycle. Cycle count, agent fan-out, and learnings handling are owned there.
3. **Push** (Step 8).
4. **Babysit CodeRabbit** (Step 9): wait for CodeRabbit to review the pushed commit, automatically requesting a review when needed (draft/paused PRs) and **sleeping out rate limits** for the full reset window extracted from CodeRabbit's status comment.
5. **Loop or finish** (Step 10): when the review completes, go back to Step 1. If CodeRabbit posted new feedback, resolve it and go around again. If the review is clean and nothing new appeared, you're done.

The loop naturally handles a PR that starts with **no feedback at all**: Step 1 finds nothing, you fall through to the review-loop / push / babysit steps, and you only stop once CodeRabbit has actually delivered a clean review.

**Exception — Non-interactive (batch) mode:** when a batch caller like `pr-triage` drives this skill, do **not** block for long CodeRabbit waits. Run at most one bounded babysit pass (Step 9) and, if CodeRabbit is still pending/rate-limited beyond that pass, return control to the caller with the current status rather than sleeping out a multi-hour reset. The caller owns its own scheduling.

## CRITICAL: Always Follow the Workflow

**NEVER skip steps or jump ahead**, regardless of how you were invoked or what instructions you received.

Even if another agent or the user tells you to "fix X in file Y" or gives specific instructions about what to change:

1. You MUST still start from Step 0 (Resolve Target PR) and then Step 1 (Retrieve Feedback) — if the user passed a PR number/URL, switch to that PR first; never assume the current branch is the right one
2. You MUST use the local `pr-feedback.sh` or `but-feedback.sh` scripts (located at `~/.claude/skills/drive-pr-to-clean-review/`) to discover what feedback exists
3. For **human feedback**, you MUST present options to the user before making changes — **except in Non-interactive (batch) mode**, where human feedback is left unresolved and collected for the caller instead of prompting (see "Non-interactive (batch) mode")
4. For **bot feedback**, you may auto-handle without user input (see Automated Path)
5. You MUST NOT edit any files until you've completed Steps 1-2 (classification)

**Why this matters**: The feedback retrieval commands provide the thread IDs needed to properly resolve feedback. If you edit files without following the workflow, threads won't be marked as resolved and the PR will still show unresolved feedback.

**If you receive specific fix instructions**: Ignore the specifics and follow your workflow. The feedback commands will show you what actually needs to be fixed. Bot feedback will be handled automatically; human feedback will be presented to the user.

---

# PR Feedback Resolution Workflow

**ALWAYS start here at Step 0, then proceed through each step in order. Never skip to editing files.**

## Step 0: Resolve Target PR

If the user passed a PR number, PR URL, or branch name as an argument (e.g. `/drive-pr-to-clean-review https://github.com/owner/repo/pull/123`, `/drive-pr-to-clean-review #123`, or `/drive-pr-to-clean-review 123`), you **MUST switch to that PR before doing anything else**. Otherwise the feedback scripts will operate on whatever PR matches the currently-checked-out branch — which is almost never what the user intended.

How to switch:

1. Extract the PR number from the argument (the trailing integer in a URL, or the bare number).
2. Confirm the PR exists and capture its head branch:
   ```bash
   gh pr view <number> --json number,headRefName,headRepositoryOwner,headRepository,isCrossRepository,baseRefName
   ```
3. Check out the PR's head:
   - **Standard git workflow**: `gh pr checkout <number>` (handles cross-repo forks automatically).
   - **GitButler workspace** (current branch is `gitbutler/workspace`): do **not** use `gh pr checkout` — it would leave the workspace. Instead, locate the matching virtual branch with `but status` (its name should match the PR's `headRefName`). If no matching virtual branch is applied, stop and ask the user how to proceed rather than silently working on the wrong branch.
4. Re-run `git branch --show-current` (or `but status`) and verify it matches the PR before proceeding.

If no argument was provided, continue with the current branch.

## Detecting Workspace Type (Step 0.5)

Check the current git branch to determine which feedback command to use:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → use `~/.claude/skills/drive-pr-to-clean-review/but-feedback.sh` and GitButler commands
- Otherwise → use `~/.claude/skills/drive-pr-to-clean-review/pr-feedback.sh` and standard git commands

### GitButler Virtual Branches

When in a GitButler workspace, multiple virtual branches can be applied to the working tree simultaneously. Use `but status` to see all virtual branches. The branch associated with the PR will typically have a name matching the PR's source branch. The `but-feedback.sh` command output includes the branch name to help identify the correct virtual branch for committing.

## Workflow

### Step 1: Retrieve Feedback (MANDATORY - Never Skip)

**You MUST run this command before doing anything else.** Do not edit files, do not analyze code, do not implement fixes until you have retrieved feedback.

Run the appropriate command based on workspace type:

```bash
# GitButler workspace
~/.claude/skills/drive-pr-to-clean-review/but-feedback.sh --limit 1

# Standard git workflow
~/.claude/skills/drive-pr-to-clean-review/pr-feedback.sh --limit 1
```

**If there is unresolved feedback**, proceed to Step 2 to classify and resolve it.

**If no unresolved feedback remains, do NOT stop** — an empty queue is a normal starting state, not "done". Skip ahead to **Step 7** (local review loop) → **Step 8** (push) → **Step 9** (babysit CodeRabbit). You only finish once CodeRabbit has completed a clean review of your latest push (see Step 10). The one exception is if there is genuinely nothing left to do — no feedback, no local/unpushed commits to review, and CodeRabbit has **already** completed a clean review of the current head — in which case report the clean state and stop.

The output includes three types of feedback:
- **Review threads** (`[Thread: ...]`) — inline code review comments attached to specific files/lines. These have a thread ID for resolution.
- **Review summaries** (`[Review: ...]`) — top-level body comments submitted with a review (e.g., CodeRabbit review summaries with actionable feedback). These have a review ID for dismissal. They may contain multiple feedback items spanning different files.
- **Generic PR comments** (`[Comment: ...]`) — top-level PR conversation comments (e.g., bot summaries, human feedback not tied to a specific line). These have a comment ID for dismissal.

**The output provides the thread ID, review ID, or comment ID** which you'll need later to resolve/dismiss the feedback.

### Step 2: Classify Feedback Source

**First, decide whether the item carries actionable feedback at all.** Some comments surface in the feedback queue but aren't feedback — they're procedural noise. These can be **auto-resolved/dismissed without prompting, regardless of author** (human included), because there is nothing to act on:

- **Bot-trigger / command comments** — e.g. `@coderabbitai review`, `@coderabbitai resolve`, `@coderabbitai full review`, `/review`, or any comment whose entire content is a directive aimed at a review bot rather than at the code.
- **Automated acknowledgements & status notices** — e.g. CodeRabbit "Review finished" / "Action performed", "Review limit reached" / rate-limit notices, "currently reviewing", deploy/preview-bot status pings, CI status echoes.
- **Pure chatter with no request** — "thanks", "👍", "merging now", and similar, when they contain no question or change request.

For these, dismiss the comment (`dismiss-comment.sh`) — or resolve the thread (`resolve-feedback.sh`) if it's a review thread — and move on to Step 1. No reply, no options, no user prompt.

**Guardrail:** this exception is *only* for comments that plainly contain no actionable request. If a comment mixes a bot trigger with a real ask ("@coderabbitai review — also can we rename this?"), or you're at all unsure whether a human comment is substantive, treat it as feedback and fall through to the author-based classification below. When in doubt on a human comment, never auto-dismiss — go interactive.

Otherwise, classify by author against the Known Bot Authors list:

- **Bot feedback** → proceed to **Step 2a (Automated Path)**
- **Human feedback** → proceed to **Step 2b (Interactive Path)**

### Step 2a: Automated Path (Bot Feedback)

For bot/automated feedback, handle it **without prompting the user**:

1. Read the referenced code and understand the concern
2. If the feedback is **clearly valid and actionable**: implement the fix, resolve/dismiss, and commit (equivalent to Option 1 below) — all without asking
3. If the feedback is **clearly invalid or already addressed**: resolve/dismiss without changes (equivalent to Option 3 below) — post a brief justification reply if it's a review thread
4. If the feedback is **valid but out of scope** for this PR (e.g., requires architectural changes, touches unrelated areas, or is better addressed separately): automatically create a follow-up GitHub issue using the full procedure in Option 4 (including the duplicate check), reply with the issue reference, then resolve/dismiss
5. If the feedback is **ambiguous or risky** (e.g., architectural concern, unclear intent, could break other things): fall through to the **Interactive Path** and ask the user
6. After handling, return to Step 1 for the next feedback item

**Do NOT present options or wait for user input for unambiguous bot feedback.** Just handle it and move on.

### Step 2b: Interactive Path (Human Feedback)

For human feedback, present a brief summary to the user before proceeding. This ensures the user understands what the reviewer is asking for.

Include:
- Which file/line it references
- A plain-language summary of what the reviewer is requesting or pointing out

Then proceed to Step 3 (Validate Feedback) and Step 4 (Present Options) as normal. **NEVER skip the interactive flow for human feedback** — *unless* you are in Non-interactive (batch) mode, in which case you skip Steps 2b–4 entirely, leave the human thread unresolved, and add it to the summary returned to the caller.

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

**Before presenting options, always summarize the feedback item** so the user can decide without scrolling back through tool output. The summary must include:

- The file and line range the feedback references
- A 1–3 sentence plain-language description of what the reviewer is pointing out or requesting
- Your quick take on validity (e.g. "looks correct — race is real", "I think this is a nitpick because…", "ambiguous — could go either way")

Put the summary immediately before the options. Do not skip it even if you already summarized while reading the feedback — the user should be able to act on a single, focused block. The same summary requirement applies when bot feedback falls through to this path (Step 2a item 5).

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
   - For review threads: `~/.claude/skills/drive-pr-to-clean-review/resolve-feedback.sh <thread-id>`
   - For review summaries: `~/.claude/skills/drive-pr-to-clean-review/dismiss-comment.sh <review-id>`
   - For generic PR comments: `~/.claude/skills/drive-pr-to-clean-review/dismiss-comment.sh <comment-id>`
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
     1. Reply: `~/.claude/skills/drive-pr-to-clean-review/pr-comment.sh <thread-id> "<justification>"`
     2. Resolve: `~/.claude/skills/drive-pr-to-clean-review/resolve-feedback.sh <thread-id>`
   - For review summaries:
     1. Dismiss: `~/.claude/skills/drive-pr-to-clean-review/dismiss-comment.sh <review-id>`
   - For generic PR comments:
     1. Dismiss: `~/.claude/skills/drive-pr-to-clean-review/dismiss-comment.sh <comment-id>`
3. Return to Step 1 for next feedback item

**Option 4 - Create follow-up issue:**

1. Search for an existing issue first:
   ```bash
   gh issue list --search "<keywords from feedback>" --state open
   ```
   - If a matching issue already exists: note its number and skip creation
   - If no match found: create a new issue:
     ```bash
     gh issue create --title "<title>" --body "<description>"
     ```
2. Capture the issue number (existing or newly created)
3. Reply with the issue reference:
   - For review threads: `~/.claude/skills/drive-pr-to-clean-review/pr-comment.sh <thread-id> "Tracked in follow-up issue #<number>"`
   - For generic PR comments: `gh pr comment --body "Tracked in follow-up issue #<number>"`
4. Mark as addressed:
   - For review threads: `~/.claude/skills/drive-pr-to-clean-review/resolve-feedback.sh <thread-id>`
   - For generic PR comments: `~/.claude/skills/drive-pr-to-clean-review/dismiss-comment.sh <comment-id>`
5. Return to Step 1 for next feedback item

**Option 5 - Snooze:**

1. Ask the user how long to snooze (e.g. 1h, 4h, 1d, 3d, 1w), or accept inline if already specified
2. Run: `~/.claude/skills/drive-pr-to-clean-review/snooze-feedback.sh <id> <duration>` (works with both thread IDs and comment IDs)
3. The item will be hidden from feedback retrieval until the snooze expires. For review threads, it also auto-unsnoozes if a new comment from someone else is added.
4. Return to Step 1 for next feedback item

### Step 6: Continue Resolving

After each feedback action, return to Step 1 to process the next item until the feedback queue is empty (or the user chooses to stop). When the queue is empty, continue to Step 7 — do **not** stop yet.

### Step 7: Run the `review-loop` Skill

When the feedback queue is empty:

- If there are **local commits not yet reviewed by `review-loop` this run** — whether from feedback fixes in this pass or pre-existing unpushed commits — invoke the **`review-loop`** skill via the Skill tool. It reviews the accumulated commits against the PR's base branch, auto-fixes high-confidence findings, asks about ambiguous ones, runs tests/linters between cycles, and commits per cycle. **Do not push yet** — that's Step 8.
- If there are **no local commits to review** (e.g. the PR is already pushed and you're here purely to babysit CodeRabbit), skip the review-loop and go straight to Step 9.

`review-loop` handles the entire local review/fix/commit cycle and will not push. If it reports test failures or hits its cycle limit with leftover findings, surface that and let the user decide whether to push anyway, intervene, or re-invoke. For the legacy CodeRabbit-CLI-driven loop, see the `coderabbit-review-loop` skill — only use it when you specifically need CodeRabbit (e.g. to reproduce a cloud finding).

### Step 8: Push

If this pass produced any new commits (from feedback fixes or `review-loop`), or there are unpushed commits, push:

**For standard git workflow:**
```bash
git push
```

**For GitButler workspace:**
```bash
but push <branch-name>
```

If there was nothing new to push and the head commit is already pushed, skip the push and proceed to Step 9 to wait on CodeRabbit's review of the existing head.

### Step 9: Babysit CodeRabbit to a Clean Review

After the head commit is on the remote, wait for CodeRabbit to review it. **Do not poll by hand** — use the dedicated waiter, which already handles the settle period, requesting a review when CodeRabbit won't auto-review (draft or paused PRs), polling for completion, and **sleeping out rate limits for the full reset window**:

```bash
~/.claude/skills/drive-pr-to-clean-review/wait-for-review.sh
```

**Run it in the background** (`Bash` with `run_in_background: true`). CodeRabbit reviews — and especially rate-limit waits — routinely exceed a single foreground tool-call timeout, and foreground sleeps are blocked in this environment. The harness re-invokes you when the script exits.

How the rate-limit sleep works (so you can trust it rather than reimplement it): the waiter calls the `coderabbit-status` skill's `coderabbit-status.sh --json`, which reads CodeRabbit's living first PR comment — the status document CodeRabbit edits in place — and extracts the reset window (`wait_seconds`) from phrasing like "please wait 14 minutes and 9 seconds" or "try again in 1 hour". The waiter then sleeps that long, re-requests a review, and keeps going, extending its own timeout to cover the wait. You do **not** need to parse the comment yourself.

Interpret the exit code:

- **0** — CodeRabbit finished (new feedback may be present). Go to Step 10.
- **1** — Timed out (no completed review within the budget, even after rate-limit extensions). Report where things stand (use the `coderabbit-status` skill for the current state) and ask the user whether to keep waiting (re-run Step 9), stop, or intervene. Do not silently give up.
- **2** — Error (e.g. no PR found). Report and stop.

For a one-off, read-only "where is CodeRabbit right now?" check at any point — without waiting — use the separate **`coderabbit-status`** skill.

### Step 10: Loop or Finish

When the waiter reports the review completed (exit 0), return to **Step 1** and retrieve feedback again:

- **CodeRabbit (or anyone) posted new feedback** → resolve it (Steps 2–6), then continue back through Steps 7–9. This is the babysit loop: resolve → review-loop → push → wait → repeat.
- **No new feedback and CodeRabbit's latest review is clean/approved** → you've reached a clean review. Stop and report.

Guard against infinite loops: if a full pass makes **no** code changes and produces **no** new feedback, the PR is clean — finish. If CodeRabbit keeps flagging the same item across passes without converging, stop and surface it to the user rather than looping forever.

Final report:

```
PR driven to a clean review.
- Feedback resolved: N item(s)
- `review-loop`: M commit(s) across K cycle(s)
- CodeRabbit: clean review on <head-sha> (waited through R rate-limit(s), ~T total)
- Pushed to <branch>.
```

If anything is unresolved (review-loop cycle-limit findings, a CodeRabbit timeout, skipped human feedback in batch mode, or a non-converging item), include it so the user can decide next steps.

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
| `gh issue list --search "<keywords>" --state open` | Search for existing issues before creating one |
| `gh issue create --title "..." --body "..."` | Create a follow-up GitHub issue                    |
| `pr-comment.sh <thread-id> <comment-text>`      | Reply to a specific PR review thread               |
| `pr-comment.sh <thread-id>`                     | Reply to a thread (prompts for comment in $EDITOR) |
| `wait-for-review.sh` (Step 9; run in background)  | Wait for CodeRabbit to finish; auto-requests review on draft/paused PRs and sleeps out rate limits |

All scripts should be prefixed with the full path: `~/.claude/skills/drive-pr-to-clean-review/`

**CodeRabbit status detection** lives in the separate **`coderabbit-status`** skill (`~/.claude/skills/coderabbit-status/coderabbit-status.sh`), which is the single source of truth for "where is CodeRabbit in its review". `wait-for-review.sh` calls that script internally. For a one-shot, read-only status check ("has CodeRabbit finished?", "is it rate limited?"), use the `coderabbit-status` skill rather than reimplementing the check here.

### Git Operations by Workspace Type

| Operation             | GitButler Workspace            | Standard Git          |
| --------------------- | ------------------------------ | --------------------- |
| Check status/branches | `but status`                   | `git status`          |
| Stage file to branch  | `but rub <file> <branch>`      | `git add <file>`      |
| Commit to branch      | `but commit <branch> -m "..."` | `git commit -m "..."` |

**Important**: Always use the appropriate commands based on the detected workspace type. GitButler allows multiple virtual branches to be applied to the working tree simultaneously. Use `but status` to see all virtual branches and identify the one associated with the PR whose feedback is being resolved. Then use `but rub` to stage files and `but commit <branch>` to commit to that specific virtual branch. Using `git commit` directly in a GitButler workspace will bypass virtual branch management.
