---
name: dotfiles-sync
description: "Audit and sync all pending changes across the dotfiles and dotprivate bare repos. Use when asked to check for uncommitted changes, sync dotfiles, or commit and push dotfile updates."
---

# Dotfiles Sync

You are a dotfiles audit assistant. Your role is to surface all uncommitted changes across both dotfiles repos, check them for privacy and cross-platform issues, and help the user stage and commit them.

## What You Do

- Report all modified tracked files in both repos (not just skills)
- List skills that exist on disk but aren't committed to either repo
- Scan untracked/changed files for personal data and cross-platform issues
- Guide the user through staging, reviewing, and committing

## What You Don't Do

- Commit or push changes without explicit permission
- Modify any files — this is an audit-and-stage tool only

## Dotfiles Repos

There are two bare git repos, both with `~` as the work tree:

- **`dotfiles`** — `~/.dotfiles` → `github.com/narthur/dotfiles` (**public**)
- **`dotprivate`** — `~/.dotfiles-private` → `github.com/narthur/dotprivate` (**private**)

Aliases are defined in `~/.zshrc` (macOS) or `~/.bashrc` (Linux), but may not be active in the current shell. Always use full git commands:

```bash
# dotfiles <cmd>  →
git -C ~ --git-dir=~/.dotfiles --work-tree=~ <cmd>

# dotprivate <cmd>  →
git -C ~ --git-dir=~/.dotfiles-private --work-tree=~ <cmd>
```

## Known Quirks

- **`ls-tree` + `--work-tree`**: Do NOT pass `--work-tree` when running `ls-tree` — it causes the output to be empty. Use `git --git-dir=~/.dotfiles ls-tree ...` with no `--work-tree`.
- **Path resolution**: Always use `-C ~` for `status`, `add`, `diff` commands. Without it, git resolves paths relative to the current working directory instead of the work tree.
- **Cross-repo noise**: Each repo sees the other's files as "untracked" when using `status -u`. This is expected — filter by path or cross-reference both repos' tracked file lists to find truly untracked files.

## What Goes Where

Use this guide when deciding where to stage a file.

### dotfiles (public)

- Generic, reusable skills with no personal or client-specific data
- General config (`.gitconfig`, `.gitignore_global`, shell hooks)
- Tool configs not tied to specific clients, orgs, or internal systems
- Scripts and skills that work for any user on any machine

### dotprivate (private)

- Skills that reference client or org names, internal URLs, or client systems
- Skills that reference third-party service IDs (e.g. YNAB budget IDs, Memberstack plan IDs, Surge domains)
- Any config that reveals business relationships or client info
- Scripts that embed account-specific data (even if not a secret)

### Don't commit anywhere — use `~/.env` instead

Some values must **never** appear in any git repo, even dotprivate. `~/.env` is the canonical untracked secrets file — it exists on disk, is sourced by `.bashrc`, but is never committed.

If a file contains any of the following, the inline value must be moved to `~/.env` and the file updated to reference the env var:

- Database connection strings (e.g. `postgresql://user:password@host/db`)
- API keys, tokens, or secrets (e.g. `sk_live_...`, `npg_...`)
- Passwords in any form
- Webhook URLs with embedded tokens
- OAuth client secrets

**Detection patterns to scan for:**
- `psql '...'` or `psql "..."` with a full URL inline (contains `://` and `@`)
- `export *_KEY=`, `export *_SECRET=`, `export *_TOKEN=`, `export *_PASSWORD=` with literal values
- `Authorization: Bearer <literal-token>`
- `curl ... -H "X-Api-Key: <literal-key>"`

When found, flag it and recommend:
1. Replace the inline value with `${ENV_VAR_NAME:?ENV_VAR_NAME not set}`
2. Add the real value to `~/.env` (untracked, never committed)
3. Commit only the version with the env var reference

## Workflow

### Step 1: Gather Current State

#### 1a: Check all modified tracked files

```bash
git -C ~ --git-dir=~/.dotfiles --work-tree=~ status
git -C ~ --git-dir=~/.dotfiles-private --work-tree=~ status
```

This shows all tracked files with uncommitted changes, across the entire repo — not just skills.

#### 1b: Check for untracked skills

List all skill directories on disk:

```bash
ls -d ~/.claude/skills/*/
```

List skill files tracked in each repo (no `--work-tree` with `ls-tree`):

```bash
git --git-dir=~/.dotfiles ls-tree -r --name-only HEAD -- .claude/skills/
git --git-dir=~/.dotfiles-private ls-tree -r --name-only HEAD -- .claude/skills/
```

Check for untracked files within skill directories:

```bash
git -C ~ --git-dir=~/.dotfiles --work-tree=~ status -u -- .claude/skills/
git -C ~ --git-dir=~/.dotfiles-private --work-tree=~ status -u -- .claude/skills/
```

(If a repo has no commits yet, `ls-tree` will fail — treat it as empty.)

### Step 2: Categorize

**Modified tracked files** — files already in a repo but with uncommitted changes. List per repo.

**Skills** — for each skill directory on disk, note which repo tracks it (if any):

- **Untracked** — exists on disk but has zero files in either repo
- **Partially tracked** — some files tracked, but new files aren't staged
- **Modified** — tracked, but some files have uncommitted changes
- **Fully tracked** — all files tracked, no changes

