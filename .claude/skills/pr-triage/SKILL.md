---
name: pr-triage
description: "Go through open pull requests, check their status, and take actions to move them forward. This includes triaging PRs, fixing CI, resolving feedback, merging, or managing PR workflow. Use when asked to triage PRs, go through open PRs, or manage PR workflow. Runs autonomously by default on the user's own PRs — rebasing, resolving conflicts, fixing CI, and applying bot feedback without input — and only returns to the user once it has exhausted all autonomous work."
---

You are helping the user triage their open pull requests. Your role is to assess PR status, identify blockers, and take actions to move PRs forward toward merging. **By default you operate autonomously** (see "Autonomous Operation" below): work every eligible PR as far as you can on your own, and only return to the user once nothing autonomous remains.

## What You Do

- Work through the user's open PRs systematically and autonomously
- Assess each PR's status (CI, reviews, conflicts, feedback)
- Identify what's blocking each PR
- Execute unblocking actions yourself (integrate base/resolve conflicts, fix CI, apply bot feedback, request reviews)
- Batch the decisions that are the user's to make (merge, mark-ready) and anything you can't handle into a single request at the end

## What You Don't Do

- You don't perform code reviews yourself (the user has other tooling for that)
- You don't apply **human** review feedback without confirmation, or make code-quality judgment calls on it
- You never merge a PR or flip a draft to ready on your own — those are always the user's call (the **one exception** is low-risk Dependabot bumps; see "Dependabot PRs")
- You don't act on PRs that aren't the user's to drive (someone else's, or assigned away)

## Autonomous Operation (default)

Unless the user explicitly asks for interactive/step-by-step triage, run **autonomously**: work every eligible PR as far as you can without input, and only return to the user once you have exhausted all autonomous work across **all** eligible PRs. Reaching a mergeable or ready state on one PR is **not** a reason to stop — keep working the others first.

### Eligible PRs

A PR is **eligible** for autonomous handling when it is the user's to drive:

- authored by the user **and** not assigned to someone else (no assignees, or the user is among them), **or**
- assigned to the user (regardless of author), **or**
- authored by **Dependabot** (`app/dependabot`) — see "Dependabot PRs" below for the special auto-merge handling these get.

Compute the current user and the eligible set at the start of the run:

```bash
me=$(gh api user -q .login)
gh pr list --state open --json number,title,author,assignees,isDraft | \
  jq --arg me "$me" '[ .[]
    | select(
        ((.author.login == $me) and ((.assignees | length) == 0 or any(.assignees[]; .login == $me)))
        or any(.assignees[]; .login == $me)
        or (.author.login == "app/dependabot")
      )
    | {number, title, isDraft} ]'
```

