# Dotfiles

Personal dotfiles and scripts for Linux and macOS.

## Files

### Shell Configuration

- **`.bashrc`** - Bash shell configuration
  - Sources `.env` for environment variables
  - Adds `~/bin` to PATH
  - Configures Docker host for Podman
  - Initializes zoxide for directory navigation

- **`.env`** - Environment variables for shell scripts
  - `PROJECTS_DIR` - `/mnt/backup/ProgrammingProjects`
  - `Z_EXPERIMENTS_DIR` - Path to z-experiments project
  - `OBSIDIAN_VAULT` - Path to main Obsidian vault
  - `OBSIDIAN_DAILY_NOTES` - Path to daily notes directory

- **`.gitconfig`** - Git configuration
  - GitHub credential helper via `gh` CLI
  - Default branch set to `main`
  - Auto setup remote on push

### i3 Window Manager

- **`.config/i3/config`** - i3 window manager configuration
  - Mod key: Super (Mod4)
  - Default tabbed layout
  - Rofi as application launcher (`$mod+d`)
  - Volume controls via amixer (media keys and F1-F3)
  - Desktop background via feh
  - i3blocks status bar

- **`.config/i3blocks/config`** - i3blocks status bar configuration
  - 💼 Work time (from ActivityWatch)
  - 🐝 Beeminder next goal (via buzz)
  - 🔊 Volume level
  - 📅 Date and time

- **`.config/i3status/config`** - i3status configuration (fallback/reference)

### Scripts

- **`.local/bin/slack-handler`** - Protocol handler for slack:// URLs
  - Launches Flatpak Slack app when clicking slack:// links in browser
  - Firefox setup:
    1. Set `network.protocol-handler.expose.slack` to `false` in `about:config`
    2. Set `network.protocol-handler.external.slack` to `true` in `about:config`
    3. Restart Firefox
    4. Click a slack:// link and choose `~/.local/bin/slack-handler` as the handler

- **`bin/llm-local`** - Runs cheap, recoverable subtasks through a local model via the `llm` CLI
  - Modes: `filter`, `extract`, `redact`, `classify`, `run` (input read from stdin)
  - Defaults to `qwen2.5-coder:7b`; override with `LLM_LOCAL_MODEL`
  - Scoped to low-stakes, verifiable jobs — not for summarizing source a stronger model reasons over
  - See Fieldnotes "Local LLM Setup on Mac (Apple Silicon)" for rationale

- **`bin/get-work-time`** - Fetches productive work time from ActivityWatch
  - Queries ActivityWatch API for window events
  - Uses your configured categories from ActivityWatch settings
  - Filters for "Work" category events
  - Returns duration in seconds
  - Optional date argument: `get-work-time 2025-01-15`

- **`bin/sync-work-time`** - Syncs work time to Beeminder
  - Loops through last 7 days
  - Converts seconds to hours
  - Submits to Beeminder via buzz CLI

- **`bin/backup-urls`** - Downloads and archives URLs weekly
  - Reads URLs from `~/.config/backup-urls/urls.txt`
  - Keeps a year's worth of versioned backups
  - Creates `latest_*` symlinks for easy access
  - Backups stored in `~/.local/share/backup-urls/`

- **`bin/cron-run`** - Wrapper script for cron jobs
  - Adds timestamps to output via `ts`
  - Logs to `~/.local/log/<name>.log`
  - Usage: `cron-run <logname> <command> [args...]`

- **`bin/install-packages`** - Installs all system packages (Linux-focused; run `brew bundle` on macOS)
  - Apt packages from `~/packages.txt`
  - Brew packages from `~/.Brewfile`
  - Pipx packages (rofimoji)
  - Binary manager (bin) and binaries
  - GitHub CLI (gh)
  - asdf plugins (nodejs, pnpm, ruby)
  - Colored output with progress logging

### Cron

- **`.config/crontab`** - Cron job definitions
  - `sync-work-time` - Every 10 minutes
  - `dcli sync` - Hourly (Dashlane sync)
  - `backup-urls` - Weekly (Sundays at 3am)
  - Install with: `crontab ~/.config/crontab`

### Other Configuration

- **`.config/backup-urls/urls.txt`** - URLs to back up (one per line)

## Setup

This repo uses a bare git repository to manage dotfiles directly in `$HOME`.

### New Machine

```bash
# Clone the bare repo
git clone --bare https://github.com/narthur/dotfiles.git $HOME/.dotfiles

# Define the alias (add to .zshrc on macOS, .bashrc on Linux)
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# Don't show untracked files (the entire home directory)
dotfiles config --local status.showUntrackedFiles no

# Checkout the files
dotfiles checkout
```

If checkout fails due to existing files, back them up first:

```bash
mkdir -p ~/.dotfiles-backup
dotfiles checkout 2>&1 | grep -E "^\s+" | xargs -I{} mv {} ~/.dotfiles-backup/{}
dotfiles checkout
```

### Private Dotfiles

Sensitive files (e.g. private Claude skills) are tracked in a separate private bare repo:

```bash
# Clone the private bare repo (use HTTPS if SSH not configured)
git clone --bare git@github.com:narthur/dotprivate.git $HOME/.dotfiles-private
# or: gh repo clone narthur/dotprivate $HOME/.dotfiles-private -- --bare

# Define the alias (add to .zshrc on macOS, .bashrc on Linux)
alias dotprivate='git --git-dir=$HOME/.dotfiles-private --work-tree=$HOME'

# Don't show untracked files
dotprivate config --local status.showUntrackedFiles no

# Checkout the files
dotprivate checkout
```

### Post-Setup

1. Install packages: `~/bin/install-packages`
2. Configure postfix for local mail: `~/bin/configure-postfix`
3. Install crontab: `crontab ~/.config/crontab`

### Daily Usage

```bash
dotfiles status              # Check status
dotfiles add ~/.vimrc        # Track a new file
dotfiles commit -m "message" # Commit changes
dotfiles push                # Push to GitHub
```

## Mail (Cron Output)

Cron jobs send their output to your local mailbox via postfix.

**Read mail:**
- `mail` - Interactive mail reader
- `mail -H` - List messages
- `cat /var/mail/$USER` - View mailbox directly

## Dependencies

- [ActivityWatch](https://activitywatch.net/) - Time tracking
- [buzz](https://github.com/narthur/buzz) - Beeminder CLI
- [i3](https://i3wm.org/) - Window manager
- [i3blocks](https://github.com/vivien/i3blocks) - Status bar
- [rofi](https://github.com/davatorium/rofi) - Application launcher
- [zoxide](https://github.com/ajeetdsouza/zoxide) - Directory jumper
- [feh](https://feh.finalrewind.org/) - Image viewer / wallpaper setter
- [Dashlane CLI](https://cli.dashlane.com/) - Password and secret manager
- [postfix](http://www.postfix.org/) - Mail transfer agent (local delivery)
- [mailutils](https://mailutils.org/) - Mail reading tools
- jq, curl, bc, wget, moreutils - Command line utilities

