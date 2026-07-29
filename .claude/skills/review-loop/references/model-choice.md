# Model choice — why every review agent is pinned to `sonnet`

Decision record for the model tier in SKILL.md ("Model tier" under the agent
fan-out). Read this before changing a `[model: ...]` tag.

## Decision (2026-07-17)

**All review agents — #1 through #9 — are pinned to `sonnet`.** `sonnet`
currently resolves to **Sonnet 5**.

Previously the deep-reasoning agents (#2 bugs, #5 security, #7 structural,
#9 intent-recon) were left *unpinned* so they inherited the session model —
Opus on an Opus session — on the theory that a missed inference there is a
missed real defect and so "earns the top tier."

## Why it changed

1. **Sonnet 5 closed the gap.** Anthropic reports Sonnet 5 landing near
   Opus 4.8 on performance, including the kind of reasoning these agents do.
   The top tier no longer buys enough marginal defect-catching to justify its
   cost on review work.
   Blog post: https://www.anthropic.com/news/claude-sonnet-5

2. **A single review was burning a whole Opus session.** The deep agents on an
   Opus session ran on Opus, and #2 (bugs) is **batched** — a large PR fans it
   out to one instance per file-batch. So a big diff spun up several Opus
   instances in one review. That was the concrete pain that triggered this.
   (Example that motivated it: a review on a ~40-file private-repo PR hit the
   session limit hard.)

## The rule and its shape

- The pin is a **ceiling, not a floor.** On an Opus session it pins the deep
  agents *down* to Sonnet 5 (the savings). On a Haiku session it pins them
  *up* to Sonnet 5 (deep reasoning still gets a capable model). Only if you
  deliberately want the *whole* review on Haiku would you drop the pins.

- **#2 stays pinned regardless.** It's the only deep agent that's batched, so
  its fan-out is what actually multiplies cost on a big diff. Unpinning it would
  reintroduce the exact problem this decision fixed.

- **If review quality ever slips**, unpin **#5 (security)** or **#7
  (structural)** first — they're single calls per run, so putting Opus back on
  them is cheap. Do not unpin #2.

## How to verify a regression before reverting

Don't revert on vibes. The eval harness under `evals/` (esp.
`evals/intent-recon.py` for #9, and the omission fixtures) measures
defect-catching per agent. Run it on Sonnet 5 vs Opus for the agent in question
and compare caught-defect counts before changing a pin back.
