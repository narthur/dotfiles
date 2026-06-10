---
name: resolve-feedback
description: "Retrieve, classify, and resolve PR review feedback — inline review threads, review summaries, and generic PR comments, from humans and bots. Fixes valid feedback (committing locally), posts justifications for invalid feedback, files follow-ups for out-of-scope items, and — critically — literally marks each item resolved/dismissed on GitHub (a reply is NOT a resolution). Supports an interactive mode (prompts on human feedback) and a non-interactive/batch mode (auto-applies bot/procedural feedback, defers human feedback to the caller). Use when the user wants to resolve PR feedback / review comments / review threads, address reviewer comments, or 'resolve feedback'. This is the feedback engine that the drive-pr and pr-triage skills delegate to; it does not push, run the review loop, fix CI, or integrate the base branch — that is the caller's job."
---

You retrieve PR review feedback, decide what each item warrants, act on it, and **leave every handled item resolved or dismissed on GitHub**. You are the focused feedback engine: `drive-pr` and `pr-triage` delegate the feedback dimension to you and own everything else (base integration, the local `review-loop`, push, CI). When a user simply says "resolve feedback" on a PR, you are the right tool on your own.

## THE CARDINAL RULE: a reply is not a resolution

Whenever you finish with a feedback item — whether you **fixed** it, **justified** why no change is needed, or **filed a follow-up** — you MUST literally mark it addressed on GitHub:

- **Review thread** → `~/.claude/skills/resolve-feedback/resolve-feedback.sh <thread-id>` (the `resolveReviewThread` GraphQL mutation). Replying with `pr-comment.sh` does **not** resolve it.
- **Review summary** → `~/.claude/skills/resolve-feedback/dismiss-comment.sh <review-id>`
- **Generic PR comment** → `~/.claude/skills/resolve-feedback/dismiss-comment.sh <comment-id>`

Posting a comment that says "fixed in <sha>" or "this is intentional" and then walking away is the single most common failure mode here. The thread stays open, the PR still shows unresolved feedback, and the reviewer has to clean up after you. **Every item you touch ends resolved/dismissed — no exceptions.** The only items you may leave open are human threads in non-interactive (batch) mode, which you hand back to the caller (see below).

The feedback-retrieval scripts are what give you the thread/review/comment IDs needed to do this. That is why you must run retrieval first and never hand-edit files before classifying.

## What this skill does NOT do

Stay in your lane. You do **not** push, run the `review-loop` skill, fix CI, integrate the base branch, or merge. You fix feedback and commit those fixes **locally**, then report. The caller (`drive-pr`, `pr-triage`, or the user) decides when to review-loop, push, and chase CI. When invoked standalone and you committed fixes, say so plainly in your report and recommend `/drive-pr` to review-loop + push + drive to mergeable — because resolving a thread is an immediate remote action while your fix commit is still local, so the user should publish promptly.

## Preconditions (establish before retrieving)

A caller (`drive-pr`/`pr-triage`) has usually done these already; when invoked standalone, do them yourself.

1. **Resolve the target PR.** If the user passed a PR number/URL/branch, switch to it first — otherwise the feedback scripts operate on whatever PR matches the current branch, which is rarely intended.
   ```bash
   gh pr view <number> --json number,headRefName,baseRefName,isCrossRepository
   ```
   - **Standard git**: `gh pr checkout <number>`.
   - **GitButler workspace** (current branch is `gitbutler/workspace`): do **not** `gh pr checkout` (it leaves the workspace). Find the matching virtual branch with `but status`; if none is applied, stop and ask rather than work on the wrong branch.
   Re-verify with `git branch --show-current` / `but status` before proceeding.
2. **Detect workspace type** (selects the retrieval script):
   ```bash
   git branch --show-current
   ```
   - `gitbutler/workspace` → use `but-feedback.sh` + GitButler commands.
   - otherwise → use `pr-feedback.sh` + standard git.

