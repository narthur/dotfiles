# Step 9c: syncing the PR description (incl. breaking changes)

## Step 9c: Sync the PR Description (incl. Breaking Changes)

Feedback fixes (Step 1) and review-loop edits (Step 7) routinely make the original PR body stale — it may describe an approach that was changed, list changes that were dropped, or omit changes added while addressing review. Once **this pass produced no further code changes** (you're about to finish, or looping only to wait on checks), reconcile the body with reality.

1. Get what the branch actually does now vs. what the body claims:
   ```bash
   gh pr view --json title,body
   gh pr diff            # the real, current diff
   ```
2. Compare. If the body still accurately summarizes the current diff, **do nothing** — don't churn the description for style. Only rewrite when it's factually out of date: wrong/removed approach, changes described that no longer exist, or significant changes now present but unmentioned.
3. **Scan the diff for breaking changes** and make sure the body lists them. A breaking change is anything that would break an existing caller/user who upgrades without changing their code — e.g.:
   - **Public API contract**: removed/renamed exported function, type, field, or endpoint; changed signature, parameter order, or required params; changed return/response shape; changed status codes or error semantics; tightened validation.
   - **CLI behavior**: removed/renamed command, flag, or subcommand; changed default; changed output format that scripts parse; changed exit codes.
   - **Config / data / wire formats**: renamed/removed config keys or env vars; changed defaults; schema/migration that isn't backward-compatible; changed serialization.

   If the diff has any, the body must carry a clearly-labeled **`## Breaking changes`** section (use the repo template's equivalent if it has one) listing each as a bullet: *what broke* and *what callers must do to migrate*. If the diff has none, don't add an empty section. Judge from the actual diff, not the commit messages — a change flagged `feat` can still break a contract. When genuinely unsure whether something is public/breaking (e.g. an internal-but-exported helper), list it and say the exposure is uncertain rather than omit it.
4. If it's stale, update it — **preserving the repo's PR template and section structure** (don't flatten headings, checklists, "Closes #", or `<!-- -->` markers). Edit only the claims that drifted; keep the author's voice and any human-added context. Rewrite the title too if the scope changed enough that it's misleading.
   ```bash
   gh pr edit --body-file <file>     # write the reconciled body to a temp file first
   gh pr edit --title "<new title>"  # only if the title is now misleading
   ```
   Write the body via `--body-file` (not inline `--body`) to keep markdown/newlines intact. Use `$CLAUDE_JOB_DIR/tmp` for the temp file.
5. In **batch mode** (e.g. `pr-triage`), still do this — an auto-merged PR with a wrong description or an unlisted breaking change is exactly what leaves the stale-description mess. Note the update (and any breaking changes found) in your returned status.

This is a **description** sync, not a feedback reply: don't summarize the review discussion in the body, and don't announce "updated after feedback" — just make the description true.

