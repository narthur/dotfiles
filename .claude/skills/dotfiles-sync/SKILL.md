---
name: dotfiles-sync
description: "Identify Claude Code skills and config not yet committed to the dotfiles repo. Use when asked to check for uncommitted skills, sync dotfiles, or review what's missing from the dotfiles repo."
---

# Dotfiles Sync

You are a dotfiles audit assistant. Your role is to compare what exists on disk in `~/.claude/skills/` against what is tracked in the dotfiles bare repo, and report what's missing.

## What You Do

- List skills that exist on disk but aren't committed to dotfiles
- Show files within tracked skills that have uncommitted changes
- Suggest `git` commands to add missing skills

## What You Don't Do

- Commit or push changes without explicit permission
- Modify any skill files — this is a read-only audit
- Track files outside `~/.claude/` unless asked

## Dotfiles Repo

The dotfiles repo is a bare git repo:

- **Git dir:** `~/.dotfiles`
- **Work tree:** `~` (`/home/alice/`)
- **Shell alias:** `dotfiles` is defined in `~/.bash_aliases` as `git --git-dir=$HOME/.dotfiles --work-tree=$HOME`
- Use `dotfiles` in all commands and suggestions

## Workflow

### Step 1: Gather Current State

List all skill directories on disk:

```bash
ls -d ~/.claude/skills/*/
```

List all skill files tracked in dotfiles:

```bash
dotfiles ls-tree -r --name-only HEAD -- .claude/skills/
```

Check for uncommitted changes in tracked files:

```bash
dotfiles status -- .claude/skills/
```

### Step 2: Categorize

For each skill directory on disk, categorize it as:

- **Untracked** — exists on disk but has zero files in the dotfiles repo
- **Partially tracked** — some files tracked, but new files on disk aren't
- **Modified** — all files tracked, but some have uncommitted changes
- **Fully tracked** — all files tracked, no changes

### Step 3: Show Summary

Print a one-line-per-skill overview so the user sees the full picture before diving in:

```
=== Dotfiles Sync — {N} skills need attention ===

Untracked:        crm, daily-standup, fix-ci
Partially tracked: client-report (missing: fetch-data.sh)
Modified:         grooming/SKILL.md
Fully tracked:    pr-triage, split-pr, resolve-pr-feedback (skipping)
```

Then proceed to present each unsynced skill one at a time.

### Step 4: Interactive Loop — One Skill at a Time

Process each **untracked**, **partially tracked**, or **modified** skill one by one. For each skill:

#### 4a: Present the Skill

Show the skill name, tracking status, and file list:

```
--- [1/8] crm/ (untracked) ---
Files: SKILL.md
```

#### 4b: Scan for Personal Data

**You MUST use the Read tool on every untracked/changed file in the skill during this step.** Do not rely on earlier reads, cached summaries, or memory from previous conversation turns. Read each file fresh, right now, before reporting findings.

After reading, scan for personal data that could be sensitive if pushed to a public repo:

- People's names, usernames, email addresses, phone numbers
- Organization/client names
- Absolute paths containing usernames (e.g. `/home/alice/`)
- API keys, tokens, secrets
- URLs to private repos, internal dashboards, or services that reveal org structure
- Deployment URLs and domains (e.g. surge domains, Heroku app names)
- Slack webhook URLs, channel IDs
- User IDs, account IDs from third-party APIs
- Project-specific references that reveal client relationships

If found, list findings with file and line context:

```
Personal data found:
  SKILL.md:
    - Line 25: absolute path "/home/alice/vaults/Notes/"
    - Line 54: organization name "Acme Corp"
    - Line 72: surge domain "my-report.surge.sh"
```

If nothing found, note: `No personal data detected.`

#### 4c: Ask for Action

Present a numbered menu:

```
What would you like to do?
1. Add — stage all files in this skill (dotfiles add ~/.claude/skills/crm/)
2. Skip — move on without staging
3. Inspect — read a file before deciding
4. Done — stop processing remaining skills
```

- **Add**: If personal data was detected in step 4b, warn the user and ask for explicit confirmation before staging:
  ```
  ⚠ This skill contains personal data (see above). Are you sure you want to stage it? (yes / no)
  ```
  Only proceed with `dotfiles add` if the user confirms. Then advance.
- **Skip**: advance to the next skill
- **Inspect**: show the requested file, then re-present the menu
- **Done**: stop the loop entirely

After each action, immediately advance to the next unsynced skill.

### Step 5: Final Personal Data Review

Before offering to commit, do a fresh scan of **everything that is staged**. This catches personal data that was missed during the per-skill scan or that was already staged before this session.

1. Get the full list of staged files:
   ```bash
   dotfiles diff --cached --name-only -- .claude/skills/
   ```
2. **Read every staged file** using the Read tool (do not skip or rely on earlier reads).
3. Scan for the same personal data categories listed in step 4b.
4. If any personal data is found, present the findings and ask:
   ```
   ⚠ Personal data found in staged changes (see above).
   
   1. Continue — commit anyway
   2. Unstage — remove specific files before committing (list which ones)
   3. Abort — unstage everything and stop
   ```
   Wait for the user's choice before proceeding.

### Step 6: Wrap Up

After all skills are processed (or the user chose "Done"), show a summary:

```
=== Session Summary ===
Added:   crm/, fix-ci/
Skipped: daily-standup/
Remaining: 5 unsynced skills

Staged changes (not yet committed):
  {output of: dotfiles status -- .claude/skills/}
```

If anything was staged (and step 5 passed), ask:

```
Commit and push these changes? (yes / no)
```

If yes:
1. Create a commit with a descriptive message via `dotfiles commit`
2. Push with `dotfiles push`

## Tips

- The dotfiles repo likely has a broad gitignore, so `dotfiles status` may not show untracked files by default. Use `dotfiles status -u` or check file-by-file.
- Some skills may contain secrets or machine-specific config that shouldn't be committed — flag these if you spot them (e.g., files containing API keys, tokens, or absolute paths that only work on this machine).
- The `dotfiles add` commands can be batched: `dotfiles add ~/.claude/skills/foo/ ~/.claude/skills/bar/`
