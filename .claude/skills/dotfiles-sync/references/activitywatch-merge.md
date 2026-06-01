# ActivityWatch Settings Merge

## When This Matters

If you run ActivityWatch locally and have its `settings.json` synced across machines via dotfiles, pulling updates can overwrite local AW state with remote config. This reference explains how to preserve both.

## The Problem

**Scenario:** You have `~/.config/activitywatch/settings.json` tracked in dotfiles and pull an update that changes it. The pull overwrites your local file, but your *running* AW instance still has the old settings in memory.

Result: AW config is out of sync with disk, and when you restart AW, it loses the local tweaks.

## The Solution: Export → Pull → Merge → Import

The `pull-and-sync` script automates this:

1. **Export current AW state** (`aw-export`) — snapshot what the running instance has
2. **Pull both repos** — get the latest from GitHub
3. **Merge the snapshots** (`aw-merge`) — local state wins on conflicts, remote adds new entries
4. **Import back** (`aw-import`) — tell the running instance about the merged config
5. **Clean up** — remove temp files

## How It Works

- Local AW settings (from the snapshot) take precedence over remote changes
- Any new keys in the remote file are added (don't overwrite what AW has)
- Result is written back to disk and imported into the running AW instance

## Prerequisites

- `aw-export` and `aw-import` commands installed and on PATH
- `aw-merge` script available at `~/.claude/skills/dotfiles-sync/pull-and-sync` (bundled in this skill)
- ActivityWatch running on `localhost:5600`

## Manual Merge (if script isn't available)

If the script isn't working:

```bash
# 1. Export AW state before pulling
aw-export /tmp/aw-before.json

# 2. Pull normally
git -C ~ --git-dir=~/.dotfiles --work-tree=~ pull

# 3. Merge (local wins, remote adds new keys)
aw-merge /tmp/aw-before.json ~/.config/activitywatch/settings.json > /tmp/aw-merged.json
mv /tmp/aw-merged.json ~/.config/activitywatch/settings.json

# 4. Import back to running AW
aw-import

# 5. Verify
cat ~/.config/activitywatch/settings.json
```

## Skipping AW Sync

If you don't want AW sync on a particular pull:

```bash
pull-and-sync --no-aw
```

Or run the normal pull commands without the AW wrapper.

## Troubleshooting

**"aw-export not found"** — Install ActivityWatch and ensure `aw-export` is on PATH.

**"Connection refused"** — ActivityWatch is not running on `localhost:5600`. Start it or use `--no-aw`.

**Settings not updated in AW UI** — After `aw-import`, you may need to reload the AW webinterface. Check your browser's Activity Log to verify the merge worked.
