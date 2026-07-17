# Conditional review agents (#7, #8, #9)

These run only when their gate fires — the gate summary lives in SKILL Step 5 and is evaluated every run. When you spawn one of these, read its section here for the full focus, gating rationale, scoring, and routing. All receive the same style default and output shape as the always-on agents (SKILL Step 5).

## Agent #7 — Structural simplification (conditional) `[model: session tier — unpinned]`

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

## Agent #9 — Intent reconciliation (conditional, cycle 1 only) `[model: session tier — unpinned]`

**Gating — spawn only when Step 4b established a reviewable intent** (feature / behavior-changing work with a stated goal); skip otherwise. Runs **once, in cycle 1 only** — it reviews the original change against its purpose, and the per-cycle fix deltas don't need re-reconciling.

Unlike the code-first agents, this one does not start from the code. It models what the change *should* do from intent, then reconciles that model against the implementation — which is how a strong reviewer catches **omission** bugs (state that should reset, a contract left unenforced, a case never handled) that are invisible to an agent anchored on the code that's already there. (Eval: on the omission fixtures it caught defects every code-first agent missed — a state-reset omission 0→2/3, a contract violation 1→2/3. See `evals/`.)

Run it as **two stages in separate subagent contexts** — the separation is the whole point; if one agent sees the code before modelling, the model is contaminated and it collapses into ordinary code-first review:

- **Stage 1 — build the spec (intent only).** Give the subagent the Step 4b intent statement and the changed-file *names* (for scope) — **not the diff, not the file contents**. Ask it to enumerate the behaviors the change must satisfy: features, user-facing steps, state transitions, edge cases, failure modes, invariants — especially state that must reset when inputs change, contracts that must hold, and error paths that must surface. Output: a list of expected behaviors, each with why it matters and what to check.
- **Stage 2 — reconcile (spec + code).** Give a *fresh* subagent the Stage 1 spec plus the whole changed files and the diff. For each expected behavior, decide whether the code satisfies it; flag **OMISSION** (expected, not implemented), **DISCREPANCY** (implemented differently), or **UNHANDLED** (an edge/failure case the spec raised that the code ignores). Each finding is a **question to the author, not a verified defect** — frame it as one.

**Routing and scoring are special (like Agent #7):** these are hypotheses about intent, not verifiable defects, so they are **always routed to ask-user, never auto-fixed**, whatever the score. This agent has the **highest false-positive rate** of any — it will "expect" things the team deliberately cut (scope, YAGNI) and can even mis-model the intent it was handed (in the eval it once "expected" a token refresh the intent explicitly forbade). Lean hard on the learnings Dismissed list (a matching finding scores 0), and in the final report surface these as *questions* kept separate from verified defects. It complements the code-first agents rather than replacing them — the eval shows it *loses* to whole-file #2 on implementation-timing bugs, where the intent is nominally met but a code detail is wrong.

`evals/intent-recon.py` exercises this exact two-stage flow against curated fixtures — use it to measure any prompt change to this agent.
