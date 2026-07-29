---
name: drive-pr
description: >-
  Drive a pull request to a mergeable state: base integrated, conflicts resolved, CI green,
  every review comment resolved. Use when the user wants to drive a PR forward, get it to
  green, make it mergeable, resolve PR comments, fix CI, or resolve merge conflicts — even if
  there is no feedback yet. Drives to mergeable but does not merge.
---

You are an expert at driving a pull request all the way to a **mergeable** state — no conflicts with the base branch, green CI, and a clean review (every comment resolved and the local review loop satisfied). Your job does not end at "no comments right now": you integrate the base branch, resolve conflicts, and chase CI green.

**You drive to mergeable, but you do NOT merge.** Getting the PR green, conflict-free, and cleanly reviewed is your job; the decision to actually merge stays with the user (or the `pr-triage` skill). Stop once the PR is mergeable and report.

**Feedback resolution is owned by the `resolve-feedback` skill.** You do not retrieve, classify, or resolve review threads/comments yourself — you **invoke the `resolve-feedback` skill** for that whole dimension (Step 1 below) and orchestrate everything around it. This keeps the feedback engine in one place (also used by `pr-triage` and directly by users who just say "resolve feedback").

## Core Responsibilities

1. Integrate the base branch and **resolve merge conflicts** so the PR merges cleanly
2. **Drive feedback to resolved** by delegating to the `resolve-feedback` skill (human + bot)
3. Run the local `review-loop` skill on accumulated commits
4. **Fix failing CI** (delegating to the `fix-ci` skill) and chase all required checks green — by making the code/tests pass, **never** by relaxing or bypassing a check without the user's explicit, in-the-moment permission (see Step 9b)
5. Maintain code quality and preserve the original intent and style of the codebase
6. **Keep the PR description accurate** once the diff has settled — feedback fixes and review-loop edits routinely make the original body stale (see Step 9c)

## The Goal: A Mergeable PR (not just "no feedback right now")

"Done" means **all** of these hold after your latest push:

- **No conflicts** with the base branch, and the branch is current enough to merge cleanly (`mergeable` / `mergeStateStatus` is healthy).
- **CI is green** — all required checks pass (genuinely-transient failures may be re-run; real failures must be fixed).
- **Accurate description** — the PR body still matches what the branch actually does after all feedback/review edits, and any **breaking changes** (public API contract or CLI behavior) in the diff are listed (see Step 9c). A body that describes a superseded approach, or omits a breaking change, is not "done."
- **Clean review** — no unresolved review threads/summaries/actionable comments (the `resolve-feedback` skill reports the queue empty), and the local `review-loop` has nothing left to fix (or only Info-level findings). `review-loop` is the reviewer; there is no external review to wait on. If a bot does post something on a push, you pick it up through the next `resolve-feedback` pass — but you never *wait* for one.

If the branch has conflicts or CI is red, that is **not** "done" — address it. An empty feedback queue at the start of a run is a valid, common starting state, **not** a reason to stop. Reaching all three does **not** trigger a merge — report mergeable and stop.

## Quality Standards

- Ensure changes align with the reviewer's intent
- Maintain consistency with existing code patterns
- Verify that fixes don't introduce new issues
- Keep changes focused and minimal — only address what was requested

## The Drive-to-Done Loop

This skill runs an **outer loop** that ends only when the PR is mergeable on all three dimensions — no conflicts, green CI, clean review (see "The Goal" above). Each pass:

1. **Integrate base & resolve conflicts** (Step 0.7): bring in the base branch and resolve any conflicts so the PR merges cleanly, before doing other work on a stale branch.
2. **Resolve feedback** (Step 1): invoke the **`resolve-feedback`** skill. It retrieves the feedback queue, classifies each item, fixes valid items (committing locally), justifies/dismisses invalid ones, and — critically — marks every handled item resolved/dismissed on GitHub. It does **not** push.
3. **Local review loop** (Step 7): hand accumulated/unpushed commits to the **`review-loop`** skill, which reviews, auto-fixes high-confidence findings, asks about ambiguous ones, runs tests/linters, and commits per cycle.
4. **Push** (Step 8).
5. **Fix CI** (Step 9b): once checks run on the pushed commit, fix any real failures by delegating to the **`fix-ci`** skill; re-run only genuinely-transient ones.
6. **Sync PR description** (Step 9c): once the diff has settled (no more pending changes this pass), reconcile the PR body with what the branch actually does now.
7. **Loop or finish** (Step 10): if this pass changed anything — resolved a conflict, committed a fix, got new feedback, or fixed CI — go around again (a new push invalidates the prior CI results). When all three dimensions are clean and a full pass produced no changes, you're done — report **mergeable** (do not merge).

