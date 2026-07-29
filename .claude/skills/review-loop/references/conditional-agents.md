# Conditional review agents (#7, #8, #9, #10)

These run only when their gate fires — the gate summary lives in SKILL Step 5 and is evaluated every run. When you spawn one of these, read its section here for the full focus, gating rationale, scoring, and routing. All receive the same style default and output shape as the always-on agents (SKILL Step 5).

## Agent #7 — Structural simplification (conditional) `[model: sonnet]`

**Gating — only spawn this agent when the diff is substantial.** Skip it entirely (don't spawn) when ALL of these hold: total diff < ~150 changed lines, no single file grew past ~800 lines, and the change is a pure bugfix/config/dependency bump. Small and bot-driven PRs don't benefit from structural review and it only adds noise. When in doubt on a borderline diff, spawn it.

Unlike the other agents, this one is **allowed and expected to read beyond the diff** — open the surrounding files, the module the change lives in, and any shared/general modules it touches. Structural smells are only visible in context.

Look for "code judo" — restructurings that preserve behavior while making the implementation meaningfully simpler:

- A reframing that makes a whole branch, helper, mode, conditional, or layer **disappear entirely** (not just shrink).
- A file the diff pushed past ~1k lines (or meaningfully grew when already large) without a strong reason. Treat this as a smell to weigh, not an automatic block.
- New ad-hoc conditionals, scattered special cases, or one-off branches inserted into otherwise-unrelated flows.
- Feature-specific logic leaking into shared/general-purpose modules, or implementation details leaking through a public API.
- Casts, optionality, or ad-hoc object shapes that obscure a real invariant — where a typed model would make a chain of conditionals collapse.
- A thin abstraction that adds indirection without buying clarity.
- A mutable accumulate-and-reassign flow (per the style default) big enough that restructuring it is invasive — small local cases belong to the always-on agents via the style default, not here.

For each finding, the `suggested_fix` should describe the restructuring in plain language and name what it deletes ("collapse the three `status` string checks into a `Status` union; the `isPending`/`isDone` helpers then disappear"). These are **proposals, not patches** — do not expect them to be auto-applied (see SKILL Step 6 and Step 8a routing). Scored on value-vs-risk and always routed to ask-user.

## Agent #8 — Observability coverage (conditional) `[model: sonnet]`

**Gating — only spawn this agent when BOTH hold:** the diff is substantial/risky (same threshold as Agent #7), AND the repo already has an observability convention — a logger, metrics client, or error reporter visible in the surrounding files. **Skip entirely** if the project logs nothing; don't invent a convention where none exists. As with #7, when in doubt on a borderline diff, spawn it.

This is the mirror of Agent #6 (test coverage): #6 asks "does changed logic have tests?"; #8 asks "if changed logic fails in prod, will we find out?"

Like #7, this agent is **allowed and expected to read beyond the diff** — observability is often satisfied upstream or downstream of the changed line. Confirm a failure path is *actually* unsurfaced, not merely out of frame, before flagging.

1. Enumerate the **failure-bearing** behaviors the diff adds or changes: external I/O (network, DB, API, filesystem), error-handling paths, async / background / queue work that can partially fail, money / auth / security paths, and fallible state mutations. **Ignore** pure in-memory logic, renames, refactors, and UI-only changes — they are not this agent's business.
2. For each, check whether a failure would be **detectable**: is there a log, metric, error report, or surfaced error on the failure path?
3. Flag only failure-bearing changes where a silent failure would matter and nothing surfaces it. Also flag observability the diff **removed or downgraded** on such a path (a deleted log line, an error report dropped, a log level lowered on a failure path). State the symptom concretely: "if this charge fails, the user sees nothing and no log/metric fires — first signal is a support ticket."

Findings here are verifiable (the failure path either surfaces something or it doesn't), so they use the **normal Step 6 rubric** — no special-casing like #7. The fixes are almost always additive (add a log line / metric / error surface), which makes them low-risk under Step 8a and so usually auto-applied.

## Agent #9 — Intent reconciliation (conditional, cycle 1 only) `[model: sonnet]`

**Gating — spawn only when Step 4b established a reviewable intent** (feature / behavior-changing work with a stated goal); skip otherwise. Runs **once, in cycle 1 only** — it reviews the original change against its purpose, and the per-cycle fix deltas don't need re-reconciling.

Unlike the code-first agents, this one does not start from the code. It models what the change *should* do from intent, then reconciles that model against the implementation — which is how a strong reviewer catches **omission** bugs (state that should reset, a contract left unenforced, a case never handled) that are invisible to an agent anchored on the code that's already there. (Eval: on the omission fixtures it caught defects every code-first agent missed — a state-reset omission 0→2/3, a contract violation 1→2/3. See `evals/`.)

Run it as **two stages in separate subagent contexts** — the separation is the whole point; if one agent sees the code before modelling, the model is contaminated and it collapses into ordinary code-first review:

- **Stage 1 — build the spec (intent only).** Give the subagent the Step 4b intent statement and the changed-file *names* (for scope) — **not the diff, not the file contents**. Ask it to enumerate the behaviors the change must satisfy: features, user-facing steps, state transitions, edge cases, failure modes, invariants — especially state that must reset when inputs change, contracts that must hold, and error paths that must surface. Output: a list of expected behaviors, each with why it matters and what to check.
- **Stage 2 — reconcile (spec + code).** Give a *fresh* subagent the Stage 1 spec plus the whole changed files and the diff. For each expected behavior, decide whether the code satisfies it; flag **OMISSION** (expected, not implemented), **DISCREPANCY** (implemented differently), or **UNHANDLED** (an edge/failure case the spec raised that the code ignores). Each finding is a **question to the author, not a verified defect** — frame it as one.

**Routing and scoring are special (like Agent #7):** these are hypotheses about intent, not verifiable defects, so they are **always routed to ask-user, never auto-fixed**, whatever the score. This agent has the **highest false-positive rate** of any — it will "expect" things the team deliberately cut (scope, YAGNI) and can even mis-model the intent it was handed (in the eval it once "expected" a token refresh the intent explicitly forbade). Lean hard on the learnings Dismissed list (a matching finding scores 0), and in the final report surface these as *questions* kept separate from verified defects. It complements the code-first agents rather than replacing them — the eval shows it *loses* to whole-file #2 on implementation-timing bugs, where the intent is nominally met but a code detail is wrong.

`evals/intent-recon.py` exercises this exact two-stage flow against curated fixtures — use it to measure any prompt change to this agent.

## Agent #10 — Prior review feedback (conditional, cycle 1 only) `[model: sonnet]`

**Gating — spawn only when ALL hold:** it's cycle 1 (past feedback is about the original change, not the loop's own fix deltas), the run is **not** on the Step 3b trivial-diff fast path, `gh auth status` succeeds, and the repo has a GitHub remote. **Skip** when the changed files have no merged-PR history, or when `gh` calls fail — report the skip in one line rather than falling back to guesswork.

Every other agent reasons from code. This one reasons from **what human reviewers already said about these exact files**. Agent #3 reads git history — commits and blame, the record of what changed. This agent reads the *conversations*: the review comments that never made it into a commit message, the "we tried that, it breaks X" that lives only in a PR thread. That institutional memory is the most expensive knowledge in the repo and the easiest to lose when the person who wrote it moves on.

Procedure (these commands are verified; `{owner}/{repo}` resolves automatically from the cwd's remote):

1. For each changed file, find the merged PRs that actually touched it — via commits, not search:
   ```bash
   git log --format='%H' -5 -- <path> \
     | xargs -I{} gh api 'repos/{owner}/{repo}/commits/{}/pulls' --jq '.[].number'
   ```
   **Do not use `gh pr list --search "<path>"`** — that is a full-text search over titles and bodies, so it returns PRs that merely *mention* the path and misses ones that changed it without naming it. Verified: on one file it returned a dependency-bump PR that never touched the file.
   Take the most recent handful per file and dedupe across files; this agent earns its cost on the last few PRs, not the whole history.
2. Pull the inline review comments from those PRs:
   ```bash
   gh api 'repos/{owner}/{repo}/pulls/<n>/comments' \
     --jq '.[] | "\(.user.login) @ \(.path):\(.line // .original_line): \(.body)"'
   ```
   Add `gh pr view <n> --json reviews` for summary-level review bodies when the inline comments look thin.
3. **Weight human comments far above bot comments.** In practice most inline comments on these repos are `coderabbitai[bot]`, and much of that volume is analysis blocks, severity badges, and acknowledgment chatter — plus CodeRabbit already reviews each PR once on open, so its generic findings are not news. The valuable signal is a **human** reviewer stating a constraint, and the single most valuable shape is a human *overriding* or *qualifying* a bot ("capped to retry: 1 — one retry smooths transient blips"), because that records a decision with reasoning attached. Skim bot comments for a cited gotcha; read human comments properly.
4. Read for **durable guidance** — a constraint, convention, gotcha, or rejected approach that generalizes beyond that one diff. Then check whether the current diff violates any of it.

What to flag, and what not to:

- **Flag** — the diff repeats something a reviewer previously asked to be changed; it reintroduces an approach that was explicitly rejected; it violates a convention a reviewer stated on this file; it hits a gotcha someone documented in a thread ("this endpoint 404s on empty results, don't assume").
- **Don't flag** — comments that were about that PR's specific code and don't generalize; nitpicks; praise; process chatter ("rebase please", "LGTM"); anything the current diff clearly already accounts for; anything already covered by a CLAUDE.md rule (that's Agent #1's job — don't double-report).

**Every finding must cite its source**: the PR number, the commenter, and a short quote. A finding without a citation is this agent hallucinating precedent, which is worse than silence — put the citation in `reasoning` and reference it in `description` ("PR #1042, @jakecoble: 'don't call this from the request path — it blocks'").

Findings use the **normal Step 6 rubric** and **normal Step 8a routing** — a reviewer having already said the thing is real evidence, so these behave like ordinary defects rather than the proposals #7 and #9 produce. The scorer should treat a well-cited finding as more confident than an uncited one.

**Relationship to the learnings file.** `.git/info/review-loop-learnings.md` accumulates what *this loop* learned per repo; Agent #10 mines what *humans* learned on GitHub. They converge: Step 11 records **every surviving #10 finding** to Accepted patterns — including ones auto-fixed at Step 7, which is a deliberate exception to Step 11's normal "record Step 8b outcomes" rule, because this agent runs once per branch and its findings cost API calls to rediscover. Over time a repo's most-repeated review feedback migrates from GitHub into the learnings file, where the always-on agents get it for free. That migration is the point: #10 should get *quieter* on a repo you work in often.
