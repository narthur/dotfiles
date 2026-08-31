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

**Security findings never reach this rubric.** The security review's Stage-2 false-positive filter is their scorer (confidence 1-10 → score ×10), and its floor is higher than the loop's general band: **nothing below 80 is actioned** — no 50-79 ask band for security, because upstream's 8/10 threshold is most of what buys the low false-positive rate. Sub-80 security findings are not lost, though: Step 14 lists each one, since a wrongly-dropped security finding is otherwise invisible to a non-expert forever. `bucket.py` enforces this via `SECURITY_AGENTS` / `SECURITY_FLOOR`. Details: `references/security-review.md`.

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

Plus four hard rules that override the matrix:

- **Structural finding (from Agent #7)** → always ask, never auto-apply. A behavior-preserving restructuring is inherently high-blast-radius and high-forward-binding; surface it as a proposal and let the user decide. This holds even if the Haiku score is ≥80.
- **Suggested fix is unclear or conflicts with current state** → always ask. (Same as Step 7.)
- **A `CLAUDE.md` file or learnings entry explicitly says "always ask the user about X"** → always ask.
- **An authorization finding (`agent: "5-security-authz"`)** → always ask, never auto-apply, at any score. Adding or tightening an authz check is high-blast-radius by construction: the failure mode is locking legitimate users out of production, and it is the one class where an auto-applied wrong fix looks exactly like a right one. Injection fixes (parameterize a query) and data-exposure fixes (drop a field from a log payload) are mechanical and subtractive — those take the normal matrix.


## Framing the question for non-expert readers (Step 8b)

The user is choosing whether to apply a fix; they need enough context to decide without re-reading the diff. The Haiku scorer's confidence was 50-79, which means *you* aren't sure either — so the user is genuinely being asked to make a judgment call.

Before the options, write a short framing in the `question` field that covers:

1. **Why you're asking instead of auto-fixing** — name the specific Step 8a dimension(s) that pushed this finding into ask-user (e.g. "high blast radius — touches 4 files and changes an exported signature", "high forward-binding — introduces a new helper module other code will follow", "suggested fix conflicts with current state — needs human resolution", "learnings entry says always ask about X"). One short clause is enough. This tells the user *why their input is required*, not just what the finding is.
2. **What the code in question does**, in plain language — name the function/file, but explain its role without assuming the user remembers the architecture.
3. **What the reviewer is concerned about**, stated as the concrete risk (not the abstract category). "If the user signs out mid-fetch, the old friend list could overwrite the new one" beats "race condition in async state writes."
4. **Why it's borderline** — what makes the issue real, and what makes it possibly not worth fixing (e.g. "currently safe because X, but X isn't guaranteed forever").
5. **What changes if applied** — number of lines, whether tests change, whether behavior changes for any current user.

Write this for a reader who knows the codebase shallowly. Avoid jargon the user wouldn't have used themselves (UUID, predicate, idempotent, etc.) unless you also define it inline. If a term is load-bearing for the decision, define it in one phrase.

**If the user replies "I don't understand" / "explain more" / similar**, do not just re-ask. Step back and explain the finding from first principles in your text response — what the function does, what the situation is, what the answer is today, what the reviewer suggests, and a side-by-side trade-off (a short markdown table works well). Then re-issue the question with a tighter framing. The user should be able to act on the second ask without further questions.

**Do not surface uncertainty by making the user resolve it.** If your scorer landed at 50-79, that's because the finding is genuinely ambiguous. Frame it as "judgment call" rather than "I'm not sure" — the user is the decider, not the rubber-stamp.
