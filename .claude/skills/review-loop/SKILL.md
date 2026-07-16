---
name: review-loop
description: "Pre-push Claude-driven code review loop with auto-fix. Runs up to 8 parallel review agents (CLAUDE.md, bugs, git history, code comments, security, test coverage, and — on substantial diffs — structural simplification and observability coverage) per cycle, scores each finding 0-100 with an independent Haiku rater, auto-fixes ≥80 findings, asks about 50-79 in a single batch per cycle, and stores per-repo learnings in .git/info/. Each cycle first runs the static-analysis skill (a deterministic linter/security/secret tool pass with autofix) so the LLM agents can focus on what tools can't catch. On clean exit, a final manual-testing evidence gate verifies the PR carries proof the changed functionality actually works — and produces that proof itself (local dev servers + playwright + surge-image-upload) when missing. Replaces CodeRabbit for local review. Invoke this proactively and by default before any push and whenever finishing or cleaning up a chunk of code changes — do not ask the user for permission first and do not look for reasons to skip it. Prefer running it over not running it."
---

You are an expert code reviewer running a multi-cycle, multi-agent review-fix-commit loop on the current branch. Your job is to deliver CodeRabbit-equivalent (or better) review depth using Claude subagents, apply high-confidence fixes automatically, batch ambiguous fixes for user approval, and accumulate per-repo learnings over time.

## Detecting Workspace Type

Before starting, check the current git branch:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → use GitButler commands (`but status`, `but rub <file> <branch>`, `but commit <branch> -m "..."`)
- Otherwise → use standard git commands

## Step 1: Determine Base Branch

Try these in order; use the first that returns a value:

```bash
# 1. PR base (if a PR exists for this branch)
base_branch=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)

# 2. Repo default branch via gh
[ -z "$base_branch" ] && base_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)

# 3. origin/HEAD symbolic ref
[ -z "$base_branch" ] && base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
```

If all three fail, ask the user to specify a base branch (e.g. `main` or `master`).

Then fetch the latest from origin so the review compares against current remote state:

```bash
git fetch origin "$base_branch"
```

The scope of the review is everything on the current branch that isn't on `origin/<base_branch>` — i.e. committed changes only. If the user has uncommitted work they want reviewed, tell them to commit it first before re-invoking.

## Step 2: Load Per-Repo Learnings

```bash
learnings_file=".git/info/review-loop-learnings.md"
[ -f "$learnings_file" ] && cat "$learnings_file"
```

If the file exists, hold its contents in mind for the entire session — pass them to every review agent in Step 5. The file has two sections:

- **Dismissed**: findings the user has explicitly said are not worth flagging in this repo
- **Accepted patterns**: types of issues the user has explicitly confirmed matter in this repo

If the file does not exist, that's fine — start with no learnings.

## Step 3: Detect Test & Lint Commands

The broad analyzer set (linters, security, secrets) is handled deterministically by the static-analysis pass (Step 4a) — you don't need to detect per-tool commands for it. What you're detecting here is the **test** command and any **project-specific** lint/format/typecheck script (Prettier, `tsc`, a custom `npm run lint`) that static-analysis doesn't replicate and that runs alongside it.

Search for project-standard test and lint commands. Check (in this order):

1. Root `CLAUDE.md` — look for explicit "test command" / "lint command" instructions
2. `package.json` `scripts` — `test`, `lint` (note if `lint` supports `--fix` or a `lint:fix` script exists)
3. `Makefile` — `test`, `lint` targets
4. Language-specific configs: `pytest.ini` / `pyproject.toml` → `pytest`; `ruff.toml` / `.ruff.toml` → `ruff check --fix`; `.eslintrc*` → `eslint --fix`; `.rubocop.yml` → `rubocop -A`; `Cargo.toml` → `cargo clippy --fix` and `cargo test`
5. CI config (`.github/workflows/*.yml`) as a last-resort hint

Record what you found. If no test command can be detected, warn the user once at the start: "No test command detected — fix-induced regressions won't be caught between cycles." Same for lint.

## Step 4: Main Loop

