# Obsidian Vault Sync

Two-way sync of the Obsidian vault to Backblaze B2 (S3-compatible) using
[`rclone bisync`](https://rclone.org/bisync/), scheduled outside of Obsidian.

## Overview

This replaces the Obsidian **remotely-save** plugin. Instead of the editor
syncing the vault, a standalone `rclone bisync` job mirrors the vault to a B2
bucket on a 30-minute schedule. The same script + config run on any machine;
only the scheduler differs per OS (launchd on macOS, cron on Linux).

Conflicts are resolved by *newest edit wins*, and — unlike remotely-save, which
silently clobbered the losing side — the older copy is always preserved as a
numbered file so nothing is lost.

| | |
|---|---|
| Provider | Backblaze B2 (S3-compatible) |
| Endpoint | `s3.us-east-005.backblazeb2.com` |
| Bucket | `narthur-obsidian` |
| Vault | `$OBSIDIAN_VAULT` (default `~/Obsidian/Main`) |
| Encryption | None — files stored plaintext in the bucket |
| Cadence | Every 30 minutes |

## Components

### 1. rclone remote (`~/.config/rclone/rclone.conf`)

Defines the `obsidianb2` remote (S3 backend pointed at Backblaze). **Tracked in
`dotfiles-private`.** It holds everything *except* the secret key. File mode is
`600`.

```ini
[obsidianb2]
type = s3
provider = Other
access_key_id = <B2 keyID>
region = us-east-1
endpoint = s3.us-east-005.backblazeb2.com
```

The `secret_access_key` is **not** stored in the config file. rclone reads it
at runtime from the environment variable `RCLONE_CONFIG_OBSIDIANB2_SECRET_ACCESS_KEY`
(rclone's `RCLONE_CONFIG_<REMOTE>_<KEY>` override mechanism), which is exported
from `~/.env` — an untracked, local-only file already sourced by the shell. This
keeps the secret out of both git repos. (The remote is named `obsidianb2`, not
`obsidian-b2`, because environment-variable names cannot contain hyphens.)

`~/.env`:

```bash
export RCLONE_CONFIG_OBSIDIANB2_SECRET_ACCESS_KEY=<B2 applicationKey>
```

### 2. Sync script (`~/bin/obsidian-sync`)

The wrapper around `rclone bisync`. Tracked in `dotfiles`.

```bash
obsidian-sync           # normal incremental two-way sync (used by the scheduler)
obsidian-sync resync    # ONE-TIME baseline — run once per machine before scheduling
```

Key flags it sets:

- `--conflict-resolve newer` / `--conflict-loser num` — newest edit wins; the
  losing copy is kept as a numbered file (e.g. `Note.conflict1.md`), never
  deleted.
- `--max-delete 25` — aborts the run if it would delete >25% of files on either
  side (guards against a missing mount or accidental mass deletion).
- `--resilient --recover` — tolerate transient failures and recover from an
  interrupted run / stale lock instead of demanding a manual `--resync`.
- `--compare size,modtime` — detect changes by size and modification time.

### 3. Filters (`~/.config/rclone/obsidian-bisync-filters.txt`)

Excludes device-specific state and tool caches that should not round-trip
through the bucket. Tracked in `dotfiles`.

```
- .DS_Store
- /.trash/**
- /.playwright-cli/**
- /.obsidian/workspace*
```

### 4. Scheduler — macOS (`~/.config/launchd/com.narthur.obsidian-sync.plist`)

A launchd agent that runs the script every 30 minutes (`StartInterval 1800`)
via `cron-run`, so output lands in `~/.local/log/obsidian-sync.log`. Tracked in
`dotfiles`. Installed/loaded by `~/bin/setup-launchd`.

### 4b. Scheduler — Linux

launchd is macOS-only. On Linux, run the same script from cron (installed by
`~/bin/setup-cron`):

```cron
*/30 * * * * $HOME/bin/cron-run obsidian-sync $HOME/bin/obsidian-sync
```

## How It Works

1. **Baseline (once per machine):** `obsidian-sync resync` establishes the
   bisync state — a snapshot of both sides that later runs diff against. Without
   it, a plain run errors out by design (no silent first sync). The baseline
   uses `--resync-mode newer` so the most recent copy of each file wins.
2. **Scheduled runs:** every 30 minutes the scheduler runs `obsidian-sync`,
   which compares the vault against the bucket, propagates changes both ways,
   and resolves conflicts as described above.
3. **State:** rclone keeps per-machine bisync state in its cache dir
   (`~/Library/Caches/rclone/bisync/` on macOS, `~/.cache/rclone/bisync/` on
   Linux), keyed on the local path and remote name. This is **not** shared
   between machines — each machine maintains its own baseline against the shared
   bucket.

## Running on Multiple Machines (Mac + Linux)

The script, rclone config, and filters are fully portable. To add a machine:

1. Ensure `rclone` is installed (it's in `.Brewfile` on macOS; via the package
   manager / `setup-linux` on Linux).
2. Pull `dotfiles` + `dotfiles-private` so the script and `rclone.conf` are
   present.
3. Run `obsidian-sync resync` **once** on that machine to create its baseline.
4. Install the scheduler for the OS (`setup-launchd` on macOS, the cron line
   above on Linux).

Each machine then two-way syncs independently to the same `narthur-obsidian`
bucket. Do not copy the rclone bisync cache dir between machines.

### Cross-platform gotchas

- **Filename case:** macOS (APFS) is case-insensitive by default; Linux is
  case-sensitive. Two notes differing only by case can coexist on Linux but
  collide on Mac.
- **Unicode normalization:** macOS stores filenames as NFD, Linux as NFC.
  rclone normalizes for comparison by default, so this is usually handled, but
  it's where an accented or emoji filename could surface a phantom conflict.

Neither affects typical Markdown vaults.

## Maintenance

```bash
# Watch the latest sync
tail -f ~/.local/log/obsidian-sync.log

# Run a sync manually right now
obsidian-sync

# Preview what a sync would do without changing anything
rclone bisync "$OBSIDIAN_VAULT" obsidianb2:narthur-obsidian \
  --filters-file ~/.config/rclone/obsidian-bisync-filters.txt --dry-run

# Browse the bucket
rclone lsd  obsidianb2:narthur-obsidian
rclone ncdu obsidianb2:narthur-obsidian   # interactive disk-usage browser
```

## Troubleshooting

**"cannot find prior Path1 or Path2 listings" / bisync refuses to run:**
- No baseline exists for this machine. Run `obsidian-sync resync` once.

**Run aborts with a `--max-delete` error:**
- More than 25% of files would be deleted on one side — usually because the
  vault path is wrong/empty or a mount is missing. Confirm `$OBSIDIAN_VAULT`
  resolves to the real vault before re-running. Override only if the mass
  deletion is genuinely intended.

**A run was interrupted and the next one complains about a lock / prior abort:**
- `--resilient --recover` normally self-heals on the next run. If it persists,
  re-establish the baseline with `obsidian-sync resync`.

**Conflict files appearing (e.g. `Note.conflict1.md`):**
- The same note was edited on two machines between syncs. The newest edit is the
  live file; the `.conflict*` copy is the older edit, kept so you can merge and
  delete it.

**Two tools fighting over the bucket:**
- Make sure the remotely-save plugin is disabled — running it alongside this job
  means both write to the same bucket.

## History

Migrated off the remotely-save Obsidian plugin in June 2026. The B2 bucket,
endpoint, and application key were reused from the plugin's former config, so no
re-upload of the existing ~12 GB of vault data was required — the first
`resync` only reconciled metadata and a few hundred differing files.
