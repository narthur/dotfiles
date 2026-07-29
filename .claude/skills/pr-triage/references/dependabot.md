# Dependabot PRs — the auto-merge carve-out

Read this when the queue contains a Dependabot PR. It is the one standing exception to the
"never merge without explicit authorization" gate in SKILL.md.

### Dependabot PRs (auto-merge exception)

Dependabot PRs (`app/dependabot`) are the **one exception** to "never merge automatically". They are dependency bumps, not the user's own code, and the user has opted into hands-off handling for the low-risk ones. Handle them like this:

1. **Classify the bump** with the helper:

   ```bash
   ~/.claude/skills/pr-triage/dependabot-bump-type <number>
   # stdout: minor-patch | major | unknown
   # exit 0 = minor-patch, 1 = major, 2 = unknown
   ```

2. **Overlap guard — check for a competing human PR before auto-merging.** If an open non-Dependabot PR edits the same `package.json` this bump touches, auto-merging will pile conflict churn onto that human PR (it has to re-resolve the lockfile/version lines every time a bump lands). Run:

   ```bash
   ~/.claude/skills/pr-triage/dependabot-overlap <number>
   # exit 0 = overlap found → DO NOT auto-merge; defer to user
   # exit 1 = no overlap   → safe to auto-merge (still subject to the checks below)
   # exit 2 = error
   ```

   On exit 0, treat the bump as deferred: note it in the final request as "subsumed by / overlaps #<n> — held to avoid conflict churn" and move on. Do **not** auto-merge it even if it is green + `minor-patch`. (An action-only bump like `actions/checkout` touches no manifest and always reports no overlap.)

3. **Decide by state** (only when the overlap guard reports clear):

   - **Green + mergeable + `minor-patch`** → **auto-merge it** (the exception). Use the repo's default merge method, defaulting to squash: `gh pr merge <number> --squash` (or `--merge`/`--rebase` to match repo settings). Log it and move on. Do **not** add it to the final batched request — it's done.
   - **Green + mergeable + `major` or `unknown`** → do **not** merge. Defer to the final batched request under "Ready to merge" with the bump type noted (e.g. "major: 4.x → 5.x — your call"). Major bumps and unclassifiable titles (group updates, odd version strings) always need the user's judgment.
   - **CI failing** → do **not** try to fix a dependency bump in-tree. A genuinely failing bump usually means the new version breaks something, which is a decision for the user — defer it to the final request with the failing check named. Only re-run a check that is plainly transient (timeout, network, runner error); never hand-edit the dependency to make CI pass.

4. **Conflicts / behind base** → **never** manually rebase or force-push a Dependabot branch (it desyncs Dependabot and it'll just recreate the PR). Instead comment `@dependabot rebase` and move on; revisit the PR on a later pass once Dependabot has updated it:

   ```bash
   gh pr comment <number> --body "@dependabot rebase"
   ```

5. **Bot feedback** on Dependabot PRs is informational — don't block on it. Apply trivially-safe auto-fixes if `/drive-pr --non-interactive` handles them, otherwise leave it; the merge decision is driven by CI + bump type, not by review threads.

Everything Dependabot-related still goes in the activity log: classification result, each `@dependabot rebase` comment, each auto-merge (with SHA), and each deferral with its reason.