```
cycle = 1
max_cycles = 3

while cycle <= max_cycles:
    a. Run the static-analysis pass (Step 4a below): the static-analysis skill (--diff --fix) plus the project linter --fix if detected. Stage what changed; collect the deterministic tool findings.
    b. Run 6 parallel review subagents (Step 5). Each returns findings + suggested fixes.
    c. For each finding, spawn a Haiku scorer subagent (Step 6). Score 0-100.
    d. Bucket by score AND risk profile (Step 8a):
       - structural (Agent #7), any score → ask-user (never auto-apply)
       - ≥80                              → auto-fix
       - 50-79 + low-risk                 → auto-fix (no ask)
       - 50-79 + high-risk                → ask-user
       - <50                              → skip
    e. If auto-fix bucket is empty AND the static-analysis pass made no changes and surfaced no unresolved security/secret/SAST findings → EXIT LOOP (clean).
    f. Apply auto-fix bucket via Edit (Step 7).
    g. If ask-user bucket is non-empty, batch them into one AskUserQuestion (Step 8b). Apply approved fixes.
    h. If test command detected, run tests (Step 9). On failure → STOP LOOP, report.
    i. Commit this cycle's changes (Step 10).
    j. Append captured learnings to .git/info/review-loop-learnings.md (Step 11), deduping against existing entries.
    k. cycle += 1

If cycle > max_cycles:
    Report: "Reached cycle limit (3). Remaining findings below."
```

On a clean loop exit, run the manual-testing evidence gate (Step 13) before the final report/auto-push (Step 14). If the gate's testing uncovers a real issue, fix + commit + restart the loop from cycle 1 (see Step 13c).

## Step 4a: Static-analysis pass (deterministic tools)

Loop step (a). Runs at the top of every cycle, before the review agents. This is the deterministic counterpart to the LLM review — the review agents (Step 5) deliberately ignore linter/typechecker territory because this pass owns it.

**1. Run the static-analysis skill, scoped to the diff, with autofix:**

```bash
python3 ~/.claude/skills/static-analysis/static-analysis.py . --diff --fix --exit-zero
```

It detects the repo's languages/configs and runs the curated analyzer set (ESLint/Biome/oxlint, Ruff, RuboCop, Stylelint, golangci-lint, govulncheck, gitleaks, Semgrep, actionlint, zizmor, markdownlint, hadolint, shellcheck, …), applies safe autofixers, and writes `.static-analysis/summary.json` + `report.md` (git-ignored — never appears in the diff). Stage whatever the autofixers changed.

**2. Then run the project linter --fix if one was detected** (Step 3) — it catches formatting (Prettier), type-checking (tsc), and custom lint rules the analyzer set doesn't replicate. Stage those changes too.

**3. Read `.static-analysis/summary.json` and fold the *remaining* (non-autofixed) findings into the cycle:**

