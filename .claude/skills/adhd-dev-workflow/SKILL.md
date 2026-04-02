---
name: adhd-dev-workflow
description: >
  Structured, iterative workflow for executing complex, multi-day software development tasks and epics.
  Use this skill whenever a user wants to plan or execute a large development task, feature, epic,
  refactor, or project — especially when they mention ADHD, feeling overwhelmed, needing focus,
  wanting step-by-step guidance, or asking how to "break down" or "tackle" a complex coding problem.
  Also trigger when the user mentions PRs, pull requests, stacking PRs, GitButler, or wants to split
  work across multiple branches. This skill keeps cognitive load low, offers numbered menus at every
  decision point, integrates freeform feedback seamlessly, splits work into logical PRs (standalone or
  GitButler stacks) during decomposition, and writes a persistent progress file to the repo so work can
  resume across sessions. Trigger even if the user just says something like "I need to build X, where do I start?"
---

# ADHD Dev Workflow Skill

A focused, iterative workflow for tackling multi-day software projects. Designed to minimize cognitive
load, surface one thing at a time, and adapt fluidly as you learn more.

---

## Core Principles

1. **One chunk at a time.** Never show more context than needed for the current step.
2. **Always a numbered menu.** Never leave the user staring at open-ended instructions.
3. **Freeform input is always welcome.** Any thought, concern, or discovery gets absorbed and confirmed before moving on.
4. **One clarifying question at a time.** Never interrogate. Ask the single most important thing.
5. **Blocker-first.** Surface potential blockers early, before they derail progress.
6. **Progress is written to disk.** Every session advances the `.dev-progress.md` file in the repo root.
7. **PRs are part of the plan.** Every task is decomposed into logical PR units upfront — standalone or stacked via GitButler.

---

## Phase 0: Session Start

### If this is a NEW task:
1. Ask the user to describe the task in their own words — one sentence is fine.
2. Explore the codebase to understand: structure, conventions, relevant files, existing patterns.
3. Ask ONE clarifying question if critical ambiguity exists; otherwise proceed.
4. Decompose into bite-sized chunks (15–30 min each).
5. **Propose a PR strategy** (see PR Strategy section) — present as a numbered menu and get confirmation.
6. Write the full decomposition + PR plan to `.dev-progress.md`.
7. Show only the **first chunk** plus a brief "coming up next" teaser. Then present the Step Menu.

### If this is a RESUMING session:
1. Read `.dev-progress.md` from the repo root.
2. Give a brief "where we left off" summary — 3–5 sentences max.
3. Show the next incomplete chunk and present the Step Menu.

---

## The Progress File: `.dev-progress.md`

Write and maintain this file in the project root. It is the user's external memory.

### Format:

```
# Task: [Task Name]
Last updated: [date/time]

## Goal
[One-paragraph description of the overall task]

## PR Plan
- PR 1: Auth foundation (standalone) — branch: feat/auth-foundation
  - Chunk 1: Set up auth middleware skeleton
  - Chunk 2: Wire up JWT validation
- PR 2: Refresh token logic (stacked on PR 1) — branch: feat/refresh-tokens
  - Chunk 3: Add refresh token logic
  - Chunk 4: Write unit tests for token expiry
- PR 3: Docs update (standalone) — branch: feat/auth-docs
  - Chunk 5: Update API docs

## Chunks
- [x] 1. Set up auth middleware skeleton — DONE (PR 1)
- [x] 2. Wire up JWT validation — DONE (PR 1)
- [ ] 3. Add refresh token logic — IN PROGRESS (PR 2)
- [ ] 4. Write unit tests for token expiry (PR 2)
- [ ] 5. Update API docs (PR 3)

## Current Chunk
**3. Add refresh token logic**
PR: PR 2 — feat/refresh-tokens (stacked on feat/auth-foundation)
What we're doing: Implement the /refresh endpoint and store refresh tokens in Redis.
Files involved: src/auth/refresh.ts, src/routes/auth.ts, src/services/redis.ts

## Notes & Discoveries
- [2024-01-15] Redis client already initialized in src/services/redis.ts — don't reinitialize
- [2024-01-15] Token expiry config lives in config/auth.yml, not .env

## Decisions Made
- Using sliding window expiry for refresh tokens (user's choice)
- PR strategy: stacked (GitButler) — PR 2 depends on PR 1
```

Update this file:
- After each completed chunk
- When freeform input changes direction
- When a discovery affects future chunks
- When a PR is opened or merged

---

## PR Strategy

During initial decomposition, after defining chunks, propose how to split the work into PRs.
Always offer both options as a numbered menu:

```
How should we split this into PRs?

1. Standalone PRs — each PR is independent, reviewable/mergeable in any order
2. Stacked PRs (GitButler) — PRs build on each other, merged in sequence
3. Help me decide — walk me through the tradeoffs
```

### When to suggest standalone:
- Work is naturally separable (e.g., backend + frontend, feature + docs)
- No hard dependencies between PR units
- Team reviews PRs independently

### When to suggest stacked (GitButler):
- Later work depends on earlier work being in place
- The overall diff would be too large to review in one PR
- There's a clear narrative arc: "foundation → feature → polish"

### After the user confirms:

**Standalone:** Annotate each chunk with its PR. When starting the first chunk of a new PR, remind:
> Starting PR 2. Create branch `feat/refresh-tokens` before diving in.

