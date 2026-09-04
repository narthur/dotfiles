# Finishing a run (Step 14): reconcile, record, push

Read this at Step 14. SKILL.md carries the four-step order and the script invocations; this file
carries the rules behind them.

## 1. Reconcile the PR description, then post the summary comment

On a clean loop exit with a PR: reconcile the description so it is accurate and complete for the
now-final reviewed change — this is the counterpart to Step 4b, which deliberately left it alone
*during* review, because describing code you are still reviewing launders a bug into intent. Then
post the report block as a PR comment.

Skip the reconcile on a cycle-limit exit or a test-failure short-circuit — that tree is not a
converged state and its description should not claim otherwise.

On a clean exit with **no PR yet**, both the reconcile and the comment are **deferred**: write the
report to `.git/info/review-loop-pending-report.md` (shape in `references/report-format.md`) so
Step 0c flushes them when the PR appears. The comment posts directly on any terminal exit where a
PR already exists.

## 2. Record the reviewed commit

```bash
~/.claude/skills/review-loop/record-reviewed.sh
```

On a **clean loop exit** only (auto-fix bucket empty, tests green, no unresolved high-risk
findings), and **before** the push decision — so both this run's auto-push and any later *manual*
push of the same HEAD pass the gate.

Skip it on a **cycle-limit** or **test-failure** exit: that tree is not a converged, reviewed
state, so it should not be waved through a later push. (The gate itself is
`~/.git-hooks/review-gate.sh`; it blocks pushing commits you authored whose tip is not recorded
here, bypassable with `REVIEW_GATE_BYPASS=1`.)

### The honesty rule

**`record-reviewed.sh` is this skill's completion stamp — it means the loop actually looked at this
tip.** It is called here, by the loop, after a real review pass (full loop or the Step 3b fast
path — both count).

Do **not** hand-call it to clear the pre-push gate on a change the loop never examined: that
records a review that never happened. If you make a tiny follow-up commit after a clean exit — a
comment, a doc line, a config value — there are two honest options, and hand-calling is not one:

- **Run the fast-path re-entry** (SKILL.md Step 3b). It is cheap, and if the change is genuinely
  fast-path-eligible it ends by calling `record-reviewed.sh` legitimately.
- **Record it as skipped**, if you judge it beneath even the fast path:
  `~/.claude/skills/review-loop/record-skipped.sh "<reason>"`. This clears the gate but writes a
  *distinct* state — skipped, with your reason — that never masquerades as reviewed. A reason is
  required, so the judgment is stated rather than silent.

"It's just a comment" is precisely the rationalization the gate exists to catch. Judging a change
beneath the loop is a legitimate call; making that call *silently look like a review* is not.

## 3. The push decision

```bash
python3 ~/.claude/skills/review-loop/push-check.py --clean-exit \
  --gate-state <passed|skipped|blocked> [--unresolved-skip] \
  --branch <current> --default-branch <default>
```

Pass the loop-state flags you know (omit `--clean-exit` if the loop did not converge). It checks
the git facts itself — is this the default branch, is an upstream configured — and emits
`{push, reason}`. **Push only when `push` is true.** When false, surface `reason` in the report and
stop.

Use the checker rather than re-deriving the checklist: pushing to the wrong branch or a
non-converged tree is the costly mistake, and a script cannot talk itself into it.

When it says push:

`git push`

If the push fails (network error, branch protection, missing upstream, non-fast-forward), surface
the error verbatim in the final report and continue — do not retry, do not force.

### When NOT to auto-push — the spec `push-check.py` encodes

- **Tests failed mid-loop** (Step 9 short-circuit). The branch is in a known-broken state; do not
  propagate it.
- **Cycle limit reached with unaddressed ≥80 findings.** The loop did not converge.
- **The user explicitly skipped a 50-79 finding without "remember as dismissal pattern".** That is
  an unresolved ambiguity they may still want to think about; let them push when ready.
- **No upstream configured for the branch.** Do not infer one; report and stop.
- **Branch is the repo's default branch (main/master).** Never auto-push to main; surface the
  unusual state instead.
- **The Step 13 evidence gate is blocked or hit its restart cap.** Untested (or known-broken)
  functionality does not get pushed on your say-so.
- **The Step 13.5 measurement gate is blocked or hit its restart cap.** An unmeasurable ship is a
  ship you cannot learn from, and the instrumentation belongs in this PR. (A *waived* gate is not
  blocked — that one pushes.)

When skipping the auto-push, end the report with `Next step: <reason>; push when ready.` Do not
pretend it was a clean exit.

## 4. Emit the report

The exact block — and the deferred-report file shape — is in `references/report-format.md`.
