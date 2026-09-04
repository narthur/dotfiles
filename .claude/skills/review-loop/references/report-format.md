# Step 14: PR description reconcile, summary comment, and the report block

### Reconcile the PR description (clean exit, PR exists)

On a clean loop exit, if a PR exists, make the PR description **accurate and complete** for the now-final reviewed change. This is the counterpart to Step 4b: 4b captured *intended goals* for review and deliberately left the description alone; this runs *after* review converges, so describing what the change actually does is correct rather than contaminating, and it's the moment to leave the PR merge-ready.

**When it runs — only when the change is done (converged):**
- **Clean exit** (loop converged): reconcile. This is the only state where "accurate and complete" is meaningful and stable.
- **Cycle limit reached**: **skip.** The loop didn't converge — open findings still need addressing, and fixing them will change the code, so a description written now goes stale immediately and would document known-open defects as "what the change does." It's reconciled on the eventual clean re-run instead. (Mirrors the auto-push and evidence-gate gates, which likewise hold off until the change is done.)
- **Test failure short-circuit**: skip — the tree is knowingly broken.
- **No PR** (local branch): skip; nothing to reconcile.

Then:
- Compare the current description against the final diff. Update it to state the purpose, the actual behavior (including notable edge cases and any decisions the review surfaced or resolved), and — if the repo's PRs use one — the test plan.
- **Preserve author intent and structure**: fill gaps and correct drift, don't rewrite wholesale, and never delete a human's rationale.
- Edit in place with `gh pr edit <n> --body …` — a low-risk update to your own PR.
- Do this even when the auto-push is being skipped (e.g. branch is `main`): an accurate description is still worth leaving behind.

### Post the summary comment to the PR

When a PR exists for the branch (`gh pr view` succeeds), post the same **Report format** below as a PR comment so the review outcome is visible on GitHub. Runs on any terminal exit — clean, cycle-limit, or test-failure — since each is a finished review.

```bash
gh pr comment <n> --body "$(cat <<'EOF'
<the report-format block>
EOF
)"
```

**No PR yet — defer, don't skip.** A fresh branch is pushed *after* the loop runs (the gate forces that order), so "no PR" is the normal first-branch case, not a reason to drop the summary. Write the report block — plus any evidence captured in Step 13 — to `.git/info/review-loop-pending-report.md` instead. Two things flush it, both running Step 0c's procedure (post the report, run the evidence gate, reconcile the description): (a) if you go on to create the PR **later in this same session**, flush it immediately (you still have this report in context); (b) otherwise Step 0c flushes automatically the next time the loop runs after the PR exists. Either way the summary and evidence reach the PR without the author having to notice they're missing.

If the comment post fails, note it in the report and continue — don't retry.

### Report format

```
review-loop complete: <N> cycle(s), <M> commits, pushed: <yes|no — reason>.
Evidence gate: <passed — existing evidence | passed — evidence captured & posted (link) | deferred — no PR yet (flushes via Step 0c) | skipped — no functional changes | blocked — <reason>>.
Measurement gate: <passed — plan posted (metric: <name>) | waived — <reason> | deferred — no PR yet (flushes via Step 0c) | skipped — <no user-facing change | repo has no measurement capability> | blocked — <gap>>.
PR description: <reconciled to final change | already accurate — no edit | deferred — no PR yet (flushes via Step 0c) | skipped — not converged (cycle limit / test failure)>.

Cycle 1: <summary>
Cycle 2: <summary>
...

Structural proposals (Agent #7 — not applied, your call):
- Blockers: <high-value simplifications that delete a layer/branch, or file-size breaches — the things worth doing before this merges>
- Nits: <smaller tidy-ups, listed briefly>
(Omit this section entirely if Agent #7 didn't run or found nothing.)

Intent questions (Agent #9 — reconciled against PR intent, not applied, your call):
- <each as a question: "intent says X; the code does Y / doesn't do Z — intended?" — ordered by plausibility × impact>
(Omit entirely if Agent #9 didn't run — skipped when the change had no reviewable intent (Step 4b) — or found nothing.)

Auto-applied low-risk 50-79 (no ask):
- <list with one-line summary each — visible to the user since they didn't see the ask>

Security findings below the action floor (confidence < 8/10 — considered, not actioned):
- <file:line — category — one-clause description (confidence N/10)>
(One line each, never a bare count. This is the ONLY place a wrongly-dropped security finding can
surface for a non-expert reader, so it is not collapsible the way the <50 bucket below is. Omit the
section entirely only when there were none.)

Threat model (Step 2b): <bootstrapped — N claims | updated — R re-verified, A added, D dropped | unchanged>.
Upstream security prompt (Step 2a): <in sync at claude-code X.Y.Z | DRIFT — vendored X.Y.Z, installed A.B.C; run `upstream-check.py --extract` to diff>.

Static-analysis (Step 4a): autofixed <count>; security/secret/SAST findings <resolved/surfaced>; quality residue by tool: <tool=N, …>; skipped tools: <list or none>.

Learnings sweep (Step 2a): <ran — dropped N (D dead-path, S stale), promoted P, now E entries | not triggered — <E> entries>.

Remaining 50-79 findings the user skipped or didn't address:
- <list>

Remaining <50 findings (low confidence, not surfaced):
- <count only, not detail>
```


## Backfilling a deferred report (Step 0c)

Reached when `.git/info/review-loop-pending-report.md` exists **and** a PR now exists for the
branch. (Pending file but still no PR → leave it in place and continue the run.)

1. Post the file's contents as a PR comment (`gh pr comment <n> --body-file .git/info/review-loop-pending-report.md`).
2. Run the Step 13 evidence gate and the Step 13.5 measurement gate now (the branch is pushed and testable) and reconcile the PR description (Step 14), which the no-PR exit couldn't do.
3. Delete the pending file.
4. If HEAD still equals the reviewed sha the deferral was recorded at (nothing changed since), this backfill **was** the reason to run — report what you posted and exit without re-reviewing. Otherwise continue into the loop normally to review the new commits.

