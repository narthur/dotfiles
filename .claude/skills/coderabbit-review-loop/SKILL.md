---
name: coderabbit-review-loop
description: "CodeRabbit-CLI-specific local review loop. Use ONLY when you specifically want CodeRabbit (e.g. to validate against its rules, reproduce a cloud finding, or when review-loop is unavailable). For general pre-push review, prefer the `review-loop` skill, which is Claude-driven, runs 6 parallel review agents, and stores per-repo learnings. This skill runs `coderabbit review --agent` iteratively, auto-fixes Critical/Warning findings, commits locally, repeats, then pushes."
---

You are an expert code reviewer and fixer. Your job is to run the local CodeRabbit CLI iteratively, fix findings, and commit — repeating until the review is clean or the cycle limit is reached.

## Detecting Workspace Type

Before starting, check the current git branch:

```bash
git branch --show-current
```

- If branch is `gitbutler/workspace` → use GitButler commands for staging and committing
- Otherwise → use standard git commands

### GitButler Workspace

When in a GitButler workspace, use `but status` to identify the virtual branch associated with the current work. Stage files with `but rub <file> <branch>` and commit with `but commit <branch> -m "..."`.

## Step 1: Prerequisites Check

Verify the CodeRabbit CLI is installed and authenticated:

```bash
coderabbit --version 2>/dev/null || echo "NOT_INSTALLED"
coderabbit auth status 2>&1
```

If not installed, ask the user before installing:

```bash
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
```

If not authenticated, instruct the user to run `coderabbit auth login`.

The `--agent` flag requires CodeRabbit CLI v0.4.0 or later — if older, run `coderabbit update`.

## Step 2: Determine Base Branch

```bash
base_branch=$(gh pr view --json baseRefName -q .baseRefName)
```

If no PR exists for the current branch, ask the user to specify a base branch (e.g. `main` or `master`).

Then fetch the latest from origin so the review compares against the current remote state:

```bash
git fetch origin "$base_branch"
```

## Step 3: Iterative Auto-Resolution Loop

```
cycle = 1
max_cycles = 5  (default; user can override by specifying a number when invoking)

while cycle <= max_cycles:
    1. Run: coderabbit review --agent --base origin/<base_branch>
    2. Parse the structured findings
    3. If no Critical/Warning findings → break (done!)
    4. Auto-handle each Critical/Warning finding:
       - Read the referenced code
       - Execute the "🤖 Prompt for AI Agents" literally if present;
         otherwise apply the described fix
       - If ambiguous/risky: pause and ask the user
    5. If any fixes were applied: commit them locally (DO NOT push yet)
    6. cycle += 1

If cycle > max_cycles:
    Report: "Reached local auto-resolution cycle limit (N). Stopping."
    Show remaining unresolved findings.
```

### Severity Handling

- **Critical** — always auto-fix
- **Warning** — auto-fix if clearly valid; ask the user if ambiguous or risky
- **Info** — skip in the loop; report to user at the end so they can address manually if desired

### Committing Fixes

Use conventional commit format. **Do not push between cycles** — all commits accumulate locally.

**Standard git:**
```bash
git add <changed-files>
git commit -m "<type>(<scope>): <description>"
```

**GitButler workspace:**
```bash
but rub <file> <branch-name>
but commit <branch-name> -m "<type>(<scope>): <description>"
```

#### Conventional Commit Types

- `fix` — bug fixes (most common for review findings)
- `refactor` — code changes that neither fix bugs nor add features
- `feat` — new features
- `docs` — documentation changes
- `test` — adding or updating tests
- `chore` — maintenance tasks

The scope should reflect the area of code changed (e.g. module name, feature area).

## Step 4: Push

After the loop ends (clean, cycle-limit, or only Info-level findings remaining):

**Standard git:**
```bash
git push
```

**GitButler workspace:**
```bash
but push <branch-name>
```

## Step 5: Report

Summarize what happened:

```
CodeRabbit local review complete after N cycle(s). Pushed to <branch>.
```

If the cycle limit was reached, list remaining unresolved findings so the user can address them manually.

If only Info-level findings remain, summarize them in the report.

## Commands Reference

| Command | Purpose |
| --- | --- |
| `coderabbit review --agent --base origin/<branch>` | Run CodeRabbit locally with structured output |
| `coderabbit auth status` | Check CodeRabbit CLI auth |
| `coderabbit --version` | Check CLI version |
| `coderabbit update` | Update CLI to latest version |
| `gh pr view --json baseRefName -q .baseRefName` | Get PR base branch |

### Git Operations by Workspace Type

| Operation | GitButler Workspace | Standard Git |
| --- | --- | --- |
| Check status/branches | `but status` | `git status` |
| Stage file to branch | `but rub <file> <branch>` | `git add <file>` |
| Commit to branch | `but commit <branch> -m "..."` | `git commit -m "..."` |
| Push branch | `but push <branch>` | `git push` |
