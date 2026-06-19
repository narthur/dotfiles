# Bitter-Lesson Audit Criteria

The governing idea (Richard Sutton's Bitter Lesson, applied to personal scaffolding):
**as the model and harness get smarter, the specific ways you told them to do things get
dumber.** Scaffolding is a depreciating asset. Every skill, hook, and setting is a
standing liability — context cost, a maintenance burden, and a place for stale assumptions
to hide. The default verdict is therefore *suspicion*, and the bias is toward **deleting and
simplifying**, not preserving.

But not everything is depreciating. Scaffolding that encodes **private, non-inferable
knowledge** (your credentials, your project specifics, your idiosyncratic preferences,
hard-won correctness lessons) is exactly what the model *can't* derive on its own and should
be kept. The audit is the act of separating the two.

## Verdicts

Assign each skill/hook one verdict plus a one-line rationale and a confidence (high/med/low):

- **DELETE** — the harness or model now does this natively, OR it's unused, OR it duplicates
  another skill. Net liability.
- **SIMPLIFY** — still useful, but over-engineered: too much hot-path prose, scripts that
  reimplement now-native tools, step-by-step procedures the model would now infer. Hand to
  the `refine-skill` skill.
- **FIX** — useful and correctly scoped, but contains stale facts: dead API flags, renamed
  files, removed commands, wrong model IDs/prices. Correct it (don't hedge).
- **MERGE** — overlaps materially with another skill; fold them.
- **KEEP** — earns its place. Encodes private knowledge or hard-won correctness. Leave alone.

## DELETE heuristics (the core of the bitter-lesson pass)

A skill is a DELETE candidate when a native capability has caught up. Check each against the
current capability baseline in `native-capabilities.md`:

- Reimplements a tool the harness now ships (custom web search vs native WebSearch/WebFetch;
  custom fan-out vs the Agent tool / Workflow; a bespoke scheduler vs `/loop` & `/schedule`;
  manual planning ritual vs Plan mode).
- Spells out a procedure the model now reliably does unprompted (e.g. "how to write a good
  commit message", "how to read a stack trace"). If the SKILL.md is mostly generic best
  practice with no private specifics, it's scaffolding the model has outgrown.
- **Unused.** No evidence of invocation in memory, Fieldnotes, or recent transcripts, and the
  user doesn't recognize needing it. Dead weight.
- Duplicate / superseded (e.g. a v1 left behind after a v2; note the existing
  `coderabbit-review-loop` → `review-loop` supersession already documented in its own
  description).

## SIMPLIFY heuristics

- SKILL.md is long (rough flag: >200 lines) AND much of it is situational — move to
  `references/`. Every line in SKILL.md loads on every invocation.
- Inline command sequences always run the same way — extract to a script.
- A script reimplements something now native — replace the script call with the native tool.
- Defensive hedging ("you might want to consider possibly…") — make it direct or cut it.

## What protects a skill from deletion (KEEP)

- **Credentials / connection details** the model can't know (DB DSNs, API endpoints, account
  IDs, org-specific config).
- **Idiosyncratic preference** — your conventions, not the model's defaults (e.g. caveman
  mode, your CRM format, your Fieldnotes conventions).
- **Hard-won correctness** — guardrails that exist because something broke. These are the
  *opposite* of bitter-lesson rot: they're institutional memory. Examples in this setup:
  `review-loop`, the egress-guard hook, the CodeRabbit one-review-per-PR learning. **Never
  delete these without explicit user confirmation**, even if they look like "the model could
  do this now."
- **Vendor doc bundles** (the `render-*` and `cloudflare*` plugin skills) — these are an
  installed plugin set, not your scaffolding. Out of scope; don't propose changes.

## Confidence calibration

- Be willing to recommend deletion at *medium* confidence — the user approves before anything
  is deleted, so a wrong-but-flagged candidate costs only a moment of their attention.
- But surface uncertainty honestly. Don't present a low-confidence guess as a clear win.
- If you bounded the audit (sampled, skipped a category), say so — silent truncation reads as
  "I reviewed everything" when you didn't.
