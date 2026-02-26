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

### Step 2: Compare

For each skill directory on disk, check whether it has **any** files tracked in the dotfiles repo. Categorize each skill as:

- **Untracked** — the skill directory exists on disk but has zero files in the dotfiles repo
- **Partially tracked** — some files in the skill are tracked, but new files on disk aren't
- **Fully tracked** — all files on disk are tracked

Also check for **uncommitted changes** in tracked files:

```bash
dotfiles status -- .claude/skills/
```

### Step 3: Scan for Personal Data

For each **untracked** or **partially tracked** skill, read all files and scan for personal data that could be sensitive if pushed to a public repo. Flag any occurrences of:

- **People's names** — full names of real people (e.g. clients, coworkers, contacts)
- **Usernames** — GitHub handles, Slack usernames, npm usernames, email local-parts
- **Email addresses and phone numbers**
- **Organization/client names** — company names, project names tied to specific clients
- **Absolute paths** containing usernames (e.g. `/home/alice/`)
- **API keys, tokens, secrets** — anything resembling a credential
- **URLs** — to private repos, internal dashboards, or services that reveal org structure
- **IP addresses** — especially if labeled with a person's name or location
- **Slack webhook URLs, channel IDs**
- **User IDs, account IDs** — from third-party APIs

For each skill, list the specific findings with file and line context:

```
Personal data found in untracked skills:

  crm/SKILL.md:
    - Line 25: absolute path "/home/alice/vaults/Notes/"
    - Line 54: references "Jane Smith", "Bob Jones" by name

  daily-standup/SKILL.md:
    - Line 23: GitHub usernames "alice", "bob", "carol"
    - Line 25: internal user IDs
    - Line 31: org names "acme-corp", "client-co"
    - Line 148: goal slugs tied to specific clients

  daily-standup/fetch-data.sh:
    - Line 12: internal API base URL
    - Line 45: Slack webhook URL
```

This helps the user decide whether to:

- Commit as-is (if the repo is private)
- Redact/parameterize sensitive values before committing
- Skip committing certain skills entirely

### Step 4: Report

Print a combined summary with both the tracking status and personal data findings:

```
=== Dotfiles Sync — Skills Audit ===

Untracked skills (not in dotfiles):
- crm/ — ⚠ personal data found (see below)
- daily-standup/ — ⚠ personal data found (see below)
- fix-ci/

Partially tracked (new files on disk):
- client-report/ — missing: fetch-data.sh

Modified (uncommitted changes):
- grooming/SKILL.md

Fully tracked:
- pr-triage/
- split-pr/
- resolve-pr-feedback/

--- Personal Data Scan ---

  crm/SKILL.md:
    - Line 25: absolute path "/home/alice/vaults/Notes/"
    ...
```

Omit empty categories. Omit the personal data section if nothing was found.

### Step 5: Suggest Commands

For each untracked or partially tracked skill, suggest the `git add` command:

```bash
dotfiles add ~/.claude/skills/{skill-name}/
```

Do **not** run these commands — just print them for the user to review.

## Tips

- The dotfiles repo likely has a broad gitignore, so `dotfiles status` may not show untracked files by default. Use `dotfiles status -u` or check file-by-file.
- Some skills may contain secrets or machine-specific config that shouldn't be committed — flag these if you spot them (e.g., files containing API keys, tokens, or absolute paths that only work on this machine).
- The `dotfiles add` commands can be batched: `dotfiles add ~/.claude/skills/foo/ ~/.claude/skills/bar/`
