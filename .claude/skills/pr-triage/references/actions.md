# Step 4 action playbook

One section per menu option. Read the section for the option that was selected. **Option 6 (merge)**
carries its own authorization gate — read it before acting.

### Step 4: Execute Selected Action

**Option 1 - Fix failing CI:**

1. **Review CI run history first.** Before re-running or fixing anything, check whether the failing check has already been re-run previously. Use `gh run list --branch <branch> --limit 5` to see recent runs. If a check has already failed multiple times across different runs, it's almost certainly a real bug — don't re-run, investigate and fix instead. Only re-run if this is the first failure and it looks transient (e.g. timeout, network error, resource exhaustion).
2. Use the worktree printed by the summary (`Worktree: <path>`) — `view`/`next` already checked the PR out there.
3. Identify failing checks and their logs.
4. Fix the issues directly in the worktree.
5. After fixes, commit and push from the worktree.

**Option 2 - Resolve feedback:**

1. Use the worktree printed by the summary — `view`/`next` already checked the PR out there.
2. Invoke the `/drive-pr` skill to handle the rest. It drives the PR toward mergeable and delegates the feedback dimension to the `resolve-feedback` skill (retrieving feedback, presenting options, implementing fixes, and marking each item resolved).
3. After the skill completes, return to PR assessment.

**Option 3 - Fix conflicts:**

1. Use the worktree printed by the summary (`Worktree: <path>`).
2. Determine the PR's actual base branch from the PR metadata — **never assume `main`**:
   ```bash
   gh pr view <number> --json baseRefName -q '.baseRefName'
   ```
3. From the worktree, fetch and rebase onto `origin/<base-branch>` (always use the remote base branch, never the local one, to avoid stale state):
   ```bash
   cd "<worktree>" && git fetch origin <base-branch> && git rebase origin/<base-branch>
   ```
4. Resolve conflicts.
5. Push updated branch: `git push --force-with-lease`.

**Option 4 - Request review:**

```bash
gh pr edit <number> --add-reviewer <username>
```

**Option 5 - Mark ready:**

```bash
gh pr ready <number>
```

**Option 6 - Merge PR:**

**Only execute this when the user has explicitly chosen to merge in the current turn** — either by selecting "Merge PR" from the Step 4 menu (interactive mode) or by picking the PR in the autonomous final batched request. Do not infer merge intent from action-category labels, "Next" selections, PR size, or the fact that autonomous mode is running. If you're about to run `gh pr merge` and you cannot point to the user's most recent message authorizing this specific merge, stop and ask instead.

**Exception — Dependabot:** a green, mergeable, `minor-patch` Dependabot PR is auto-merged in autonomous mode without explicit per-PR authorization, per the standing opt-in in "Dependabot PRs". This carve-out applies **only** to Dependabot bumps that classify as `minor-patch`; for any other PR the gate above stands.

```bash
gh pr merge <number> --squash  # or --merge, --rebase based on repo settings
```

**Option 7 - Close PR:**

```bash
gh pr close <number>
```

**Option 8 - Snooze:**

1. Ask the user how long to snooze (e.g. 1h, 4h, 1d, 3d, 1w), or accept inline if already specified
2. Run: `~/.claude/skills/pr-triage/pr-review-session snooze <number> <duration>`
3. The PR will be hidden from the triage list until the snooze expires, then automatically reappear