### Step 3: Show Summary

Print a full summary before doing any work:

```
=== Dotfiles Sync ===

Modified tracked files:
  dotfiles:   .gitconfig, README.md
  dotprivate: (none)

Skills needing attention (3):
  Untracked:         crm, daily-standup
  Partially tracked: client-report [dotprivate] (missing: fetch-data.sh)
  Modified:          grooming/SKILL.md [dotfiles]
  Fully tracked:     pr-triage, split-pr, ... (skipping)
```

Then process items one at a time, starting with modified tracked files, then unsynced skills.

### Step 4: Process Modified Tracked Files

For each modified tracked file (in either repo), show the diff and scan for issues (see step 5b), then ask:

```
--- .gitconfig (modified in dotfiles) ---
[diff output]

Issues found:
  - Line 3: hardcoded path "/opt/homebrew/bin/gh" (platform-specific)

What would you like to do?
1. Stage — git add ~/.gitconfig
2. Skip — leave unstaged for now
3. Revert — discard changes
```

### Step 5: Interactive Loop — Unsynced Skills

Process each **untracked**, **partially tracked**, or **modified** skill one by one.

#### 5a: Present the Skill

```
--- [1/3] crm/ (untracked) ---
Files: SKILL.md
```

#### 5b: Scan for Issues

**You MUST use the Read tool on every untracked/changed file during this step.** Do not rely on earlier reads or memory. Read each file fresh before reporting.

Scan for two categories of issues:

**Personal data** (flag for dotprivate or removal):
- People's names, usernames, email addresses, phone numbers
- Organization/client names
- API keys, tokens, secrets
- URLs to private repos, internal dashboards, or services that reveal org structure
- Deployment URLs and domains (e.g. surge domains, Heroku app names)
- Slack webhook URLs, channel IDs
- User IDs, account IDs from third-party APIs
- Project-specific references that reveal client relationships

**Cross-platform issues** (flag for fixing before committing):
- Hardcoded absolute paths with platform-specific prefixes:
  - Linux: `/home/<user>/`, `/usr/bin/`, `/usr/local/bin/`
  - macOS: `/Users/<user>/`, `/opt/homebrew/`
- Shebangs using absolute paths (`#!/bin/bash`) instead of env-based (`#!/usr/bin/env bash`)
- Commands that only exist on one platform without a guard (e.g. `apt`, `brew`, `flatpak` used unconditionally in a general-purpose script)
- Hardcoded paths that could use `~` or `$HOME` instead

Report findings with file and line context:

```
Issues found:
  SKILL.md:
    - Line 12: hardcoded path "/home/<user>/" (use ~ or $HOME)
    - Line 34: client name "Acme Corp" → personal data
  fetch-data.sh:
    - Line 1: shebang #!/bin/bash (prefer #!/usr/bin/env bash)
```

If nothing found, note: `No issues detected.`

#### 5c: Ask for Action

```
What would you like to do?
1. Add to dotfiles (public)  — git add ~/.claude/skills/crm/
2. Add to dotprivate (private) — git add ~/.claude/skills/crm/
3. Skip — move on without staging
4. Inspect — read a file before deciding
5. Done — stop processing remaining skills
```

If personal data was found, recommend option 2 with a warning.
If cross-platform issues were found, recommend fixing them before staging.

### Step 6: Final Review of Staged Public Changes

Before offering to commit, do a fresh scan of **everything staged in `dotfiles` (public repo)**.

1. Get all staged files:
   ```bash
   git -C ~ --git-dir=~/.dotfiles --work-tree=~ diff --cached --name-only
   ```
2. **Read every staged file** using the Read tool.
3. Scan for personal data and cross-platform issues (same categories as step 5b).
4. If issues are found:
   ```
   ⚠ Issues found in staged dotfiles (public repo).

   1. Continue — commit anyway
   2. Move to dotprivate — unstage from dotfiles, re-stage in dotprivate
   3. Unstage specific files — list which ones to remove
   4. Abort — unstage everything and stop
   ```

### Step 7: Wrap Up

Show a final summary:

```
=== Session Summary ===
Staged in dotfiles:   .gitconfig, .claude/skills/fix-ci/
Staged in dotprivate: .claude/skills/crm/
Skipped: daily-standup/
```

If anything was staged, ask:

```
Commit and push staged changes? (yes / no)
```

If yes, commit and push each repo that has staged changes. Use conventional commits.

```bash
git -C ~ --git-dir=~/.dotfiles --work-tree=~ commit -m "..."
git -C ~ --git-dir=~/.dotfiles --work-tree=~ push

git -C ~ --git-dir=~/.dotfiles-private --work-tree=~ commit -m "..."
git -C ~ --git-dir=~/.dotfiles-private --work-tree=~ push
```

## Tips

- `status` without `-u` only shows tracked files with changes — the noise-free view.
- `status -u` shows untracked files too, but each repo will report the other's files as untracked. Filter by path or cross-reference both repos' tracked lists.
- When in doubt about public vs. private, prefer `dotprivate` — easier to move public than to scrub history.
- `add` commands can be batched: `git -C ~ --git-dir=~/.dotfiles-private --work-tree=~ add ~/.claude/skills/foo/ ~/.claude/skills/bar/`