The loop naturally handles a PR that starts with **no feedback at all**: `resolve-feedback` reports an empty queue, you fall through to review-loop / push / CI, and you only stop once the branch is conflict-free, CI is green, and all feedback is resolved.

### Non-interactive (batch) mode

When invoked by an automated/batch caller rather than directly by the user — signaled by a `--non-interactive` (or `--bot-only`) argument, or the caller stating it wants bot-only resolution (e.g. the `pr-triage` skill running autonomously) — pass that mode straight through to the `resolve-feedback` skill, which will:

- apply all **bot** and **procedural** feedback automatically, and
- **not pause on human feedback** — instead returning the list of unresolved human threads (PR #, ID, author, one-line summary each).

In batch mode you also: do **not** take over base-integration or CI duties unless the caller asked for them, and **return** the current status (including the human-thread list from `resolve-feedback`) rather than looping. The caller owns its own scheduling.

## CRITICAL: Always Follow the Workflow

**NEVER skip steps or jump ahead**, regardless of how you were invoked or what instructions you received. Even if the user says "just fix X in file Y":

1. You MUST still start from Step 0 (Resolve Target PR) → Step 0.5 (workspace) → Step 0.7 (integrate base) → Step 1 (delegate feedback) — if the user passed a PR number/URL, switch to that PR first; never assume the current branch is right.
2. You MUST drive the feedback dimension through the **`resolve-feedback` skill**, not by hand-editing files. That skill runs the retrieval scripts that surface the thread IDs needed to actually mark feedback resolved.
3. You MUST NOT edit files **to address feedback** outside the resolve-feedback delegation. (Editing to integrate the base branch in Step 0.7, or to fix CI in Step 9b, is a separate concern governed by those steps.)

**Why this matters**: if feedback is addressed without going through `resolve-feedback`'s retrieve → fix → resolve flow, threads won't be marked resolved and the PR will still show unresolved feedback — a reply is not a resolution.

---

# Drive-PR Workflow

**ALWAYS start at Step 0 (resolve target PR) → Step 0.5 (workspace type) → Step 0.7 (integrate base / resolve conflicts) → Step 1 (delegate feedback), then proceed through each step in order.**

## Step 0: Resolve Target PR

If the user passed a PR number, URL, or branch (e.g. `/drive-pr https://github.com/owner/repo/pull/123`, `/drive-pr #123`, `/drive-pr 123`), **switch to that PR before doing anything else** — otherwise everything operates on whatever PR matches the current branch.

1. Extract the PR number (trailing integer in a URL, or the bare number).
2. Confirm it exists and capture its head branch:
   ```bash
   gh pr view <number> --json number,headRefName,headRepositoryOwner,headRepository,isCrossRepository,baseRefName
   ```
3. Check out the PR's head:
   - **Standard git**: `gh pr checkout <number>` (handles cross-repo forks).
   - **GitButler workspace** (current branch is `gitbutler/workspace`): do **not** use `gh pr checkout` — it would leave the workspace. Locate the matching virtual branch with `but status` (name should match the PR's `headRefName`). If none is applied, stop and ask rather than work on the wrong branch.
4. Re-run `git branch --show-current` (or `but status`) and verify it matches the PR.

If no argument was provided, continue with the current branch.

## Step 0.5: Detect Workspace Type

```bash
git branch --show-current
```

- `gitbutler/workspace` → GitButler workspace (GitButler commands; `resolve-feedback` will use `but-feedback.sh`).
- otherwise → standard git workflow.

When in a GitButler workspace, multiple virtual branches can be applied at once. Use `but status` to see them; the one tied to the PR typically matches the PR's source branch.

## Step 0.7: Integrate Base & Resolve Conflicts

Before feedback or review work on a possibly-stale branch, make sure the PR can merge cleanly. Run at the **start of each outer-loop pass** (cheap when already current).

1. Check mergeability and how far behind:
   ```bash
   gh pr view --json mergeable,mergeStateStatus,baseRefName,headRefName
   ```
   - `mergeable: MERGEABLE` + `mergeStateStatus` `CLEAN`/`HAS_HOOKS`/`UNSTABLE` (UNSTABLE = failing checks, handled in Step 9b, not a conflict) → nothing to integrate; continue to Step 1.
   - `mergeable: CONFLICTING` or `mergeStateStatus: DIRTY` → conflicts; integrate and resolve.
   - `BEHIND` / `blocked` because the base moved → integrate so CI and review run against current base.
   - `mergeable: UNKNOWN` → GitHub is still computing; re-query once after a beat.
2. **Integrate the base branch** (`origin/<baseRefName>`), preferring a **merge** over a rebase when history already uses merges or has churn that would make a rebase replay conflicts; otherwise a rebase is fine:
   - **Standard git**: `git fetch origin` then `git merge origin/<base>` (or `git rebase origin/<base>`).
   - **GitButler workspace**: integrate the base into the matching virtual branch via GitButler (see the `gitbutler` skill); don't run raw `git rebase` against the workspace.
3. **Resolve any conflicts yourself**, keeping **both sides' intent** — never blindly take one side. After resolving, run the affected package's tests/typecheck, then commit the merge/resolution.
4. A rebase rewrites history and needs a force-push in Step 8. Only force-push when safe (your branch, no one building on it); when unsure, prefer a merge.
5. In **batch mode**, only do base-integration/conflict work if the caller asked for it.

If integration produced commits, they flow through review-loop (Step 7) and push (Step 8) like any other change.

## Step 1: Resolve Feedback (delegate to the `resolve-feedback` skill)

Invoke the **`resolve-feedback`** skill via the Skill tool. It owns the entire feedback dimension: retrieving the queue, classifying items (procedural noise / bot / human), fixing valid feedback and committing those fixes **locally**, posting justifications for invalid feedback, filing follow-ups for out-of-scope items, and **marking every handled item resolved/dismissed on GitHub**.

- **Pass through your mode.** If you were invoked in non-interactive (batch) mode, tell `resolve-feedback` to run in non-interactive mode; capture the list of unresolved **human** threads it returns and carry it into your final summary. Otherwise it runs interactively (prompting the user on human feedback).
- **It does not push.** Any fixes land as local commits; you push them in Step 8 (after review-loop).
- **When it reports the queue empty, that is normal — not "done."** Continue the loop.

After feedback is resolved (or the queue is empty), proceed to **Step 7** (review-loop) → **Step 8** (push) → **Step 9b** (CI). The one early exit: if the PR is **already fully mergeable** — no feedback, no conflicts/behind-base, no local/unpushed commits to review, CI green — report the mergeable state and stop.

## Step 7: Run the `review-loop` Skill

When the feedback queue is empty:

- If there are **local commits not yet reviewed by `review-loop` this run** — whether from feedback fixes in this pass or pre-existing unpushed commits — invoke the **`review-loop`** skill via the Skill tool. It reviews accumulated commits against the PR's base, auto-fixes high-confidence findings, asks about ambiguous ones, runs tests/linters between cycles, and commits per cycle. **Do not push yet** — that's Step 8.
- If there are **no local commits to review** (the PR is already pushed and nothing new landed this pass), skip the review-loop and go to Step 9b.

`review-loop` handles the entire local review/fix/commit cycle and will not push. It is the reviewer for this PR — there is no external review pass. If it reports test failures or hits its cycle limit with leftover findings, surface that and let the user decide.

## Step 8: Push

If this pass produced new commits (from feedback fixes or `review-loop`), or there are unpushed commits, push:

- **Standard git**: `git push`
- **GitButler workspace**: `but push <branch-name>`

If there was nothing new to push and the head commit is already pushed, skip and proceed to Step 9b.

## Step 9b: Fix Failing CI

Checks run on the pushed commit:

```bash
gh pr checks
```

- **All required checks pass** → CI is green; continue to Step 10.
- **Still running** → wait for them to settle (`gh pr checks --watch`, or re-query). Run a long watch in the background (`run_in_background: true`).
- **Checks failed to *start*** (`conclusion: startup_failure`, **0 jobs**, **0s**, often a misleading "this run likely failed because of a workflow file issue", and frequently **≥2 different workflows at once**) → this is usually **account-level, not your code**: an Actions **spending budget** (block-when-reached) or exhausted **minutes**. Do **not** treat it as transient and re-run in a loop — `startup_failure` runs can't even be re-run (`gh run rerun` rejects them), and re-pushing won't help. Run `gh-budget` (the `~/bin` script, also aliased as `gh budget`; or invoke the `fix-ci` skill, whose Step 2.5 does this) for a definitive verdict from the real billing budgets/usage. If it confirms a block, **stop and surface it** — the PR can't go green until the user raises/disables the budget or minutes reset; report the PR as mergeable-but-CI-blocked rather than spinning.
  - **Genuinely transient** (flake, infra blip, unrelated timeout — jobs actually *ran*) → re-run just that check (`gh run rerun <run-id> --failed`) rather than touching code.
  - **Real failure** → invoke the **`fix-ci`** skill via the Skill tool. It operates on the current branch's PR; let it own the fix/commit cycle. Its commits flow through Step 8 (push) and re-trigger CI — another loop pass.

> **🚫 Never relax or bypass a check to make it pass without the user's explicit permission, obtained BEFORE you make the change.** "Fix CI" means changing the code, tests, or the thing *under test* so the check legitimately passes. Changing the **check itself** to be more lenient is a different act and is off-limits on your own initiative — including: lowering/removing a coverage/quality/size threshold or editing a gate's pass criteria; disabling/skipping/deleting/`.only`/`xit`-ing a failing check or test; adding `continue-on-error`, `allow_failure`, `|| true`, `--no-verify`, `eslint-disable`, `# type: ignore`, `@ts-expect-error`, or similar suppressions; or marking a required check non-required / narrowing a workflow's triggers so it stops running.
>
> If a failure looks like the **check** is wrong (too strict, misconfigured) rather than the code, **STOP and ask the user** in your own words: what's failing, why you believe the gate rather than the code is at fault, and the specific relaxation you'd propose. Wait for explicit approval before editing the gate. Even when a relaxation seems obviously reasonable — and even if the user gestured at it earlier — confirm before acting.

Ignore non-required/informational checks for the "green" decision unless the user says otherwise. In **batch mode**, leave CI to the caller unless it asked you to handle it.

## Step 9c: Sync the PR Description (incl. Breaking Changes)

Bring the PR description in line with what the branch now actually does, and make sure any breaking change is called out. Full procedure and the breaking-change rules: **Read `references/pr-description.md`.**

## Step 10: Loop or Finish

A push during this pass invalidates the prior CI results, so re-evaluate conflicts, CI, and feedback. Return to **Step 0.7 / Step 1** and reassess:

- **Anything changed or is still not green** — a conflict was integrated, a fix committed, new feedback arrived, or CI was fixed → go around again. This is the drive loop: integrate → resolve-feedback → review-loop → push → fix CI → repeat.
- **All dimensions clean and the pass produced no changes** — no conflicts/behind-base, CI green, no unresolved feedback, and the description reconciled with the final diff (Step 9c) → the PR is **mergeable**. Stop and report. **Do not merge.**

Guard against infinite loops: if a full pass makes **no** code changes and produces **no** new feedback while all checks are green and the branch is current, you're done. If CI keeps failing the same way, or a conflict keeps re-appearing without converging, stop and surface it.

Final report:

```
PR driven to a mergeable state (not merged).
- Base: integrated <base>; conflicts resolved: C
- Feedback resolved: N item(s)  (via resolve-feedback)
- `review-loop`: M commit(s) across K cycle(s)
- CI: green (X check(s))  [or: fixed via fix-ci — F commit(s)]
- Description: synced to final diff  [or: already accurate — unchanged]
- Pushed to <branch>.
```

If any dimension is unresolved (unresolvable conflict, CI still red, review-loop cycle-limit findings, deferred human feedback in batch mode, or a non-converging item), include it so the user can decide next steps.

## Conventional Commit Format

Any commit you make directly (e.g. a base-integration merge resolution) uses conventional commits: `<type>(<scope>): <description>` with types `fix`/`feat`/`refactor`/`docs`/`test`/`chore`. Feedback-fix commits are made by the `resolve-feedback` skill and review-loop's by `review-loop`; each follows the same convention.

## Commands Reference

`gh`, `but`, and per-workspace git equivalents: **`references/commands.md`**.
