# Review agents #1–#6: style default and focus briefs

Read this at Step 5, before spawning the fan-out. Every agent gets the style default verbatim
plus its own focus. Gates for the conditional agents #7/#8/#9 stay in SKILL.md; their focus is
in `conditional-agents.md`.

**Style default (pass to every review agent):**

> The user prefers an immutable style as the default: `const` over `let`-reassignment, expression forms (`??`/`||` short-circuit chains, ternaries, `map`/`filter`/`reduce`) over accumulate-and-mutate flows. Flag diff-introduced mutable patterns ONLY when they collapse cleanly into an immutable form with identical behavior. Do NOT flag mutability that is clearly more readable (deep nesting to avoid it, unwieldy expression) or measurably faster (hot loops, large-array copies) — those are the legitimate exceptions, not violations.

### Agent #1 — Standards compliance `[model: sonnet]` · file-scoped, whole-file, batched
- You receive the whole changed file(s) in your batch plus the diff of what changed.
- List all relevant `CLAUDE.md` files (root + every directory touched by the batch)
- Read them
- Flag changes that violate stated guidance. Skip guidance that's clearly only for code-writing, not code review.

**Baseline (applies even when the repo documents nothing).** Documented guidance always wins: where a `CLAUDE.md` endorses something the baseline would flag, suppress it. Both of these are labelled heuristics — report them as "possible Duplicated Code", never as violations — and the Dismissed list overrides them like anything else. Skip whatever tooling already enforces. **Baseline findings are always routed to ask-user and never auto-applied**, whatever they score — a rename or an extraction driven by a heuristic is a proposal, the same call Agent #7 gets. Documented-guidance findings are unaffected and score normally.

- **Mysterious Name** — a function, variable, or type introduced by the diff whose name doesn't reveal what it does or holds. → propose a rename; if no honest name exists, say so, because that usually means the design is murky rather than the name.
- **Duplicated Code** — the same logic *shape* appears more than once within this batch. → propose extracting it and calling from both sites. Require a real shape match: two functions that merely rhyme are not duplication, and premature extraction is its own smell. Do not flag test setup, fixtures, or table-driven cases, where repetition is usually the point.

Only these two. The wider Fowler catalogue is deliberately out of scope here: the structural smells (Speculative Generality, Repeated Switches, Shotgun Surgery, Divergent Change, Middle Man) belong to Agent #7, and the object-shaped ones (Feature Envy, Data Clumps, Message Chains, Refused Bequest) assume method-heavy classes and inheritance that this setup's style default steers away from.

### Agent #2 — Bug scan `[model: sonnet]` · file-scoped, whole-file, batched
- You receive the **whole changed file(s)** in your batch plus the diff of what changed. Review the changed behavior, using the full file for context — do not limit yourself to the added lines.
- **Commission bugs** (a mistake in code that *is* there): off-by-ones, null/undefined access, async race conditions, wrong loop bounds, copy-paste errors, mutation-of-arguments, missing returns, incorrect error handling.
- **Omission bugs** (behavior the code *should* have but doesn't) — read the whole file and ask what's missing on the changed path: state that should be reset/invalidated when inputs change but isn't, a documented contract left unenforced, an error/failure path that logs instead of throwing or paging, a flag set before the action it's meant to gate, a case handled elsewhere in the file that this path forgets. These are invisible in a diff-of-additions and are this agent's most common miss — weight them, and use the full-file context you're given to catch them.
- Ignore false-positive-prone categories: linter/typechecker territory (the Step 4a static-analysis pass owns this), formatting, missing imports

### Agent #3 — Git history `[model: sonnet]`
- For each significantly-modified region, run `git log -p -L <range>:<file>` or `git blame` on the original lines
- Flag changes that revert past intentional fixes (look for "fix" / "revert" / issue refs in the history)
- Flag changes that ignore conditions that prior commits added on purpose

### Agent #4 — Code comments compliance `[model: sonnet]` · file-scoped, whole-file, batched
- You receive the whole changed file(s) in your batch plus the diff of what changed.
- For each changed file, read existing comments (in-line, doc comments, header)
- Flag changes that violate explicit guidance in comments (e.g. "// must stay alphabetized", "# do not call from main thread")

### Agent #5 — Security — **superseded**
Replaced by the two-stage security review in **`references/security-review.md`** (Anthropic's
vendored `/security-review` prompt + the per-repo threat model). It is not spawned from this
roster and takes none of the briefs here — not even the style default. Findings bypass Haiku
scoring; its own Stage-2 filter scores them.

### Agent #6 — Test coverage `[model: sonnet]`
- Identify substantive logic changes (not pure refactors, not formatting)
- Check whether tests in the diff cover them
- Flag uncovered logic only when the change is non-trivial and the project clearly has a test suite. Skip if the repo has no tests at all.

