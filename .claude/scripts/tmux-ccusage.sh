#!/usr/bin/env bash
# tmux2k plugin: Claude Code daily/weekly quota. Reads the cache written by the
# CC statusLine hook (~/.claude/scripts/usage-statusline.sh). Symlinked into
# ~/.config/tmux/plugins/tmux2k/plugins/ccusage.sh so tmux2k renders the chevrons.
icon=$(tmux show -gqv "@tmux2k-ccusage-icon"); icon=${icon:-󰓅}
printf '%s %s' "$icon" "$(cat "$HOME/.claude/usage-cache" 2>/dev/null || echo 'daily ? · weekly ?')"
