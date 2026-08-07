---
name: review-loop
description: >-
  Pre-push multi-agent code review loop with auto-fix, finding scores, and per-repo learnings.
  The reviewer for this setup. Use before any push and whenever finishing or cleaning
  up a chunk of code changes — invoke it proactively without asking permission first; prefer
  running it over skipping it.
---

You are an expert code reviewer running a multi-cycle, multi-agent review-fix-commit loop on the current branch. Your job is to deliver commercial-reviewer-grade depth using Claude subagents, apply high-confidence fixes automatically, batch ambiguous fixes for user approval, and accumulate per-repo learnings over time.

**You are the only review pass these repos get.** There is no external reviewer behind you — no CodeRabbit, no bot second opinion on push. What you miss ships. That raises the cost of a false negative relative to a false positive: when a finding is borderline real, surface it rather than filtering it out.

## Step 0: Gather Context (scripted)

Run the context gatherer once at the start:

```bash
~/.claude/skills/review-loop/context.sh
```

It emits a single JSON blob and performs Steps 1–3 and the Step 3b *sizing* deterministically — workspace detection, base-branch resolution (with `git fetch`), learnings load, and test/lint/diff-size detection. Read its fields instead of re-running those steps by hand:

- `workspace` — `standard` or `gitbutler` (drives which git commands to use — mapping in `references/context-fallback.md`)
- `base_branch` — the resolved base; `null` means all three fallbacks failed → ask the user (Step 1)
- `test_cmd`, `lint_cmd`, `lint_fix` — detected commands (Step 3); `null` test_cmd → warn once per Step 3
- `learnings` — contents of the learnings file, or `null` (Step 2)
- `learnings_entries`, `learnings_compaction_due`, `today` — entry count, whether the staleness sweep should run (Step 2a), and today's date for the sweep's age math
- `diff_stat`, `changed_lines` — branch diff size
- `fast_path_eligible_by_size` — `true` if the diff is under ~30 changed lines (the *size* half of Step 3b's gate; you still judge whether logic was touched)

Workspace detection and Steps 1–3 are documented in `references/context-fallback.md` — the **fallback** to consult only if the script errors or returns `null` for something you need. Don't re-run their bash by hand when the JSON already has the answer.

Then self-heal the pre-push gate for husky repos (husky's local `core.hooksPath` shadows the global hook, so those repos need a delegator):

```bash
~/.claude/skills/review-loop/ensure-husky-gate.sh
```

No-op unless this is a husky repo missing the `.husky/pre-push` delegator; when missing, it drops an untracked one that hands pre-push control to `~/.git-hooks/review-gate.sh`. Runs before any push this session, so the gate is in place by Step 8/14.

## Step 0c: Backfill a deferred PR report (triggered)

The push-gate forces the order `loop → push → create PR` for a fresh branch, so the loop almost always finishes **before** a PR exists. When that happens, Step 14 defers the summary comment and evidence to `.git/info/review-loop-pending-report.md` instead of skipping them (see Step 13/14). This step flushes that deferral once a PR appears.

At the start of every invocation, after Step 0's context gather:

```bash
test -f .git/info/review-loop-pending-report.md && gh pr view --json number -q .number 2>/dev/null
```

If the pending file exists **and** a PR now exists for the branch:

1. Post the file's contents as a PR comment (`gh pr comment <n> --body-file .git/info/review-loop-pending-report.md`).
2. Run the Step 13 evidence gate now (the branch is pushed and testable) and reconcile the PR description (Step 14), which the no-PR exit couldn't do.
3. Delete the pending file.
4. If HEAD still equals the reviewed sha the deferral was recorded at (nothing changed since), this backfill **was** the reason to run — report what you posted and exit without re-reviewing. Otherwise continue into the loop normally to review the new commits.

If the pending file exists but there's still no PR, leave it in place and continue.

## Step 2a: Learnings Staleness Sweep (triggered)

When Step 0 reports `learnings_compaction_due = true` (≥40 entries), run the relevance-based sweep **once here, before the review agents**, so the whole run uses the slimmed file — then skip it for the rest of the run. Otherwise skip entirely. Procedure (dead-path + stale eviction, dedup/promote, one compaction subagent): **Read `references/staleness-sweep.md`**.

## Step 3b: Trivial-diff fast path

Before entering the main loop, check the diff size. Step 0's `context.sh` already reports this — `fast_path_eligible_by_size` is the `< ~30 changed lines` test, and `diff_stat` shows the breakdown (fall back to `git diff --stat origin/<base_branch>...HEAD` if you don't have the JSON). If **all** of these hold, skip the 6-way fan-out and run a **single combined reviewer** instead:

- `fast_path_eligible_by_size` is true (fewer than ~30 changed lines), and
- no single hunk touches program logic — the diff is confined to docs, comments, config/manifest values, dependency-version bumps, or string/copy edits.

When in doubt (any logic touched, or borderline size), do NOT take the fast path — run the full loop. The fan-out's value is independent perspectives on substantial code; a typo or a version bump doesn't earn six agents plus scorers.

**Fast path:** run **no conditional agents** (#7–#10) — a logic-free sub-30-line diff can't earn a structural proposal, an intent reconciliation, or the `gh` calls Agent #10 costs. Still run the Step 4a static-analysis pass (it's a deterministic subprocess, near-zero token cost, and catches secrets/SAST), then spawn **one** review subagent (`model: sonnet` — a sub-30-line, logic-free diff doesn't earn the top tier) covering the union of Agents #1 (CLAUDE.md), #2 (bugs), #4 (comments), and #5 (security) — pass it the diff, the learnings file, and the style default. Score its findings with **one** batched Haiku scorer (Step 6), then run Steps 7–14 exactly as normal (auto-fix / ask / test / commit / evidence gate / push). Report it as a single fast-path cycle. If that reviewer surfaces anything that changes program logic (an applied fix that isn't doc/config/comment-only), fall back to the full loop from cycle 1 — the fast path's premise (no logic under review) no longer holds.

### Fast-path re-entry — the follow-up commit after a clean exit

You already ran the loop this session, reached a clean exit, then made a **small follow-up commit** (a comment, a doc line, a config tweak) — often to satisfy review feedback or your own polish. The pre-push gate will (correctly) block it: the tip changed, so this exact state hasn't been reviewed. **Do not** reach for `record-reviewed.sh` by hand to clear it — that stamps "reviewed" on something the loop never saw (see Step 14).

Instead, re-enter here cheaply. Diff the new commit against the last reviewed sha (`git diff <last-reviewed-sha>...HEAD`), then:

- **Fast-path-eligible** (Step 3b's test on that delta: under ~30 changed lines, no program logic) → run the fast path on the delta only: Step 4a static analysis + one combined reviewer + one scorer, then `record-reviewed.sh`. This is ~10 seconds and ends with a *legitimate* reviewed stamp.
- **Genuinely beneath even that** (e.g. a one-word typo fix in a comment) → `record-skipped.sh "<reason>"` (Step 14). Honest, auditable, one line.
- **Touches logic, or you're unsure** → run the full loop from cycle 1 on the delta. The re-entry is a shortcut for *trivial* follow-ups, not a way to shrink review of real changes.

The point: make the honest lightweight path as cheap as the dishonest shortcut was, so there's never a reason to fake the stamp.

## Step 4: Main Loop

```
cycle = 1
max_cycles = 3

while cycle <= max_cycles:
    a. Run the static-analysis pass (Step 4a below): the static-analysis skill (--diff --fix) plus the project linter --fix if detected. Stage what changed; collect the deterministic tool findings.
    b. Run the parallel review subagents (Step 5) over this cycle's REVIEW SCOPE (see below). Each returns findings + suggested fixes. In cycle 1 only, and only if Step 4b (run once, before the loop) established a reviewable intent, also spawn Agent #9 (intent reconciliation).
       REVIEW SCOPE:
         - cycle 1: the full branch diff, `git diff origin/<base_branch>...HEAD` — nothing has been reviewed yet.
         - cycles 2+: only the changes THIS loop has made since it last reviewed, i.e. `git diff <sha-at-end-of-prev-cycle>...HEAD` (the fix commit(s) from the previous cycle). The rest of the branch was already reviewed in cycle 1; re-reviewing it re-pays the whole cost for code that didn't change. Reviewing the fix delta still catches fix-induced regressions, which is the only new risk a later cycle introduces.
       Record the current HEAD sha at the end of each cycle (Step 10) so the next cycle can diff against it.
    c. For each finding, spawn a Haiku scorer subagent (Step 6). Score 0-100.
    d. Bucket by score AND risk profile (Step 8a):
       - structural (Agent #7) or intent-reconciliation (Agent #9), any score → ask-user (never auto-apply)
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

On a clean loop exit, run the manual-testing evidence gate (Step 13) before the final report/auto-push (Step 14). If the gate's testing uncovers a real issue, fix + commit + restart the loop from cycle 1 (see Step 13).

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

## Step 4b: Establish PR Intent (for Agent #9)

Agent #9 (intent reconciliation, Step 5) reviews the change against what it is *supposed* to do, so it needs an accurate statement of intent — and it must be **intent, not a description of the code**. Establish this once, before the loop.

1. **Gather intent sources** (most trusted first): the linked issue / acceptance criteria, the PR description, the branch's commit messages, the title. With no PR yet (local branch), the commit messages + issue are the intent.
2. **Gate — decide whether Agent #9 runs at all.** Skip it (and the rest of this step) when the change has no reviewable intent to model against: dependency bumps, pure refactors/renames, formatting, config-only changes, or any diff whose purpose can't be stated as intended *behavior*. It earns its cost only on feature / behavior-changing work with a derivable goal.
3. **Build the intent statement — do NOT edit the PR description here.** Distil the sources into an internal statement of the change's purpose and intended behavior for Agent #9. Keep it to GOALS ("users can reconnect a third-party account"), never claims about what the code does or that an edge case is handled — an intent derived by reading the implementation just mirrors the code and blinds Agent #9 to the omissions it exists to catch. If the sources are too thin to state a goal: derive one from the issue/commits, or (interactive runs only) ask the author; if none can be established, gate Agent #9 off (step 2). The description itself is made accurate and complete *later* — **Step 14 reconciles it against the final reviewed change**, when doing so is safe (the code is final, so describing it can't launder a bug into intent) and useful (the PR ends merge-ready).
4. The resulting intent statement is what Agent #9's stage 1 consumes. Treat it as *desired behavior to be verified against the code*, not as ground truth about what the code does.

## Step 5: Parallel Review Agents

Spawn the review subagents in parallel (single message, multiple Agent tool calls). Agents #1–#6 always run. Agents #7 (structural simplification) and #8 (observability coverage) run **only on substantial diffs**; Agent #9 (intent reconciliation) runs **only in cycle 1 and only when Step 4b established a reviewable intent**; Agent #10 (prior review feedback) runs **only in cycle 1 and only when `gh` can reach the repo** — see each agent's gating rule.

**This cycle's review scope** (Step 4 loop, step b): `git diff origin/<base_branch>...HEAD` on cycle 1, or `git diff <prev-cycle-sha>...HEAD` on cycles 2+. Below, "the diff" means this scope; "the whole changed files" means those files' full contents at HEAD.

**Two agent classes — they get different context:**

- **File-scoped** — **#1 CLAUDE.md, #2 bugs, #4 comments**. These reason *within* a file, so give them the **whole changed files**, not just the diff. Omission bugs — state that should reset/invalidate but doesn't, a contract left unenforced, an error path that logs instead of throwing, a flag set before the action it gates — are invisible in a diff-of-additions and only surface against the full file. (Measured on this skill's eval: whole-file flipped a modified-file omission miss from 1/3 → 3/3; diff-only stayed blind. See `evals/`.)
- **Diff-scoped** — **#3 history, #5 security, #6 tests, #7 structural, #8 observability, #10 prior review feedback**. These reason *across* files and relationships, so give them the whole cycle diff (they may still read *beyond* it per their rules — the scope only bounds what counts as "under review"). One agent each.

**Batching the file-scoped agents (context budget).** Don't hand one agent every changed file (attention dilutes — measured: whole-PR context tanked recall to 0) nor spawn one agent per file (needless fan-out and cost). Instead run:

```
python3 ~/.claude/skills/review-loop/batch-files.py <this-cycle's diff-range>
```

It bin-packs the changed files into **batches under a ~1500-line whole-file budget** and lists any oversized file to handle by diff-plus-enclosing-scope. **Spawn one instance of each file-scoped agent per batch, in parallel**, each receiving the whole contents of its batch's files plus the diff of what changed in them. On a normal PR this is a single batch = one instance each (identical to before); it only fans out when the changed files exceed the budget — which is exactly where attention-splitting starts to hurt. Batches are disjoint file sets, so instances of the same agent never produce duplicate findings.

Each agent must also receive:
- The contents of `.git/info/review-loop-learnings.md` if it exists, with instructions: "If a finding matches anything in the Dismissed list, do not flag it."
- The agent's specific focus (below)
- The style default below (verbatim)
- A required output shape: a JSON-like list of `{file, line_range, description, suggested_fix, reasoning}`

**Model tier (pass to the Agent tool's `model` param):** pin **every** review agent to `sonnet`. Rationale and the decision record: `references/model-choice.md` (short version — Sonnet 5 lands near Opus 4.8 on review-defect-finding, so the top tier no longer buys enough to justify its cost, and a single review fan-out was burning a whole Opus session).

- **All review agents — pin to `sonnet`**: **#1 CLAUDE.md**, **#2 bugs**, **#3 git history**, **#4 comments**, **#5 security**, **#6 test coverage**, **#7 structural**, **#8 observability**, **#9 intent-recon**, **#10 prior review feedback**.

`sonnet` currently resolves to Sonnet 5, and the pin is a *ceiling* not a floor: on an Opus session it pins the deep agents (#2/#5/#7/#9) *down* to Sonnet 5 (the savings); on a Haiku session it pins them *up* to Sonnet 5 (deep reasoning still gets a capable model). If you ever want Opus back on a specific agent, unpin **#5 or #7** first — they're single calls, so Opus there is cheap. Leave **#2 pinned regardless**: it's the only deep agent that's batched (a PR that packs into 3 batches runs 3 instances of #2), so its fan-out is what actually burns the session on a big diff.

**Read `references/agent-roster.md` before spawning.** It carries the style-default paragraph every agent receives verbatim, plus the focus brief for each of #1–#6:

| # | Agent | Scope |
| --- | --- | --- |
| 1 | CLAUDE.md compliance | file-scoped, whole-file, batched |
| 2 | Bug scan — commission *and* omission | file-scoped, whole-file, batched |
| 3 | Git history | changed regions, via `git log -p -L` / `git blame` |
| 4 | Code comments compliance | file-scoped, whole-file, batched |
| 5 | Security | diff |
| 6 | Test coverage | diff |

### Agents #7, #8, #9, #10 — conditional (focus detail in `references/conditional-agents.md`)

Evaluate each gate every run; the gate is here, the focus/scoring/routing is in the reference. When a gate fires, **Read `references/conditional-agents.md`** for that agent's full instructions before spawning it.

- **#7 Structural simplification** `[sonnet]` — spawn on **substantial diffs**; skip when ALL hold: diff < ~150 changed lines, no file past ~800 lines, and pure bugfix/config/dependency bump. Reads beyond the diff. Scored on value-vs-risk, **always ask-routed** (never auto-applied).
- **#8 Observability coverage** `[sonnet]` — spawn when the diff is substantial/risky (#7's threshold) **AND** the repo already has an observability convention (logger/metrics/error reporter). Skip if the project logs nothing. Normal Step 6 rubric; fixes usually additive/auto-applied.
- **#9 Intent reconciliation** `[sonnet]` — spawn **only in cycle 1** when Step 4b established a reviewable intent. Two stages in separate contexts (spec from intent only → reconcile against code). **Always ask-routed**; highest false-positive rate — lean on the Dismissed list.
- **#10 Prior review feedback** `[sonnet]` — spawn **only in cycle 1**, and only when `gh` is authenticated and the repo has a GitHub remote. Mines review comments on past merged PRs that touched the same files and checks whether any apply again here. Skip on a repo with no PR history for the changed files. Normal Step 6 rubric; findings carry a citation to the prior comment.

## Step 6: Haiku Scoring

**Score per review agent, not per finding.** Spawn **one Haiku scorer subagent per review agent that returned findings** (so the scorers run in parallel, one alongside each finder). Each scorer receives that agent's *entire* finding-list and scores every finding in a single pass. Do NOT spawn one scorer per finding — that re-ships the diff once per finding and is the loop's biggest token sink. If a single agent returned an unusually large batch (>~12 findings), split it across two scorer calls to keep each pass careful, but never go back to one-per-finding.

The scorers stay independent from the finders (a fresh context that didn't generate the findings), so the quality intent — an independent rater — is preserved; you're only collapsing redundant diff copies.

Give each scorer:

- **Only the diff hunks the findings reference** — not the whole diff. Use the slicer to extract exactly those hunks deterministically:

  ```bash
  python3 ~/.claude/skills/review-loop/slice-hunks.py <diff-range> <file:start-end> [<file:start-end> ...]
  ```

  where `<diff-range>` is this cycle's review scope (`origin/<base_branch>...HEAD` on cycle 1, `<prev-cycle-sha>...HEAD` on cycles 2+) and each remaining arg is a finding's `file` plus its `line_range`. It prints only the hunks overlapping those ranges, grouped by file — no eyeballing, same slice every time. (For findings that cite code *beyond* the diff, the slicer won't capture it — read that region from the file and add it manually. This is expected for the file-scoped agents #1/#2/#4, whose whole-file review can flag an omission at an unchanged line, and for #3/#7/#8 by their nature.)
- The relevant `CLAUDE.md` paths
- The finding-list (each `{file, line_range, description, reasoning}`)
- The learnings file contents
- This rubric (verbatim), instructing it to **return one integer per finding, keyed by finding**, scoring each independently of the others in the batch:

**Read `references/scoring-and-routing.md`** for the rubric to pass verbatim (the 0-100 anchors, the Dismissed/Accepted adjustments) and for the two agents that score on a different basis — #7 structural on value-vs-risk, #9 intent on plausibility × impact-if-true. Both are always ask-routed regardless of score.

## Step 7: Apply Auto-Fixes (≥80)

For each ≥80 finding, in dependency order (same file → process top-to-bottom by line number to keep line refs valid):

1. Read the file
2. Apply the `suggested_fix` via Edit
3. If the suggested_fix is unclear or conflicts with current state, drop the finding to the 50-79 bucket so the user is asked

## Step 8a: Risk profile — decide which 50-79 findings need a human

A 50-79 confidence score means *you* aren't sure, not necessarily that the *user's* input is required. Cheap-to-undo, low-blast-radius fixes don't deserve an interruption — just apply them and let the user override later if they object.

Before asking, classify each 50-79 finding on three dimensions. A finding goes to **auto-fix** when ALL of the following are low-risk; otherwise it goes to **ask-user**.

The three dimensions — **reversibility**, **blast radius**, **forward-binding** — and the three hard rules that override the matrix are in **`references/scoring-and-routing.md`**. Read it before classifying.
**Bucket deterministically once each finding is classified.** After scoring (Step 6) and the risk classification above, assemble one JSON object per finding — `{id, agent, score, risk: "low"|"high", always_ask: bool}` — and route them with:

```bash
echo '<findings-json>' | python3 ~/.claude/skills/review-loop/bucket.py
```

It emits `{auto_fix, ask, skip}` applying the exact thresholds (≥80 → auto; 50-79 low-risk → auto, else ask; Agent #7/#9 → always ask; <50 → skip) so the routing can't drift between runs. The judgment stays yours — the *score* (Step 6) and the *risk* and *always_ask* flags (this step) — the script only combines them.

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

After committing, record this commit's sha (`git rev-parse HEAD`) as the previous-cycle marker so the next cycle's review scope (Step 4 loop, step b) diffs against it. If the cycle made no commit (nothing to fix), the marker stays where it was.

## Step 11: Capture Learnings

On Step 8b outcomes, record learnings in `.git/info/review-loop-learnings.md` (two sections: **Dismissed**, **Accepted patterns**). It's re-shipped to every agent, so keep it a curated index, not a log.

**Also record every Agent #10 finding that survived** — including ones auto-fixed at Step 7, which never reach Step 8b. #10 is the only agent whose findings come from outside the repo (`gh` review history), and it runs at most once per branch, so an unrecorded #10 finding costs the same API calls to rediscover next time. Write it to **Accepted patterns** with its citation intact ("PR #1042, @jakecoble: don't call this from the request path"). This is how a repo's most-repeated human review feedback migrates from GitHub into the local learnings file, where Agents #1–#6 see it for free on every subsequent run.

Do the edits with `learn.py` — you judge match/novelty/section; the script does the dated surgery:
- Re-match of an existing entry → `python3 ~/.claude/skills/review-loop/learn.py bump <file> "<substring>"` (bumps its date to today — the freshness signal Step 2a depends on).
- Novel entry → `learn.py add <file> --section dismissed|accepted "<text, no date>"` (stamps today's date; creates the file/sections if missing).
- Cap fallback → `learn.py prune <file>` (evicts oldest non-PATTERN, dismissed first; PATTERN entries never auto-pruned).

For the entry shape, the dedup/promote judgment, the per-Step-8b-outcome mapping, and the cap/split fallbacks, **Read `references/learnings-format.md`**. When in doubt whether an entry is worth writing, don't — the file's value is being scannable, not exhaustive.

## Step 12: "Remember X" Requests During the Session

If the user says "remember X", "always check Y here", "this repo cares about Z", or similar at any point during the session, immediately append to `.git/info/review-loop-learnings.md` under the appropriate section (Dismissed for "stop flagging…", Accepted for "always flag…"). Acknowledge with one sentence. Do not derail the loop.

If the user explicitly says "remember globally" or "remember for all repos", offer to also write to `~/.claude/projects/-home-narthur/memory/` as a separate auto-memory entry.

## Step 13: Manual-Testing Evidence Gate

Runs **only after everything else passes** — a clean loop exit (auto-fix bucket empty, tests green, no unresolved high-risk findings). It is the last gate before Step 14's report/auto-push.

**Skip entirely** (say so in one line in the final report) when either:

- **No PR exists** for the branch (`gh pr view` fails) — there's nowhere to attach evidence *yet*. This is **deferred, not dropped**: Step 14 records the deferral (`.git/info/review-loop-pending-report.md`) and Step 0c runs this gate once a PR appears. Only genuinely skip when the second condition also holds.
- **The diff changes no runtime functionality** — docs, comments, config, dependency bumps, CI-only changes, or pure refactors already pinned by tests. The gate is about *changed behavior*, and when in doubt, run it.

Otherwise the gate is active — **Read `references/evidence-gate.md`** and follow it: 13a (check the PR for sufficient existing evidence) → 13b (stand up the app and produce evidence yourself if missing — playwright for UI, real requests for API/CLI) → 13c (publish to the PR; or on a found issue, stop, fix, and restart the loop from cycle 1, capped at 2 restarts; or report "can't test" and don't push).

## Step 14: Final Report and Auto-Push

### Reconcile the PR description, then post the summary comment

On a clean loop exit with a PR: reconcile the description so it is accurate and complete for the now-final reviewed change (this is the counterpart to Step 4b, which deliberately left it alone during review), then post the report block as a PR comment. Skip the reconcile on a cycle-limit exit or a test-failure short-circuit. On a clean exit with **no PR yet**, both the reconcile and the comment are **deferred** — write the report to `.git/info/review-loop-pending-report.md` (per `references/report-format.md`) so Step 0c flushes them when the PR appears; the comment posts directly on any terminal exit where a PR already exists.

Both procedures in full: **Read `references/report-format.md`.**

### Record the reviewed commit

On a **clean loop exit** (auto-fix bucket empty, tests green, no unresolved high-risk findings), record the reviewed HEAD so the pre-push review-gate recognizes it — **before** the auto-push decision below, so both this run's auto-push and any later *manual* push of the same HEAD pass the gate:

```bash
~/.claude/skills/review-loop/record-reviewed.sh
```

Skip this on a **cycle-limit** or **test-failure** exit — that tree isn't a converged, reviewed state, so it shouldn't be waved through a later push. (The gate itself lives in `~/.git-hooks/review-gate.sh`; it blocks pushing commits you authored whose tip isn't recorded here, bypassable with `REVIEW_GATE_BYPASS=1`.)

**`record-reviewed.sh` is this skill's completion stamp — it means the loop actually looked at this tip.** It is called *here, by the loop*, after a real review pass (full loop or the Step 3b fast path — both count). Do **not** hand-call it to clear the pre-push gate on a change the loop never examined: that records a review that never happened. If you make a tiny follow-up commit after a clean exit — a comment, a doc line, a config value — you have two honest options and this is not one of them:

- **Run the fast-path re-entry** (below) — it's cheap, and if it's genuinely fast-path-eligible it ends by calling `record-reviewed.sh` legitimately.
- **Record it as skipped**, if you judge it beneath even the fast path: `~/.claude/skills/review-loop/record-skipped.sh "<reason>"`. This clears the gate but writes a *distinct* state (skipped, with your reason) that never masquerades as reviewed. A reason is required, so the judgment is stated, not silent.

"It's just a comment" is precisely the rationalization the gate exists to catch. Judging a change beneath the loop is a legitimate call — making that call *silently look like a review* is not. Record-skipped keeps the judgment and the honesty.

### When to auto-push

Make this decision with the checker rather than re-deriving the checklist — pushing to the wrong branch or a non-converged tree is the costly mistake:

```bash
python3 ~/.claude/skills/review-loop/push-check.py --clean-exit \
  --gate-state <passed|skipped|blocked> [--unresolved-skip] \
  --branch <current> --default-branch <default>
```

Pass the loop-state flags you know (omit `--clean-exit` if the loop didn't converge); it checks the git facts itself (branch is the default? upstream configured?) and emits `{push, reason}`. **Push only when `push` is true**; when false, surface `reason` in the report and stop. The "When NOT to auto-push" cases below are exactly what it encodes — kept here as the spec.

When it says push:

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

The exact block to emit — and to reuse as the PR comment above — is in **`references/report-format.md`**.

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