PRs that are **not** eligible (someone else's, or assigned away) are out of scope for autonomous changes. Don't rebase/fix/push them; just note them in the final report (and, for others' code, you may still offer a CodeRabbit review via the normal menu).

### Autonomous actions — do these without asking

For each eligible PR, take every applicable action, committing and pushing as you go. Drive PR selection through the session (`next`) but apply the eligibility filter above before acting.

- **Integrate base / resolve conflicts** — rebase or merge `origin/<base>` and resolve conflicts yourself, keeping both sides' intent. Prefer a **merge** over a rebase when the branch's history already uses merges or has internal churn that would make a rebase replay the same conflicts repeatedly. Verify with the affected package's tests/typecheck before pushing. See "Option 3 - Fix conflicts".
- **Fix failing CI** — fix real failures in the worktree; re-run only genuinely-transient checks. See "Option 1 - Fix failing CI".
- **Apply bot feedback** — run `/resolve-pr-feedback <pr#> --non-interactive` (its Non-interactive/batch mode). It applies all **bot** and procedural feedback automatically and, critically, **does NOT pause on human feedback** — it returns the list of unresolved human threads instead. Take that list, add each human thread to the deferred items for the final request, and keep going. **Never let feedback resolution block autonomous work**: resolve what's auto-resolvable, defer the rest, and move on to the next action on this or another eligible PR.
- **Request a CodeRabbit review** when `cr-needs-review <n>` reports unreviewed commits, so feedback is waiting by the time you finish a pass.

After any push, CI re-runs. Don't block on it — move to the next eligible PR and revisit (re-`view`) once CI settles.

### Gated actions — NEVER do automatically

- **Merge** (`gh pr merge`) — never merge on your own. **Exception:** green, mergeable, `minor-patch` Dependabot PRs are auto-merged (see "Dependabot PRs"); every other PR's merge is gated.
- **Mark a draft ready** (`gh pr ready`) — do all prep on eligible drafts, but never flip draft→ready on your own.

Both are batched into the single final request below.

### Dependabot PRs (auto-merge exception)

Dependabot PRs (`app/dependabot`) are the **one exception** to "never merge automatically". They are dependency bumps, not the user's own code, and the user has opted into hands-off handling for the low-risk ones. Handle them like this:

1. **Classify the bump** with the helper:

   ```bash
   ~/.claude/skills/pr-triage/dependabot-bump-type <number>
   # stdout: minor-patch | major | unknown
   # exit 0 = minor-patch, 1 = major, 2 = unknown
   ```

2. **Overlap guard — check for a competing human PR before auto-merging.** If an open non-Dependabot PR edits the same `package.json` this bump touches, auto-merging will pile conflict churn onto that human PR (it has to re-resolve the lockfile/version lines every time a bump lands). Run:

   ```bash
   ~/.claude/skills/pr-triage/dependabot-overlap <number>
   # exit 0 = overlap found → DO NOT auto-merge; defer to user
   # exit 1 = no overlap   → safe to auto-merge (still subject to the checks below)
   # exit 2 = error
   ```

   On exit 0, treat the bump as deferred: note it in the final request as "subsumed by / overlaps #<n> — held to avoid conflict churn" and move on. Do **not** auto-merge it even if it is green + `minor-patch`. (An action-only bump like `actions/checkout` touches no manifest and always reports no overlap.)

3. **Decide by state** (only when the overlap guard reports clear):

   - **Green + mergeable + `minor-patch`** → **auto-merge it** (the exception). Use the repo's default merge method, defaulting to squash: `gh pr merge <number> --squash` (or `--merge`/`--rebase` to match repo settings). Log it and move on. Do **not** add it to the final batched request — it's done.
   - **Green + mergeable + `major` or `unknown`** → do **not** merge. Defer to the final batched request under "Ready to merge" with the bump type noted (e.g. "major: 4.x → 5.x — your call"). Major bumps and unclassifiable titles (group updates, odd version strings) always need the user's judgment.
   - **CI failing** → do **not** try to fix a dependency bump in-tree. A genuinely failing bump usually means the new version breaks something, which is a decision for the user — defer it to the final request with the failing check named. Only re-run a check that is plainly transient (timeout, network, runner error); never hand-edit the dependency to make CI pass.

4. **Conflicts / behind base** → **never** manually rebase or force-push a Dependabot branch (it desyncs Dependabot and it'll just recreate the PR). Instead comment `@dependabot rebase` and move on; revisit the PR on a later pass once Dependabot has updated it:

   ```bash
   gh pr comment <number> --body "@dependabot rebase"
   ```

5. **Bot feedback** on Dependabot PRs (e.g. CodeRabbit) is informational — don't block on it. Apply trivially-safe auto-fixes if `/resolve-pr-feedback --non-interactive` handles them, otherwise leave it; the merge decision is driven by CI + bump type, not by review threads.

Everything Dependabot-related still goes in the activity log: classification result, each `@dependabot rebase` comment, each auto-merge (with SHA), and each deferral with its reason.

### Exhaustion loop

Cycle through the eligible set until a **full pass makes no new autonomous change** on any PR **and no eligible PR has CI still running**. Treat a PR as settled for the pass when it is either:

1. green + mergeable (awaiting your merge decision), or a fully-prepped draft (awaiting your mark-ready decision); or
2. blocked on something only the user can resolve (recorded for the final request).

Re-evaluate the whole set each pass — fixing or landing one PR can unblock or reorder another (e.g. two PRs touching the same lines, where the second needs a rebase after the first lands).

### Final request — only after exhaustion

Return to the user **once**, with a single consolidated report covering every eligible PR:

- **Ready to merge** — ask which to merge (and in what order, if interdependent). Honor the strict gate in "Option 6".
- **Prepped drafts** — ask which to mark ready.
- **Needs your input** — for each, state precisely what's blocking and what you'd need: unresolved **human** feedback, CI you couldn't fix (e.g. repo-wide dependency-audit CVEs, flaky infra, or a failure needing a product decision), conflicts requiring a judgment call, or ambiguous bot feedback you declined to auto-apply.

Prefer a single `AskUserQuestion` (or one compact numbered list) so the user can resolve everything in one turn.

### Activity log

Keep a durable, reviewable trail of everything autonomous mode does. Log to a per-repo file:

```
${XDG_CACHE_HOME:-$HOME/.cache}/pr-triage-worktrees/<owner>-<repo>/triage-activity.log
```

Append one timestamped line per meaningful action — don't overwrite. At the start of a run write a header, then log each action as you take it (not in a batch at the end, so the trail survives an interruption):

```bash
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/pr-triage-worktrees/$(gh repo view --json nameWithOwner -q .nameWithOwner | tr / -)/triage-activity.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

log "=== autonomous run start: $(gh repo view --json nameWithOwner -q .nameWithOwner) ==="
log "PR #780: rebased onto origin/main, resolved 2 conflicts in shared.ts, pushed (abc1234)"
log "PR #780: applied CodeRabbit feedback (assert issues field), tests 14/14, pushed (def5678)"
log "PR #601: web-audit failing on repo-wide vitest CVE — deferred to user"
log "=== run end: 3 ready to merge, 1 needs input ==="
```

Log at minimum: run start/end, each conflict resolution / CI fix / feedback application (with the pushed commit SHA), each gated item deferred, and each thing deferred to the user with the reason. Tell the user where the log lives in your final report.

## CRITICAL: Workflow Constraints

**Always use the `pr-review-session` helper script** for managing PR triage sessions. The script is located at `~/.claude/skills/pr-triage/pr-review-session`. It tracks which PRs have been reviewed, maintains session state, and provides structured workflow - do NOT use raw `gh` commands when a session command exists for the same purpose.

| Instead of... | Use... |
|---------------|--------|
| `gh pr list` | `pr-review-session list` |
| `gh pr view <N>` | `pr-review-session view <N>` |
| Manually tracking which PRs you've seen | `pr-review-session next` |

The session commands track state across the triage session. Using `gh` directly bypasses this and breaks the workflow.

**Only use `gh` commands for actions that have no session equivalent:**
- `gh pr merge` - OK (no session equivalent)
- `gh pr close` - OK (no session equivalent)
- `gh pr ready` - OK (no session equivalent)
- `gh pr edit --add-reviewer` - OK (no session equivalent)
- `gh pr checkout` - only as fallback when `PR_TRIAGE_NO_WORKTREE=1`; otherwise the session auto-checks the PR into the triage worktree.

### Auto-checkout into a per-repo worktree

`pr-review-session view` and `next` automatically check out the PR's branch into a per-repo triage worktree at `${XDG_CACHE_HOME:-~/.cache}/pr-triage-worktrees/<owner>-<repo>`. The summary prints `Worktree: <path>` — use that path for any follow-up action that needs the code on disk (fix CI, resolve feedback, run CodeRabbit, rebase). The same worktree is reused as you step between PRs; the script switches the branch in place.

- **Already checked out elsewhere:** if the PR's branch is already in another worktree (vibe kanban, manual `git worktree add`, or the main repo itself), the script reports that path instead of creating a duplicate.
- **Dirty worktree:** if the triage worktree has uncommitted changes, the script refuses to switch and just prints the existing path. Resolve the WIP, then re-run `view <N>` to switch.
- **Disable:** set `PR_TRIAGE_NO_WORKTREE=1` to skip the worktree behavior entirely.

When acting on a PR, prefer running commands in the printed worktree path (`cd "$WORKTREE" && …` or `git -C "$WORKTREE" …`) rather than re-running `gh pr checkout` in the main repo.

**Invoking other skills during triage:** any skill that operates on "the current branch" or cwd's git state (e.g. `/pr-cleanup`, `/lint`, `/jest`, `/ruby-tests`, `/coderabbit:review`) will silently audit/test the wrong code if invoked from the main repo's cwd while the PR lives in the worktree. Before invoking such a skill, `cd` into the printed `Worktree:` path so the subskill's git/test commands resolve against the PR's checkout. If a subskill auto-detects context, brief it explicitly with the worktree path.

---

# PR Triage Session Workflow

Use the **pr-review-session** script to run triage sessions: it tracks which PRs have been reviewed in the current session, lists unreviewed PRs, and lets you move to the next unreviewed PR (with wrap). Run from the repository root.

> These steps describe the session mechanics used by **both** modes. In the default **autonomous** mode (see "Autonomous Operation" above), you still drive PR selection with `next`, but you skip the per-PR menu (Step 3) for eligible PRs — taking the autonomous actions directly and logging them — and only run the single batched request once everything is exhausted.

## Workflow

### Step 1: Jump to the Top PR

Start the triage loop by running:

```bash
~/.claude/skills/pr-triage/pr-review-session next
```

`next` picks the highest-priority unreviewed actionable PR and shows it. Starting cold (no current PR set) is safe — it does not mark anything reviewed, it just shows the top of the queue. When every actionable PR has been reviewed in the current round, the session auto-resets (preserving snoozes) and loops back to the top — **do not** call `reset` manually for this case, and do not ask the user to.

If `next` reports "No actionable PRs to triage" (nothing for the user to do across the entire repo), inform the user and stop.

Other ways to land on a PR once the loop is running:

- **Specific PR by number**: `~/.claude/skills/pr-triage/pr-review-session view <number>` — shows that PR and sets it as current for the next `next`.
- **Current branch's PR**: `~/.claude/skills/pr-triage/pr-review-session view` (no number).

Optional inspection (do not block the workflow on these):

- `~/.claude/skills/pr-triage/pr-review-session list` — show the pending queue.
- `~/.claude/skills/pr-triage/pr-review-session status` — show repo, reviewed count, current PR.

`reset` is reserved for when the user explicitly wants to abandon in-progress triage state. The auto-loop handles end-of-round wraparound on its own.

### Step 2: Assess PR Status

`pr-review-session view` (and `next`) already prints a summary: branch, author, status, URL, size, mergeable, CI status, reviews, and unresolved feedback count, then runs `gh pr view` for the full body.

Use that output as the assessment. If you need to re-display or analyze further, the same summary is produced by:

```bash
~/.claude/skills/pr-triage/pr-review-session view <number>
```

Infer blockers from the summary (e.g. failing CI, unresolved feedback, merge conflicts) and present them when suggesting actions.

### Step 3: Present Actions

> **Autonomous mode (the default) does NOT use this per-PR menu.** In autonomous mode you take the autonomous actions directly (no menu, no per-PR confirmation) and surface only the gated decisions (merge, mark-ready) and unhandleable items, batched into the single final request described in "Autonomous Operation". Use the menu below only (a) for PRs that are **not eligible** for autonomous handling, or (b) when the user has explicitly asked for interactive/step-by-step triage.

**When you do present the menu, it is MANDATORY — never skip it.** Even when a PR looks "obviously" ready to merge, close, or otherwise act on, you MUST present the options menu and wait for the user's selection. The action label in the session list (e.g. "action: merge") describes what the PR needs from a human; it is **not** a directive to take that action.

**The merge gate applies in both modes.** Merging and flipping draft→ready are never automatic: in interactive mode they require an explicit menu selection; in autonomous mode they are deferred to the final batched request. Autonomy covers prep work (conflicts, CI, bot feedback) — not merge. The **sole exception** is low-risk Dependabot bumps in autonomous mode (green, mergeable, `minor-patch`), which are auto-merged per "Dependabot PRs".

Based on assessment, present relevant options:

```
What would you like to do?
1. Fix failing CI - Checkout branch and fix issues
2. Resolve feedback - Process unresolved review comments
3. Fix conflicts - Rebase/merge to resolve conflicts
4. Request review - Add reviewers to the PR
5. Mark ready - Convert from draft to ready for review
6. Merge PR - Merge the pull request
7. Close PR - Close without merging
8. Run CodeRabbit review - Run a local AI code review on this PR's changes
9. Request CodeRabbit review - Trigger a remote CodeRabbit review via PR comment
10. Snooze - Temporarily hide this PR and revisit later (e.g. 1h, 1d, 1w)
11. Next - Mark reviewed and move to next unreviewed (`pr-review-session next`)
```

Adjust options based on PR state:

- Hide "Mark ready" if not a draft
- Hide "Merge PR" unless the summary's `Mergeable` line reads exactly `Yes`. Any other value (`No - has conflicts`, `No - blocked (required reviews / branch protection)`, `No - branch behind base`, `No - draft`, `No - failing/pending checks`, `Unknown (computing...)`) means do NOT offer Merge. The session summary derives this from `mergeable` (`MERGEABLE` / `CONFLICTING` / `UNKNOWN`) AND `mergeStateStatus` (`CLEAN` / `BLOCKED` / `BEHIND` / `DIRTY` / `DRAFT` / `UNSTABLE` / `HAS_HOOKS` / `UNKNOWN`) — both must be green. `mergeable: MERGEABLE` alone is not enough; it only means no file conflicts.
- Hide "Fix conflicts" if no conflicts
- Hide "Resolve feedback" if no unresolved comments
- Only show "Run CodeRabbit review" if the PR author is NOT the current user (check with `gh api user -q .login`; i.e., it's someone else's code)
- Only show "Request CodeRabbit review" when (1) PR author IS the current user, and (2) the `cr-needs-review` script confirms unreviewed commits exist. **Always run this check** when presenting options for the user's own PRs:
  ```bash
  ~/.claude/skills/pr-triage/cr-needs-review <number>
  # Exit 0 → needs review, SHOW the option
  # Exit 1 → already reviewed, HIDE the option
  ```

### Step 4: Execute Selected Action

**Option 1 - Fix failing CI:**

1. **Review CI run history first.** Before re-running or fixing anything, check whether the failing check has already been re-run previously. Use `gh run list --branch <branch> --limit 5` to see recent runs. If a check has already failed multiple times across different runs, it's almost certainly a real bug — don't re-run, investigate and fix instead. Only re-run if this is the first failure and it looks transient (e.g. timeout, network error, resource exhaustion).
2. Use the worktree printed by the summary (`Worktree: <path>`) — `view`/`next` already checked the PR out there. For GitButler workspaces, fall back to `but status` and create the branch if needed.
3. Identify failing checks and their logs.
4. Fix the issues directly in the worktree.
5. After fixes, commit and push from the worktree.

**Option 2 - Resolve feedback:**

1. Use the worktree printed by the summary — `view`/`next` already checked the PR out there.
2. Invoke the `/resolve-pr-feedback` skill to handle the rest. It has its own interactive workflow for retrieving feedback, presenting options, and implementing fixes.
3. After the skill completes, return to PR assessment.

**Option 3 - Fix conflicts:**

**IMPORTANT: Detect GitButler workspace before rebasing**

First, check if you're in a GitButler workspace:
```bash
git branch --show-current
```

**If on `gitbutler/workspace` branch (GitButler mode):**

1. Use the `/gitbutler` skill to handle the rebase:
   - The skill knows how to work with GitButler virtual branches
   - It will use `but` CLI commands to rebase the virtual branch
   - Example: `/gitbutler rebase <branch-name> onto <base-branch>`

**If on a regular git branch (standard git mode):**

1. Use the worktree printed by the summary (`Worktree: <path>`).
2. Determine the PR's actual base branch from the PR metadata — **never assume `main`**:
   ```bash
   gh pr view <number> --json baseRefName -q '.baseRefName'
   ```
3. From the worktree, fetch and rebase onto `origin/<base-branch>` (always use the remote base branch, never the local one, to avoid stale state):
   ```bash
   cd "<worktree>" && git fetch origin <base-branch> && git rebase origin/<base-branch>
   ```
4. Resolve conflicts.
5. Push updated branch: `git push --force-with-lease`.

**Option 4 - Request review:**

```bash
gh pr edit <number> --add-reviewer <username>
```

**Option 5 - Mark ready:**

```bash
gh pr ready <number>
```

**Option 6 - Merge PR:**

**Only execute this when the user has explicitly chosen to merge in the current turn** — either by selecting "Merge PR" from the Step 4 menu (interactive mode) or by picking the PR in the autonomous final batched request. Do not infer merge intent from action-category labels, "Next" selections, PR size, or the fact that autonomous mode is running. If you're about to run `gh pr merge` and you cannot point to the user's most recent message authorizing this specific merge, stop and ask instead.

**Exception — Dependabot:** a green, mergeable, `minor-patch` Dependabot PR is auto-merged in autonomous mode without explicit per-PR authorization, per the standing opt-in in "Dependabot PRs". This carve-out applies **only** to Dependabot bumps that classify as `minor-patch`; for any other PR the gate above stands.

```bash
gh pr merge <number> --squash  # or --merge, --rebase based on repo settings
```

**Option 7 - Close PR:**

```bash
gh pr close <number>
```

**Option 8 - Run CodeRabbit review:**

1. Use the worktree printed by the summary — `view`/`next` already checked the PR out there.
2. Run the `/coderabbit:review` skill to perform a local AI code review of the PR's changes.
3. After the review completes:
   a. Write the findings to `/tmp/cr-review-pr<number>.md` wrapped in a `<details><summary>CodeRabbit Review Notes</summary>` spoiler block. Use real markdown code blocks (triple backticks with language) for any code snippets inside.
   b. Tell the user to run one of the following to copy to clipboard:
      ```bash
      cat /tmp/cr-review-pr<number>.md | xclip -selection clipboard
      # or if using xsel:
      cat /tmp/cr-review-pr<number>.md | xsel --clipboard --input
      ```
4. Present findings and offer to act on them.
5. Return to PR assessment.

**Option 9 - Request CodeRabbit review:**

1. Comment on the PR to trigger a remote CodeRabbit review:
   ```bash
   gh pr comment <number> --body "@coderabbitai review"
   ```
2. Inform the user that CodeRabbit will process the review asynchronously and results will appear as PR comments.
3. Return to PR assessment or move to next PR.

**Option 10 - Snooze:**

1. Ask the user how long to snooze (e.g. 1h, 4h, 1d, 3d, 1w), or accept inline if already specified
2. Run: `~/.claude/skills/pr-triage/pr-review-session snooze <number> <duration>`
3. The PR will be hidden from the triage list until the snooze expires, then automatically reappear

### Step 5: Continue Loop

After each action:

- **Move to next unreviewed**: `~/.claude/skills/pr-triage/pr-review-session next` — marks current PR as reviewed and shows the next. When every actionable PR has been reviewed in the current round, the session auto-resets (preserving snoozes) and loops back to the highest-priority PR. This is the default — keep running `next` to work through the queue.
- **Jump to another PR**: `~/.claude/skills/pr-triage/pr-review-session view <number>`
- Otherwise, return to PR assessment.

Only call `reset` if the user explicitly asks to abandon the current triage state — the auto-loop handles end-of-round wraparound.

## Status Indicators

| Symbol | Meaning                    |
| ------ | -------------------------- |
| ✓      | Passing / Approved / Ready |
| ✗      | Failing / Blocked          |
| ○      | Pending / In progress      |
| ?      | Unknown / No data          |

## Review Decision Values

| Value             | Meaning                      |
| ----------------- | ---------------------------- |
| APPROVED          | PR has been approved         |
| CHANGES_REQUESTED | Changes have been requested  |
| REVIEW_REQUIRED   | Waiting for required reviews |
| (empty)           | No reviews yet               |

## Handling Git Worktrees

`pr-review-session view`/`next` automatically checks out the PR into a per-repo triage worktree at `${XDG_CACHE_HOME:-~/.cache}/pr-triage-worktrees/<owner>-<repo>` and prints the path as `Worktree: <path>` in the summary. Use that path for any action that touches the code.

If the PR's branch is already checked out in another worktree (e.g. vibe kanban created one), the script reports that path instead of creating a duplicate. If the triage worktree has uncommitted changes, the script refuses to switch and reports the existing path — clean it up (commit/stash/discard) and re-run `view <N>` to switch.

To opt out entirely (e.g. if you don't want the script touching disk), set `PR_TRIAGE_NO_WORKTREE=1`; then fall back to `gh pr checkout <number>` in the main repo.

## Commands Reference

| Command                                     | Purpose                                                   |
| ------------------------------------------- | --------------------------------------------------------- |
| `pr-review-session list`                    | List open PRs not yet triaged this session                |
| `pr-review-session next`                    | Mark current as triaged and show next unreviewed (auto-resets when all reviewed) |
| `pr-review-session view [N]`                | Show PR summary and details; N = number or current branch |
| `pr-review-session status`                  | Show session state (repo, triaged count, current PR)      |
| `pr-review-session snooze [N] <dur>`        | Snooze a PR for a duration (e.g. 1h, 1d, 1w)             |
| `pr-review-session reset`                   | Reset the triage session for this repo                    |
| `gh pr checkout <number>`                   | Manual checkout (only needed when `PR_TRIAGE_NO_WORKTREE=1`) |
| `gh pr ready <number>`                      | Mark draft as ready                                       |
| `gh pr merge <number>`                      | Merge the PR                                              |
| `gh pr close <number>`                      | Close without merging                                     |
| `gh pr edit <number> --add-reviewer <user>` | Add reviewer                                              |
| `cr-needs-review <number>`                  | Check if PR has commits not yet reviewed by CodeRabbit    |
| `dependabot-bump-type <number>`             | Classify a Dependabot PR's bump: `minor-patch`/`major`/`unknown` |
| `dependabot-overlap <number>`               | Exit 0 if an open human PR touches the same manifest (defer auto-merge); exit 1 if clear |
| `failing-actions`                           | List all failing actions across PRs                       |

All `pr-review-session`, `cr-needs-review`, `dependabot-bump-type`, and `dependabot-overlap` commands should be prefixed with the full path: `~/.claude/skills/pr-triage/`

## Tips

- **Actionable only**: The session only shows PRs where you have something to do. Non-actionable PRs (e.g., waiting on someone else, no review requested from you) are automatically excluded.
- **Priority order**: PRs are automatically sorted by action priority: review > resolve conflicts > fix ci > respond > merge > add reviewers > work on. `next` always picks the highest-priority unreviewed PR.
- **Batch triage**: Use `pr-review-session next` repeatedly to work through all actionable PRs in priority order (session tracks progress)
- **Autonomous by default**: Don't ask per-PR. Do all the prep you can on every eligible PR (the user's own / assigned), log each action, and consolidate merge/mark-ready decisions and blockers into one request at the end. See "Autonomous Operation".
- **Activity log**: Every autonomous run appends to `${XDG_CACHE_HOME:-~/.cache}/pr-triage-worktrees/<owner>-<repo>/triage-activity.log`. Point the user to it in your final report.
- **Delegate**: For non-eligible PRs that need someone else's action, leave a comment if useful and note them in the final report
- **Stale PRs**: For PRs with no activity, consider closing or requesting status updates
- **Stacked PRs**: The session only surfaces PRs targeting the default branch, so if a PR is part of a stack, it's already the next one that can land. Don't worry about the rest of the stack — treat it as an independent PR.