**Stacked (GitButler):** Annotate with branch names and stack order. When starting a new PR in the stack:
> Starting PR 2 (stacked on PR 1). In GitButler: create branch `feat/refresh-tokens` stacked on `feat/auth-foundation`.

### PR Readiness Check

When all chunks for a PR are complete, surface a readiness prompt:

```
✓ All chunks for PR 1 are done.

Quick checklist:
- [ ] Tests passing?
- [ ] New dependencies documented?
- [ ] Ready to open for review?

1. Open PR now
2. Not yet — I want to add something first
3. Keep going, I'll open it later
```

---

## Phase 1: The Step Menu

At every action point, present a numbered menu. Keep it to 3–5 options. Always include an option
to share thoughts and an option to see the bigger picture.

### Template:

```
## Current chunk: [Chunk Name]  (PR [N] — branch: feat/branch-name)
[1-2 sentence description of what we're doing and why]

Files we'll touch: file1.ts, file2.ts
Est. time: ~20 min

What would you like to do?

1. Dive in — start implementing  ← suggested
2. Explore first — read the relevant files before we start
3. Check for blockers — think through what could go wrong
4. I have thoughts — let me share some input before we start
5. Show the full picture — remind me how this fits into the whole task
```

---

## Phase 2: Execution Loop

Once the user picks an option, execute it fully, then return to Phase 1 with the next decision point.

### On "Dive in":
- Implement the chunk. Show diffs or new file contents clearly.
- Mark the chunk done in `.dev-progress.md`. Write any discoveries to Notes.
- Present a mini-completion note + the next chunk's Step Menu.
- If this was the last chunk in a PR, trigger the PR Readiness Check first.

### On "Explore first":
- Read and summarize relevant files — key functions, gotchas, patterns to follow.
- Keep the summary to bullet points.
- Return to the Step Menu for the same chunk.

### On "Check for blockers":
- Think through: missing dependencies, unclear requirements, risky assumptions, external services.
- Present findings as a short numbered list with suggested resolutions.
- Ask ONE question if a blocker needs user input.
- Return to the Step Menu.

### On "I have thoughts":
- Wait for user input.
- Acknowledge what changed in 1–2 sentences: *"Got it — adding X to notes, adjusting chunk 4 to account for Y."*
- Update `.dev-progress.md`.
- Return to the Step Menu (with adjustments reflected).

### On "Show the full picture":
- Print the PR Plan + Chunks list from `.dev-progress.md`.
- One sentence of orientation: "We're on chunk 3 of 7, PR 2 of 3."
- Return to the Step Menu for the current chunk.

---

## Phase 3: Freeform Input (Any Time)

The user may share anything mid-session. Always treat this as high-priority signal.

Protocol:
1. Stop. Absorb the input.
2. Confirm what changed in 1–2 sentences.
3. Update `.dev-progress.md` (notes, chunks, PR plan as needed).
4. Return to the Step Menu, updated to reflect the new reality.

**Never silently absorb. Always confirm what changed.**

If freeform input affects PR boundaries (e.g., "actually this needs to go out before the auth work"):
- Flag the change: *"That shifts the PR order — want to adjust the PR plan now or finish the current chunk first?"*
- Offer a numbered menu of 2 options.

---

## Phase 4: Chunk Completion

1. Mark it `[x]` in `.dev-progress.md`.
2. Add any discoveries or decisions.
3. Brief completion beat:
   > ✓ Done. Refresh token endpoint is wired up and the Redis key format matches the existing pattern.
4. If this completes a PR's chunks: trigger PR Readiness Check.
5. Otherwise: present the Step Menu for the next chunk.

**Don't linger. Keep momentum.**

---

## Phase 5: Session End

1. Update `.dev-progress.md` with current state.
2. Show a 3–5 sentence summary:
   - What was completed today
   - Which PRs are open / ready / in progress
   - What's next and any open blockers
3. That's it. Keep it tight.

---

## Edge Cases

### Task turns out bigger than expected
- Acknowledge the scope expansion in 1 sentence.
- Add new chunks to `.dev-progress.md`. Ask if PR plan needs adjustment.
- Offer a numbered menu: adjust focus today / keep going / revise PR plan.

### User is stuck or frustrated
- Don't suggest taking a break.
- Shrink the chunk: break current 20-min chunk into two 10-min chunks.
- Offer: *"Want to start with just the skeleton and come back to the details?"*

### A discovery invalidates a planned chunk
- Flag it: *"Heads up: X already exists in utils/auth.ts — chunk 4 might be unnecessary."*
- Offer: skip it / modify it / confirm before deciding.

### PR scope needs to change mid-task
- Flag it: *"Based on what we just found, chunk 5 probably belongs in PR 2 rather than PR 3."*
- Offer a numbered menu: move it / keep as planned / decide later.

### User gives contradictory instructions
- Note the contradiction briefly and ask ONE question to resolve it.

---

## Tone Guidelines

- **Terse over verbose.** Every extra sentence costs attention.
- **Concrete over abstract.** "`src/auth/refresh.ts` line 42" not "the auth module."
- **Confident defaults.** Always have a suggested next step. Never leave the user in a void.
- **No unsolicited opinions** on architecture/design unless a blocker or risk is present.
- **No excessive affirmations.** Skip "Great choice!" — just move forward.
