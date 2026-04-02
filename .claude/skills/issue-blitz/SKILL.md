---
name: issue-blitz
description: "Go through open issues one-by-one, assess each for actionability, and spawn background agents to fix actionable ones in isolated worktrees with PRs. Use when asked to blitz through issues, batch-fix issues, or auto-resolve open issues."
---

You are helping the user rapidly triage and resolve open issues. For each issue you present an assessment, and on approval you spawn a background agent in an isolated worktree to implement the fix and open a PR.

## What You Do

- Fetch all open issues for the current repo
- Present issues one at a time with a readiness assessment
- On user approval ("y"), spawn a background Agent (subagent_type: general-purpose, isolation: worktree, run_in_background: true) to fix the issue and create a PR
- On user decline ("n"), skip to the next issue
- Report PR URLs as background agents complete

## What You Don't Do

- You don't implement fixes yourself — you delegate to background agents
- You don't spawn agents without user approval
- You don't block on agent completion — present the next issue immediately

## Step 1: Fetch Issues

```bash
gh issue list --limit 100 --state open --json number,title,labels,assignees,body
```

## Step 2: Detect Default Branch

Before spawning any agents, detect the repo's default branch:

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Store this value (e.g., `development`, `main`) and pass it to every spawned agent.

## Step 3: Present Each Issue

For each issue, display:

- **Issue number and title**
- **What:** One-sentence summary of the problem
- **Complexity:** Trivial / Low / Medium / High
- **Risk:** None / Low / Medium / High
- **Ready for execution?** Yes / No / Borderline — with brief justification

If the issue is not ready, explain why (too vague, requires human judgment, large refactor without tests, needs design decisions, etc.) and recommend skipping.

Then ask: **Spawn agent?**

## Step 4: Spawn Background Agent

When the user approves, spawn an agent with these parameters:

- **subagent_type:** `general-purpose`
- **isolation:** `worktree`
- **run_in_background:** `true`

### Agent Prompt Template

The agent prompt MUST include all of the following:

1. Project context and the full issue details (number, title, body/description)
2. The specific files and lines to modify (from the issue)
3. Clear implementation steps
4. **Testing instructions:**
   - After implementing the fix, add or update tests to cover the change wherever possible
   - Check for an existing test file next to the modified file (e.g., `foo.test.ts` for `foo.ts`) or in a nearby `__tests__/` directory
   - If a test file exists, add test cases for the new/changed behavior
   - If no test file exists but the change is to a utility function or pure logic (not a React component with complex UI), create a new test file following the project's existing test patterns
   - For edge functions (supabase/functions/), skip tests unless a test harness already exists
   - Run `npm test -- --run` (or the project's test command) to verify tests pass before committing
5. **Branch and PR instructions:**
   - Create a new branch from `origin/{DEFAULT_BRANCH}` (the value detected in Step 2)
   - Commit the change
   - Push the branch
   - Create a PR using `gh pr create --base {DEFAULT_BRANCH}` that closes the issue
   - Use the `but` command instead of raw git for write operations (commit, push, branch). For read-only git operations (status, diff, log), regular git is fine. If `but` doesn't work (e.g., not a gitbutler workspace), fall back to regular git.
5. **PR format:**
   ```
   gh pr create --base {DEFAULT_BRANCH} --title "..." --body "$(cat <<'EOF'
   ## Summary
   - bullet points

   ## Test plan
   - bullet points

   Closes #{ISSUE_NUMBER}

   Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

## Step 5: Continue Loop

After spawning (or skipping), immediately present the next issue. Do not wait for the background agent to finish.

When a background agent completes, report the result (PR URL or error) inline between issue presentations.

## Step 6: Session End

When all issues have been presented, summarize:

- Total issues reviewed
- Issues spawned (with PR URLs as they complete)
- Issues skipped (with brief reasons)

## Tips

- **Pace**: Move quickly. The user just needs enough info to say y/n.
- **Conciseness**: Keep assessments to 3-4 lines max.
- **Batching**: Multiple agents can run in parallel — don't hesitate to have several in flight.
- **Skip generously**: If an issue needs design decisions, is a large refactor, or lacks clear acceptance criteria, recommend skipping. The goal is to knock out the clearly actionable ones.
- **Security issues**: Issues involving database migrations, RLS policies, or SECURITY DEFINER functions should be flagged as needing careful human review unless the fix is trivial and well-specified.