## Interactive vs non-interactive

**Bot/automated** feedback is handled automatically. **Human** feedback requires interactive confirmation before any action — *unless* you're in non-interactive (batch) mode.

### Known bot authors

`coderabbitai`, `dependabot`, `github-actions`, `copilot`, `codecov`, `sonarcloud`, `renovate`, and any author whose login ends in `[bot]`. Anyone else is **human** → interactive path (unless batch mode).

### Non-interactive (batch) mode

When a batch caller drives you — signaled by a `--non-interactive` / `--bot-only` argument, or the caller stating it wants bot-only resolution (e.g. `pr-triage` running autonomously) — **do not pause on human feedback**:

- Handle all **bot** feedback (Automated Path) and all **procedural noise** (auto-dismiss) exactly as normal.
- For **human** feedback, do NOT prompt and do NOT act. Leave the thread unresolved and collect it.
- When the queue is exhausted, **return** (don't block) a structured summary: bot/procedural items resolved (with commit SHAs), and the list of unresolved **human** threads — PR #, thread/comment ID, author, one-line summary each — so the caller can surface them later.

This is the only circumstance in which human feedback may be left without an interactive prompt.

---

# Workflow

**Always: establish preconditions → Step 1 (retrieve) → Step 2 (classify) → act. Never edit files for feedback before classifying.**

## Step 1: Retrieve Feedback (MANDATORY — never skip)

Run the script for the workspace type before doing anything else:

```bash
# GitButler workspace
~/.claude/skills/resolve-feedback/but-feedback.sh --limit 1

# Standard git
~/.claude/skills/resolve-feedback/pr-feedback.sh --limit 1
```

The output classifies each item and gives the ID you need to resolve/dismiss it:

- **Review threads** (`[Thread: ...]`) — inline comments on specific files/lines; have a **thread ID** (resolvable).
- **Review summaries** (`[Review: ...]`) — a review's top-level body (e.g. a CodeRabbit summary); have a **review ID** (dismissible). May bundle several items across files.
- **Generic PR comments** (`[Comment: ...]`) — top-level conversation comments; have a **comment ID** (dismissible). May bundle several items.

**If the queue is empty**, you're done with feedback — report and stop (a caller will continue its own loop). Standalone, an empty queue simply means there's nothing to resolve.

## Step 2: Classify

**First, is there any actionable feedback at all?** Some items are procedural noise — **auto-dismiss without prompting, regardless of author**, because there's nothing to act on:

- **Bot-trigger / command comments** — `@coderabbitai review`, `@coderabbitai resolve`, `@coderabbitai full review`, `/review`, or any comment that is wholly a directive to a review bot.
- **Automated acknowledgements & status notices** — CodeRabbit "Review finished" / "Action performed", "Review limit reached" / rate-limit notices, "currently reviewing", deploy/preview status pings, CI status echoes.
- **Pure chatter** — "thanks", "👍", "merging now", when they carry no question or request.

Dismiss these (`dismiss-comment.sh`, or `resolve-feedback.sh` for a thread) and return to Step 1. No reply, no options, no prompt.

**Guardrail:** this is only for items with plainly no actionable request. If a comment mixes a bot trigger with a real ask ("@coderabbitai review — also rename this?"), or you're unsure whether a human comment is substantive, treat it as feedback. When in doubt on a human comment, never auto-dismiss — go interactive.

Otherwise classify by author:

- **Bot** → Step 2a (Automated Path)
- **Human** → Step 2b (Interactive Path)

### Step 2a: Automated Path (bot feedback)

Handle without prompting:

1. Read the referenced code and understand the concern.
2. **Clearly valid & actionable** → fix, resolve/dismiss, commit (Option 1).
3. **Clearly invalid or already addressed** → resolve/dismiss without changes (Option 3); post a brief justification reply first if it's a review thread.
4. **Valid but out of scope** → file a follow-up issue (Option 4, incl. duplicate check), reply with the reference, then resolve/dismiss.
5. **Ambiguous or risky** (architectural, unclear intent, could break things) → fall through to the Interactive Path and ask.
6. Return to Step 1.

Don't present options or wait on input for unambiguous bot feedback — just handle it.

### Step 2b: Interactive Path (human feedback)

Skipped entirely in non-interactive (batch) mode — there, leave the human thread unresolved and collect it for the caller.

Otherwise, summarize the item for the user (file/line + plain-language ask), then go through Step 3 (validate) and Step 4 (present options). **Never skip the interactive flow for human feedback.**

## Step 3: Validate (interactive path only)

Read the referenced code, understand the concern, judge it **solely on technical merits**.

- **Clearly valid** → offer options.
- **Clearly invalid** → explain why and offer to resolve without changes.
- **Uncertain** → present your analysis and let the user decide.

## Step 4: Present Options (MANDATORY for human feedback)

**Present options and wait for the user's choice before any code change.** Don't assume Option 1; don't auto-select. (Skipped for bot feedback handled in Step 2a.)

**Immediately before the options, summarize the item** so the user can decide without scrolling: the file/line range, a 1–3 sentence plain-language description, and your quick take on validity ("race is real", "I think this is a nitpick because…", "ambiguous"). Include this even if you summarized earlier. The same summary applies when bot feedback falls through here (Step 2a item 5).

```
Next steps:
1. Fix, resolve/dismiss, and commit - Implement the fix, mark addressed, commit
2. Fix only - Implement the fix without resolving/dismissing or committing
3. Resolve/dismiss without fix - Mark addressed (feedback invalid or already addressed)
4. Create follow-up issue - File a GitHub issue to address later
5. Snooze - Temporarily hide this item and revisit later (e.g. 1h, 1d, 1w)
6. Skip - Move to the next item
7. Stop - End the feedback session
```

Adjust to context (e.g. surface "Create follow-up issue" when the fix is out of scope).

## Step 5: Execute

All script paths are under `~/.claude/skills/resolve-feedback/`.

**Option 1 — Fix, resolve/dismiss, and commit:**

1. Implement the code fix.
2. **Mark addressed** (the cardinal rule):
   - Review thread: `resolve-feedback.sh <thread-id>`
   - Review summary: `dismiss-comment.sh <review-id>`
   - Generic comment: `dismiss-comment.sh <comment-id>`
3. Stage and commit **locally** (conventional commits — see below):
   - **GitButler**: `but status` to find the PR's virtual branch → `but rub <file> <branch>` → `but commit <branch> -m "..."`
   - **Standard git**: `git add` + `git commit -m "..."`
4. **Do NOT push** — commits accumulate locally for the caller.
5. Return to Step 1.

**Option 3 — Resolve/dismiss without fix:**

1. Compose a brief justification (concern doesn't apply / already handled / behavior intentional).
2. Reply **and** mark addressed — both steps:
   - Review thread: `pr-comment.sh <thread-id> "<justification>"` **then** `resolve-feedback.sh <thread-id>`
   - Review summary: `dismiss-comment.sh <review-id>`
   - Generic comment: `dismiss-comment.sh <comment-id>`
3. Return to Step 1.

**Option 4 — Create follow-up issue:**

1. Check for an existing issue first: `gh issue list --search "<keywords>" --state open`. Reuse a match; otherwise `gh issue create --title "..." --body "..."`.
2. Reply with the reference: review thread → `pr-comment.sh <thread-id> "Tracked in follow-up issue #<n>"`; generic comment → `gh pr comment --body "Tracked in follow-up issue #<n>"`.
3. Mark addressed: review thread → `resolve-feedback.sh <thread-id>`; generic comment → `dismiss-comment.sh <comment-id>`.
4. Return to Step 1.

**Option 5 — Snooze:**

1. Ask how long (e.g. 1h, 4h, 1d, 3d, 1w), or accept an inline duration.
2. `snooze-feedback.sh <id> <duration>` (works for thread and comment IDs).
3. Hidden from retrieval until the snooze expires; review threads also auto-unsnooze on a new comment from someone else.
4. Return to Step 1.

## Step 6: Continue

After each action, return to Step 1 for the next item until the queue is empty (or the user stops). When empty, report (Completion).

## Handling review summaries and generic comments (multi-item)

`[Review: ...]` and `[Comment: ...]` items often bundle **several feedback points** across files (e.g. a CodeRabbit summary). For each:

1. Read the whole body; enumerate every distinct point.
2. Skip points already handled via inline threads.
3. Work each remaining actionable point: bot-authored → auto-handle (Step 2a); human-authored → interactive (Steps 2b–5).
4. Only dismiss the review/comment (`dismiss-comment.sh`) **after all its points are addressed**.

**Note:** unlike review threads, review summaries and generic comments cannot be "resolved" on GitHub. `dismiss-comment.sh` tracks them as addressed in local state; they remain visible in the conversation.

## Completion

When the queue is empty (or the user stops):

- **Standalone / interactive:** report the items resolved (with commit SHAs for fixes), any follow-up issues filed, anything snoozed/skipped. If you committed fixes, state that they are **local and unpushed**, and recommend `/drive-pr` to run the review loop, push, and drive to mergeable. Remind that resolved threads are already live on the remote, so publishing the fixes promptly keeps the PR coherent.
- **Non-interactive (batch):** return the structured summary — bot/procedural items resolved (with SHAs) and the list of unresolved **human** threads (PR #, ID, author, one-line summary) — and do not push or block.

## Conventional Commit Format

```
<type>(<scope>): <description>
```

Types: `fix` (most PR feedback), `feat`, `refactor`, `docs`, `test`, `chore`. Scope = area changed (module/feature). Examples: `fix(auth): validate token expiry before API calls`, `refactor(api): extract common error handling`.

## Commands Reference

All under `~/.claude/skills/resolve-feedback/`.

| Command | Purpose |
| --- | --- |
| `pr-feedback.sh [--limit N] [--all]` | Retrieve standard PR feedback |
| `but-feedback.sh [--limit N] [--all]` | Retrieve GitButler workspace feedback |
| `resolve-feedback.sh <thread-id>` | Mark a review thread resolved (`resolveReviewThread`) |
| `resolve-feedback.sh <thread-id> --unresolve` | Re-open a resolved thread |
| `dismiss-comment.sh <comment-id>` | Mark a review summary / generic comment addressed (local) |
| `dismiss-comment.sh <comment-id> --undismiss` | Undo a dismissal |
| `pr-comment.sh <thread-id> "<text>"` | Reply to a review thread (does NOT resolve it) |
| `pr-comment.sh <thread-id>` | Reply, prompting for the body in `$EDITOR` |
| `snooze-feedback.sh <id> <duration>` | Snooze any item (e.g. 1h, 1d, 1w) |
| `gh issue list --search "<kw>" --state open` | Find an existing follow-up before creating one |
| `gh issue create --title "..." --body "..."` | File a follow-up issue |

Waiting for CodeRabbit's review is **not** this skill's job — that's `../drive-pr/wait-for-review.sh` (orchestration) and the `coderabbit-status` skill (read-only status). CodeRabbit feedback, once posted, is resolved here like any other bot's.

### Git operations by workspace type

| Operation | GitButler workspace | Standard git |
| --- | --- | --- |
| Status/branches | `but status` | `git status` |
| Stage file to branch | `but rub <file> <branch>` | `git add <file>` |
| Commit to branch | `but commit <branch> -m "..."` | `git commit -m "..."` |

In a GitButler workspace, multiple virtual branches can be applied at once — use `but status` to identify the one tied to the PR, then `but rub` / `but commit <branch>`. A bare `git commit` bypasses virtual-branch management.
