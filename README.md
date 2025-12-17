# Linux Dotfiles

Personal dotfiles and scripts for my Linux desktop setup.

## Files

### Shell Configuration

- **`.bashrc`** - Bash shell configuration
  - Adds `~/bin` to PATH
  - Configures Docker host for Podman
  - Initializes zoxide for directory navigation

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

- **`bin/install-packages`** - Installs all system packages
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

1. Install packages: `~/bin/install-packages`
2. Configure postfix for local mail: `~/bin/configure-postfix`
3. Install crontab: `crontab ~/.config/crontab`

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

