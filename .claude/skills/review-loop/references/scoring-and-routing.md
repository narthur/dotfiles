# Scoring rubric (Step 6) and risk classification (Step 8a)

## Step 6 — the rubric passed verbatim to each Haiku scorer

> Score this finding 0-100 for confidence that it is a real, actionable issue in this PR.
>
> - **0**: Not confident at all. False positive that doesn't survive light scrutiny, or pre-existing issue not touched by this diff.
> - **25**: Somewhat confident. Might be real, might not. Couldn't verify.
> - **50**: Moderately confident. Real issue, but a nitpick or rare in practice.
> - **75**: Highly confident. Verified real, likely to bite in practice. Important to functionality, or directly named in CLAUDE.md.
> - **100**: Absolutely certain. Verified, will hit frequently, evidence is direct.
>
> If a finding matches anything in the learnings file's Dismissed section, score it 0.
> If it matches an Accepted pattern, raise that finding's score by 10 (cap at 100).
>
> Return a score for every finding in the batch, each keyed to its finding (e.g. by index or file:line), as an integer 0-100. Score each finding independently — do not let one finding's score anchor another's.

**Structural findings (Agent #7) score differently.** The rubric above is for verifiable defects; a simplification is subjective and will never be "verified true," so it would score low and get filtered out unfairly. For Agent #7 findings, score on *value vs. risk* instead: how much complexity the restructuring deletes (a whole layer/branch disappearing scores high; a cosmetic tidy scores low) balanced against how invasive the refactor is. Regardless of the resulting score, structural findings are **always routed to ask-user** (Step 8a) and are never auto-applied — the score only sets their ordering and whether they're surfaced as a blocker vs. a nit in the final report (Step 14).

**Intent-reconciliation findings (Agent #9) score differently too.** These are questions about intent, not verified defects, so the confidence rubric would unfairly bury them. Score on *plausibility × impact-if-true*: how likely the gap is real given the intent, times how much it would matter if so. First apply the Dismissed-list check (a finding matching it scores 0) — this agent generates the most scope-expectation false positives, so that suppression carries the most weight here. Like #7, Agent #9 findings are **always routed to ask-user**, never auto-applied; the score only orders them and sets blocker-vs-question framing in the final report. Surface them in the report as *questions*, kept separate from verified defects.

## Step 8a — the three risk dimensions and the rules that override them

A finding goes to **auto-fix** when all three are low-risk; otherwise **ask-user**.

1. **Reversibility — how hard is this to roll back?**
   - *Low:* pure addition (new test, new doc, new helper that's only consumed once), or a localised edit (<20 lines, single file) with no API change.
   - *High:* deletes existing behavior, modifies a public type/export, touches >2 files, or changes anything in a migration / schema / generated code.

2. **Blast radius — what does this change affect?**
   - *Low:* internal to one file; or comment-only; or test-only.
   - *High:* any exported function's signature; any prop a sibling component reads; anything imported by ≥3 files.

3. **Forward-binding — does this lock in a future direction?**
   - *Low:* tactical fix that doesn't constrain later design (e.g. inlining a value, tightening a guard, adding a test).
   - *High:* introduces a new abstraction, dependency, naming convention, or architectural seam that other code will follow.

Plus three hard rules that override the matrix:

- **Structural finding (from Agent #7)** → always ask, never auto-apply. A behavior-preserving restructuring is inherently high-blast-radius and high-forward-binding; surface it as a proposal and let the user decide. This holds even if the Haiku score is ≥80.
- **Suggested fix is unclear or conflicts with current state** → always ask. (Same as Step 7.)
- **A `CLAUDE.md` file or learnings entry explicitly says "always ask the user about X"** → always ask.