- **Security / secrets / SAST** — findings from `gitleaks`, `semgrep`, `brakeman`, `govulncheck`, `zizmor`: treat each as a high-confidence (≥80) finding. **Do not Haiku-score them** — the tool already verified them. Attempt a fix and route through Step 7 / Step 8a exactly like a review-agent finding (the risk profile still decides auto-apply vs. ask). These are the ones that matter.
- **Quality / style residue** — anything the autofixers couldn't fix: don't run it through the agents or Haiku (deterministic, mostly low-value). Carry the per-tool counts into the final report (Step 14).
- **Skipped tools** — if the run skipped analyzers (not installed, no ephemeral runner) and you can prompt the user (main interactive agent, not a headless subagent), offer once to install them (use each entry's `install_hint`) and re-run. In a subagent run, just note the skips in the report; never block.

## Step 5: Parallel Review Agents

Spawn the review subagents in parallel (single message, multiple Agent tool calls). Agents #1–#6 always run. Agents #7 (structural simplification) and #8 (observability coverage) run **only on substantial diffs** — see each agent's gating rule. Each agent must receive:

- The diff: `git diff origin/<base_branch>...HEAD`
- The contents of `.git/info/review-loop-learnings.md` if it exists, with instructions: "If a finding matches anything in the Dismissed list, do not flag it."
- The agent's specific focus (one of the six below)
- The style default below (verbatim)
- A required output shape: a JSON-like list of `{file, line_range, description, suggested_fix, reasoning}`

**Style default (pass to every review agent):**

> The user prefers an immutable style as the default: `const` over `let`-reassignment, expression forms (`??`/`||` short-circuit chains, ternaries, `map`/`filter`/`reduce`) over accumulate-and-mutate flows. Flag diff-introduced mutable patterns ONLY when they collapse cleanly into an immutable form with identical behavior. Do NOT flag mutability that is clearly more readable (deep nesting to avoid it, unwieldy expression) or measurably faster (hot loops, large-array copies) — those are the legitimate exceptions, not violations.

### Agent #1 — CLAUDE.md compliance
- List all relevant `CLAUDE.md` files (root + every directory touched by the diff)
- Read them
- Flag changes that violate stated guidance. Skip guidance that's clearly only for code-writing, not code review.

### Agent #2 — Bug scan
- Read only the diff (don't pull in extra context)
- Look for obvious correctness bugs: off-by-ones, null/undefined access, async race conditions, wrong loop bounds, copy-paste errors, mutation-of-arguments, missing returns, incorrect error handling
- Ignore false-positive-prone categories: linter/typechecker territory (the Step 4a static-analysis pass owns this), formatting, missing imports

### Agent #3 — Git history
- For each significantly-modified region, run `git log -p -L <range>:<file>` or `git blame` on the original lines
- Flag changes that revert past intentional fixes (look for "fix" / "revert" / issue refs in the history)
- Flag changes that ignore conditions that prior commits added on purpose

### Agent #4 — Code comments compliance
- For each modified file, read existing comments (in-line, doc comments, header)
- Flag changes that violate explicit guidance in comments (e.g. "// must stay alphabetized", "# do not call from main thread")

### Agent #5 — Security
- Look for: injection risks (SQL, command, template), hardcoded secrets/keys/tokens, missing auth checks on routes/handlers, unsafe deserialization (pickle, eval, yaml.load), path traversal, missing CSRF/CORS where relevant, broken access control
- Be specific about the vulnerability class and how an attacker triggers it

### Agent #6 — Test coverage
- Identify substantive logic changes (not pure refactors, not formatting)
- Check whether tests in the diff cover them
- Flag uncovered logic only when the change is non-trivial and the project clearly has a test suite. Skip if the repo has no tests at all.

### Agent #7 — Structural simplification (conditional)

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

For each finding, the `suggested_fix` should describe the restructuring in plain language and name what it deletes ("collapse the three `status` string checks into a `Status` union; the `isPending`/`isDone` helpers then disappear"). These are **proposals, not patches** — do not expect them to be auto-applied (see Step 6 and Step 8a routing).

### Agent #8 — Observability coverage (conditional)

**Gating — only spawn this agent when BOTH hold:** the diff is substantial/risky (same threshold as Agent #7), AND the repo already has an observability convention — a logger, metrics client, or error reporter visible in the surrounding files. **Skip entirely** if the project logs nothing; don't invent a convention where none exists. As with #7, when in doubt on a borderline diff, spawn it.

This is the mirror of Agent #6 (test coverage): #6 asks "does changed logic have tests?"; #8 asks "if changed logic fails in prod, will we find out?"

Like #7, this agent is **allowed and expected to read beyond the diff** — observability is often satisfied upstream or downstream of the changed line. Confirm a failure path is *actually* unsurfaced, not merely out of frame, before flagging.

1. Enumerate the **failure-bearing** behaviors the diff adds or changes: external I/O (network, DB, API, filesystem), error-handling paths, async / background / queue work that can partially fail, money / auth / security paths, and fallible state mutations. **Ignore** pure in-memory logic, renames, refactors, and UI-only changes — they are not this agent's business.
2. For each, check whether a failure would be **detectable**: is there a log, metric, error report, or surfaced error on the failure path?
3. Flag only failure-bearing changes where a silent failure would matter and nothing surfaces it. Also flag observability the diff **removed or downgraded** on such a path (a deleted log line, an error report dropped, a log level lowered on a failure path). State the symptom concretely: "if this charge fails, the user sees nothing and no log/metric fires — first signal is a support ticket."

Findings here are verifiable (the failure path either surfaces something or it doesn't), so they use the **normal Step 6 rubric** — no special-casing like #7. The fixes are almost always additive (add a log line / metric / error surface), which makes them low-risk under Step 8a and so usually auto-applied.

## Step 6: Haiku Scoring

For each finding from Step 5, spawn a Haiku subagent (in parallel where possible) with:

- The original diff
- The relevant `CLAUDE.md` paths
- The finding (`{file, line_range, description, reasoning}`)
- The learnings file contents
- This rubric (verbatim):

> Score this finding 0-100 for confidence that it is a real, actionable issue in this PR.
>
> - **0**: Not confident at all. False positive that doesn't survive light scrutiny, or pre-existing issue not touched by this diff.
> - **25**: Somewhat confident. Might be real, might not. Couldn't verify.
> - **50**: Moderately confident. Real issue, but a nitpick or rare in practice.
> - **75**: Highly confident. Verified real, likely to bite in practice. Important to functionality, or directly named in CLAUDE.md.
> - **100**: Absolutely certain. Verified, will hit frequently, evidence is direct.
>
> If this finding matches anything in the learnings file's Dismissed section, score 0.
> If it matches an Accepted pattern, raise your score by 10 (cap at 100).
>
> Return only an integer.

**Structural findings (Agent #7) score differently.** The rubric above is for verifiable defects; a simplification is subjective and will never be "verified true," so it would score low and get filtered out unfairly. For Agent #7 findings, score on *value vs. risk* instead: how much complexity the restructuring deletes (a whole layer/branch disappearing scores high; a cosmetic tidy scores low) balanced against how invasive the refactor is. Regardless of the resulting score, structural findings are **always routed to ask-user** (Step 8a) and are never auto-applied — the score only sets their ordering and whether they're surfaced as a blocker vs. a nit in the final report (Step 14).

## Step 7: Apply Auto-Fixes (≥80)

For each ≥80 finding, in dependency order (same file → process top-to-bottom by line number to keep line refs valid):

1. Read the file
2. Apply the `suggested_fix` via Edit
3. If the suggested_fix is unclear or conflicts with current state, drop the finding to the 50-79 bucket so the user is asked

## Step 8a: Risk profile — decide which 50-79 findings need a human

A 50-79 confidence score means *you* aren't sure, not necessarily that the *user's* input is required. Cheap-to-undo, low-blast-radius fixes don't deserve an interruption — just apply them and let the user override later if they object.

Before asking, classify each 50-79 finding on three dimensions. A finding goes to **auto-fix** when ALL of the following are low-risk; otherwise it goes to **ask-user**.

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

When auto-applying a 50-79 finding without asking, note it in the cycle commit message (`fix(review): cycle N — ... (auto-applied low-risk: <one-line summary of each>)`) so the user sees what landed without their say-so.

If after Step 8a the ask-user bucket is empty, skip Step 8b entirely.

## Step 8b: Batched approval for the remaining (high-risk) 50-79 findings

After auto-fixes are applied, present the remaining 50-79 findings as one AskUserQuestion (or sequential if there are more than 4 — AskUserQuestion caps at 4 options per call, so use multiple calls if needed). For each:

- Option "Apply fix" — apply the suggested fix
- Option "Skip" — record as a dismissal in learnings
- Option "Skip and remember as a dismissal pattern" — record with broader pattern wording

Apply approved fixes the same way as Step 7.

### Framing the question for non-expert readers

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

## Step 9: Test Run

Run the detected test command. Stream output. If exit code is non-zero:

1. Stop the loop immediately
2. Report the failing tests with their output
3. Tell the user: "Tests failed after this cycle's fixes. Last commit is `<sha>`. Investigate, fix, and re-invoke."
4. Do not auto-revert — let the user decide whether to revert or fix forward

## Step 10: Commit the Cycle

Stage all files changed this cycle (lint --fix changes + auto-fixes + user-approved fixes) and commit with a conventional commit message summarizing the cycle:

**Standard git:**
```bash
git add <changed-files>
git commit -m "fix(review): cycle <N> — <short summary of categories addressed>"
```

**GitButler workspace:**
```bash
but rub <file> <branch>
but commit <branch> -m "fix(review): cycle <N> — <short summary>"
```

Summary should mention the agent categories whose findings drove the cycle (e.g. "security + bug scan + CLAUDE.md").

## Step 11: Capture Learnings

The learnings file is loaded into every future cycle's agent prompts, so its size and quality directly affect downstream cost and signal. Treat it as a curated index, not an append-only log.

### File

`.git/info/review-loop-learnings.md`. Create with this structure if it doesn't exist:

```markdown
# Review Loop Learnings

## Dismissed
<!-- Patterns the user has chosen to skip. Skill won't auto-flag matches. -->

## Accepted patterns
<!-- Patterns the user has explicitly confirmed matter here. Skill weights matches higher. -->
```

### Writing rules

**Entry shape** — one line, ~150 chars max. Lead with the date and either the literal token `PATTERN:` (for a broad, reusable rule) or a concrete one-off. PATTERN entries are the goal — they survive over time; one-off entries are pruned first.

**Before adding a new entry, dedup.** Read the file. If a similar entry already exists:

- **Same topic, same direction** (e.g. "don't flag X in this repo" already covers what you'd write) → do nothing. Just refresh the date on the existing entry if you want to mark it as still active.
- **Same topic, narrower scope** (your new entry is a specific instance of an existing PATTERN) → don't add it. The PATTERN already covers it.
- **Same topic, broader scope** (your new entry generalises 2+ existing entries) → replace the narrower entries with one PATTERN entry. Note the consolidation date.
- **Different topic** → add a new entry.

**Promote on repetition.** If you've added three or more narrow entries that share a theme, replace them with one PATTERN entry that captures the rule. Don't let the file accumulate near-duplicates.

**Cap at ~50 entries.** When exceeded, prune in this order:
1. Oldest non-PATTERN dismissed entries (the specific one-off skips).
2. Oldest non-PATTERN accepted entries.
3. PATTERN entries last, and only if redundant with a newer one.

**If the file passes ~75 entries even after pruning**, that's a signal the repo's review tastes are heterogeneous enough to need topic splits. At that point (not before), split into a `.git/info/review-loop-learnings/` directory with topic files (`comments.md`, `tests.md`, `refactor.md`, …) and concatenate them when loading. Don't pre-split — single file is simpler when the volume is small.

### What to write for each Step 8b outcome

- "Skip" → Dismissed entry: `- <date>: <finding description> (file: <path>, fix declined)`
- "Skip and remember as a dismissal pattern" → Dismissed entry: `- <date>: PATTERN: <user-worded pattern>`
- "Apply fix" → Accepted entry: `- <date>: <finding description> (accepted)`

Auto-applied low-risk 50-79 findings (from Step 8a) do NOT write to learnings — they're tactical and would just be noise.

When in doubt about whether an entry is worth writing, err on the side of NOT writing. The file's value is in being scannable, not exhaustive.

## Step 12: "Remember X" Requests During the Session

If the user says "remember X", "always check Y here", "this repo cares about Z", or similar at any point during the session, immediately append to `.git/info/review-loop-learnings.md` under the appropriate section (Dismissed for "stop flagging…", Accepted for "always flag…"). Acknowledge with one sentence. Do not derail the loop.

If the user explicitly says "remember globally" or "remember for all repos", offer to also write to `~/.claude/projects/-home-narthur/memory/` as a separate auto-memory entry.

## Step 13: Manual-Testing Evidence Gate

Runs **only after everything else passes** — a clean loop exit (auto-fix bucket empty, tests green, no unresolved high-risk findings). It is the last gate before Step 14's report/auto-push.

**Skip entirely** (say so in one line in the final report) when either:

- **No PR exists** for the branch (`gh pr view` fails) — there's nowhere to check or attach evidence.
- **The diff changes no runtime functionality** — docs, comments, config, dependency bumps, CI-only changes, or pure refactors already pinned by tests. The gate is about *changed behavior*, and when in doubt, run it.

### 13a: Check the PR for existing evidence

Read the PR body and comments:

```bash
gh pr view --json body,comments
```

**Sufficient evidence** = artifacts demonstrating this PR's changed functionality actually working: screenshots/recordings of the changed UI states, command transcripts with real output (curl against a dev server, CLI invocations), or test-session notes with concrete inputs and observed outputs. A bare claim ("tested locally ✅") is **not** sufficient, and evidence must cover the *changes in this PR*, not the app generally. Evidence found → gate passes; go to Step 14.

### 13b: Do the manual testing yourself

No sufficient evidence → produce it:

1. Stand up whatever the changes need locally, per repo convention (check CLAUDE.md / package.json scripts — e.g. `pnpm dev`; seed env/data as the repo's docs describe).
2. Exercise **each functional change the PR makes** — not a generic smoke test:
   - UI changes → the **playwright** skill: drive the changed flows and `playwright-cli screenshot` at the states that prove the new behavior.
   - API/CLI changes → real requests/invocations; capture the command and the actual response verbatim.
3. Save evidence as you go — screenshots to the scratchpad, transcripts verbatim.

### 13c: Outcome

**Everything works** → publish the evidence to the PR:

1. Images → public URLs via the **surge-image-upload** skill: `~/.claude/skills/surge-image-upload/upload.sh <files>`.
2. Post one PR comment (`gh pr comment`) with a `## Manual testing evidence` section: what was tested and how, embedded screenshots, transcripts in fenced blocks, and the environment (local dev, commit SHA tested).
3. Gate passes → Step 14.

**Testing finds a real issue** (broken behavior, error, regression):

1. **Stop the review immediately** — post no evidence, push nothing.
2. Fix the issue and commit it (`fix(<scope>): <description>`).
3. **Restart the loop from Step 4, cycle 1** — the fix is new, unreviewed code and goes through the full review before the gate runs again.
4. Cap gate-triggered restarts at **2 per invocation**. At the cap, stop, report the unresolved issues, and don't auto-push.

**Can't test** (required secret/service unavailable, dev environment broken) → don't fake or hand-wave it: treat the gate as **not passed**, skip the auto-push, and report exactly what was attempted, what blocked it, and what the user needs to provide.

## Step 14: Final Report and Auto-Push

### When to auto-push

If the loop exits **clean** (auto-fix bucket empty, no test failures, no skipped high-risk findings) **and the Step 13 gate passed or was skipped**, push automatically:

- **Standard git:** `git push`
- **GitButler workspace:** `but push <branch-name>`

If the push fails (network error, branch protection, missing upstream, non-fast-forward), surface the error verbatim in the final report and continue — don't retry, don't force.

### When NOT to auto-push

- **Tests failed mid-loop** (Step 9 short-circuit). The branch is in a known-broken state; don't propagate.
- **Cycle limit reached with unaddressed ≥80 findings.** The loop didn't converge.
- **The user explicitly skipped a 50-79 finding without "remember as dismissal pattern".** That's an unresolved ambiguity the user might still want to think about; let them push when ready.
- **No upstream configured for the branch.** Don't infer one; report and stop.
- **Branch is the repo's default branch (main/master).** Never auto-push to main; surface the unusual state instead.
- **The Step 13 evidence gate is blocked or hit its restart cap.** Untested (or known-broken) functionality doesn't get pushed on your say-so.

When skipping the auto-push, end the report with `Next step: <reason>; push when ready.` Don't pretend it was a clean exit.

### Report format

```
review-loop complete: <N> cycle(s), <M> commits, pushed: <yes|no — reason>.
Evidence gate: <passed — existing evidence | passed — evidence captured & posted (link) | skipped — <no PR | no functional changes> | blocked — <reason>>.

Cycle 1: <summary>
Cycle 2: <summary>
...

Structural proposals (Agent #7 — not applied, your call):
- Blockers: <high-value simplifications that delete a layer/branch, or file-size breaches — the things worth doing before this merges>
- Nits: <smaller tidy-ups, listed briefly>
(Omit this section entirely if Agent #7 didn't run or found nothing.)

Auto-applied low-risk 50-79 (no ask):
- <list with one-line summary each — visible to the user since they didn't see the ask>

Static-analysis (Step 4a): autofixed <count>; security/secret/SAST findings <resolved/surfaced>; quality residue by tool: <tool=N, …>; skipped tools: <list or none>.

Remaining 50-79 findings the user skipped or didn't address:
- <list>

Remaining <50 findings (low confidence, not surfaced):
- <count only, not detail>
```

## Quick Reference

| Operation | Standard Git | GitButler |
| --- | --- | --- |
| Status | `git status` | `but status` |
| Stage | `git add <file>` | `but rub <file> <branch>` |
| Commit | `git commit -m "..."` | `but commit <branch> -m "..."` |
| Push (user-initiated) | `git push` | `but push <branch>` |

| Bucket | Score | Risk profile (Step 8a) | Action |
| --- | --- | --- | --- |
| Ask user | (any) | structural finding from Agent #7 | Surface as proposal; never auto-apply |
| Auto-fix | ≥80 | (any) | Apply silently |
| Auto-fix | 50-79 | all three dimensions low-risk | Apply silently; note in commit message |
| Ask user | 50-79 | any dimension high-risk OR fix unclear OR `always ask` rule applies | Batch via AskUserQuestion |
| Skip | <50 | (any) | Reported in final summary count only |
